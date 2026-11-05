//
//  CardFormOnScreen.swift
//  sdkTests
//
//  The SDK takes a card only from the form registered under its ID, as a GopayCardForm on screen
//  is. Tests that only need a card held under an ID sync it through here.
//

import Foundation
@testable import sdk

/// Keeps the stand-in forms alive: the SDK holds a form's owner weakly, as it holds a real one.
private final class StandInForms: @unchecked Sendable {
    static let shared = StandInForms()
    private let lock = NSLock()
    private var owners: [String: CardFormOwner] = [:]

    func owner(for key: String) -> CardFormOwner {
        lock.lock(); defer { lock.unlock() }
        if let owner = owners[key] { return owner }
        let owner = CardFormOwner()
        owners[key] = owner
        return owner
    }
}

extension GopaySDK {

    /// Syncs `data` as the form registered under `formId` does, registering a stand-in form with
    /// no handlers first when none is on screen under that ID.
    func updateCardFormData(_ data: GopayCardFormData, formId: String) {
        let owner: AnyObject
        if let registered = self.owner(of: formId) {
            owner = registered
        } else {
            let standIn = StandInForms.shared.owner(for: "\(ObjectIdentifier(self))/\(formId)")
            registerCardFormReset({
                // A stand-in has no fields to empty.
            }, formId: formId, owner: standIn)
            owner = standIn
        }
        updateCardFormData(data, formId: formId, owner: owner)
    }
}
