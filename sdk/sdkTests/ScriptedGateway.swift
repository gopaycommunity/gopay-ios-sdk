//
//  ScriptedGateway.swift
//  sdkTests
//
//  A gateway in memory for the tests that need to hold an answer, never give one or see a request
//  dropped, without the shared `StubURLProtocol`: each test makes its own, so they run in
//  parallel. Its waits end with the task, as `DefaultNetworkClient`'s cancellable requests do.
//

import Foundation
@testable import sdk

/// Answers every request through `answer`, which may wait, hang or throw, and keeps what was sent.
final class ScriptedGateway: AsyncHTTPClient, @unchecked Sendable {
    typealias Answer = @Sendable (URLRequest) async throws -> (status: Int, body: String)

    let baseUrl = "https://gw.example/api/"
    private let answer: Answer
    private let headers: [String: String]
    private let lock = NSLock()
    private var sent: [URLRequest] = []
    private var dropped: [String] = []

    /// - Parameter headers: Response headers every answer carries, such as the gateway's `Date`.
    init(headers: [String: String] = [:], _ answer: @escaping Answer) {
        self.answer = answer
        self.headers = headers
    }

    /// Every request so far, in arrival order.
    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return sent
    }

    func requests(to pathSuffix: String) -> [URLRequest] {
        requests.filter { $0.url?.path.hasSuffix(pathSuffix) ?? false }
    }

    /// Paths of the requests that ended with their task cancelled, not with an answer.
    var droppedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return dropped
    }

    private func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        sent.append(request)
    }

    private func recordDropped(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        dropped.append(request.url?.path ?? "")
    }

    func makeURL(path: String) -> URL? { URL(string: baseUrl + path) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        do {
            let (status, body) = try await answer(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: headers.merging(["Content-Type": "application/json"]) { given, _ in given }
            )!
            return (Data(body.utf8), response)
        } catch is CancellationError {
            recordDropped(request)
            throw CancellationError()
        }
    }
}

/// Suspends until the task is cancelled and then throws `CancellationError`: a gateway that never
/// answers, or a clock that never gets there.
func untilCancelled() async throws -> Never {
    // An `AsyncStream` that never yields ends its iteration only with the task.
    let never = AsyncStream<Void> { _ in }
    for await _ in never {}
    throw CancellationError()
}

/// Holds whoever waits on it until the test opens it; open stays open. A wait ends early, with
/// `CancellationError`, when its task is cancelled. One waiter at a time.
final class AsyncGate: @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var waiting = false

    init() {
        var made: AsyncStream<Void>.Continuation!
        stream = AsyncStream { made = $0 }
        continuation = made
    }

    /// Whether something has come to wait.
    var hasWaiter: Bool {
        lock.lock(); defer { lock.unlock() }
        return waiting
    }

    private func arrived() {
        lock.lock(); defer { lock.unlock() }
        waiting = true
    }

    func open() {
        continuation.yield()
        continuation.finish()
    }

    func wait() async throws {
        arrived()
        for await _ in stream { break }
        try Task.checkCancellation()
    }
}
