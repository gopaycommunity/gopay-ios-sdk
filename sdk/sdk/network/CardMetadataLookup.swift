import Foundation

/// Backs the metadata half of ``GopaySDK/submitCardFormWithMetadata(formId:)``: asks
/// `POST /cards/bin-lookup` what the gateway knows about a card from its first eight digits, the
/// BIN, with the shareable key like the public key fetch.
///
/// The lookup never fails: no answer, an HTTP error (a 404 is the gateway not knowing the BIN), an
/// answer that cannot be read and one that takes longer than ``timeout`` are all "no metadata",
/// `nil`, with a warning in the debug log. Nothing is reported through `errorCallback`. Only a
/// cancellation of the caller passes through.
///
/// The BIN is card data. It goes into the request body and nowhere else: not into the warning,
/// not into an error, and the SDK keeps the body out of its operational data. Mirrors the Android
/// SDK's `CardMetadataLookup`.
struct CardMetadataLookup {
    /// How many digits of the card number the gateway is asked about.
    static let binLength = 8

    /// The browser SDK's limit, in seconds.
    static let defaultTimeout: TimeInterval = 3

    private static let unreadable = "the answer could not be read"

    private static let maxTextLength = 200

    let publicAPI: PublicAPI
    /// The limit on the whole lookup, not on its idle time.
    var timeout: TimeInterval = CardMetadataLookup.defaultTimeout
    /// Suspends for the given seconds and throws `CancellationError` when the task is cancelled.
    /// `Task.sleep` outside tests, which run the limit on their own clock.
    var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: AwaitChargeHooks.nanoseconds(for: seconds))
    }
    /// Where the warning of a lookup without metadata goes: `GopaySDK.logWarning(_:)`.
    let warn: @Sendable (String) -> Void

    /// How one lookup ended.
    private enum Outcome: Sendable {
        case found(CardMetadata)
        /// No metadata, with the reason the warning names.
        case noMetadata(reason: String)
    }

    /// What the request or the limit has to say when it ends.
    private enum Step: Sendable {
        /// The request ended, with or without metadata.
        case requestEnded(Outcome)
        /// The request was dropped because its task was cancelled.
        case requestDropped
        /// The limit passed.
        case limitPassed
        /// The limit was called off before it passed.
        case limitCalledOff
    }

    /// The metadata of the card whose number is `cardNumber`, digits only, or `nil`.
    ///
    /// The request and the limit run side by side, and whichever ends first decides; the other
    /// is cancelled, so a request past the limit is dropped rather than left to finish. A request
    /// the limit ended is reported as an `api_call` without an answer; one that ended because the
    /// caller was cancelled is not reported.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled, and nothing else.
    func lookUp(cardNumber: String) async throws -> CardMetadata? {
        let bin = String(cardNumber.prefix(Self.binLength))
        // ASCII digits only: the body is written by hand, and nothing else belongs in it.
        guard bin.utf8.count == Self.binLength, bin.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        let timeout = self.timeout
        let sleep = self.sleep
        let publicAPI = self.publicAPI
        let startedAt = Telemetry.now()
        let (outcome, limitEndedTheRequest) = await withTaskGroup(of: Step.self) { group -> (Outcome?, Bool) in
            group.addTask { await Self.ask(publicAPI, bin: bin) }
            group.addTask {
                // A sleep that ends early was cancelled: then the caller's cancellation or the
                // request's answer decides, not the limit.
                (try? await sleep(timeout)) != nil ? .limitPassed : .limitCalledOff
            }
            var outcome: Outcome?
            var limitEndedTheRequest = false
            for await step in group {
                switch step {
                case .requestEnded(let ended):
                    // An answer that crossed the limit on its way is too late to count.
                    outcome = outcome ?? ended
                case .limitPassed:
                    outcome = outcome ?? .noMetadata(reason: "no answer in \(Int((timeout * 1000).rounded())) ms")
                case .requestDropped:
                    // Dropped after the limit decided: the limit ended it, nobody else.
                    limitEndedTheRequest = outcome != nil
                case .limitCalledOff:
                    break
                }
                // The first to decide ends the other; the loop then hears how that one ended.
                if outcome != nil { group.cancelAll() }
            }
            return (outcome, limitEndedTheRequest)
        }
        try Task.checkCancellation()
        if limitEndedTheRequest {
            publicAPI.reportBinLookupWithoutAnswer(startedAt: startedAt)
        }
        switch outcome {
        case .found(let metadata):
            return metadata
        case .noMetadata(let reason):
            warn(Self.warning(reason))
            return nil
        case nil:
            // Neither decided, which only a cancelled caller brings about.
            throw CancellationError()
        }
    }

    /// The sentence is the Android SDK's, word for word. The reason in it is the same on both
    /// for an HTTP status, the limit, an unreadable answer and an SDK error's code; a failure
    /// that is not the SDK's is named by its type here and as `INTERNAL_001` there.
    static func warning(_ reason: String) -> String {
        "POST /cards/bin-lookup gave no card metadata (\(reason)), returning the payload without it"
    }

    private static func ask(_ publicAPI: PublicAPI, bin: String) async -> Step {
        do {
            let (body, response) = try await publicAPI.lookUpBin(bin)
            guard (200..<300).contains(response.statusCode) else {
                return .requestEnded(.noMetadata(reason: "HTTP \(response.statusCode)"))
            }
            guard let metadata = read(body) else { return .requestEnded(.noMetadata(reason: unreadable)) }
            return .requestEnded(.found(metadata))
        } catch is CancellationError where Task.isCancelled {
            return .requestDropped
        } catch let error as GopaySDKError {
            // The code only: a transport failure's message is the system's, not the SDK's.
            return .requestEnded(.noMetadata(reason: error.code.rawValue))
        } catch {
            // The type only: the message of a foreign failure is not the SDK's to print. A
            // cancellation nobody asked this task for ends here too, as `CancellationError`: it
            // is a lookup that failed, at once, not one to wait out the limit for.
            return .requestEnded(.noMetadata(reason: String(describing: type(of: error))))
        }
    }

    /// The gateway's answer as ``CardMetadata``, read as strictly as the browser SDK's
    /// `toCardMetadata` does. Without a `scheme` of VISA or MASTERCARD, or without a boolean
    /// `corporate`, there is no metadata at all. An optional field counts only in its documented
    /// shape: `brand` and `issuer` a non-empty text of at most 200 characters, `service_type`
    /// DEBIT or CREDIT, `issuer_country` three capital letters; anything else leaves that field
    /// out. No other field of the answer is passed on.
    static func read(_ body: Data) -> CardMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]),
              let fields = json as? [String: Any]
        else { return nil }
        let scheme: CardScheme
        switch fields["scheme"] as? String {
        case "VISA": scheme = .visa
        case "MASTERCARD": scheme = .mastercard
        default: return nil
        }
        // A JSON boolean only: `as? Bool` would also take the numbers 0 and 1.
        guard let corporate = fields["corporate"] as? NSNumber,
              CFGetTypeID(corporate) == CFBooleanGetTypeID()
        else { return nil }
        return CardMetadata(
            scheme: scheme,
            corporate: corporate.boolValue,
            brand: text(fields["brand"]),
            serviceType: (fields["service_type"] as? String).flatMap(CardServiceType.init(rawValue:)),
            issuer: text(fields["issuer"]),
            issuerCountry: (fields["issuer_country"] as? String).flatMap { isAlpha3($0) ? $0 : nil }
        )
    }

    /// Counted in UTF-16 units, as the browser SDK and Android count a string's length.
    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf16.count <= maxTextLength else { return nil }
        return text
    }

    private static func isAlpha3(_ text: String) -> Bool {
        text.utf8.count == 3 && text.utf8.allSatisfy { (0x41...0x5A).contains($0) }
    }
}
