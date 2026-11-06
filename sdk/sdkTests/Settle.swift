//
//  Settle.swift
//  sdkTests
//
//  Waiting for a state instead of pausing for a fixed time. The GitHub runner is many times slower
//  than a Mac and a pause that is plenty here is too short there, so a test waits for what it is
//  about to check, up to a limit far above what a loaded runner needs. The limit only matters when
//  the state never comes: the test then checks it as before and fails there.
//
//  The limit is wall clock time, so it is generous: under load a main actor test can wait seconds
//  for the main thread alone, and a state that does arrive costs nothing extra.
//

import Foundation
import Testing
import UIKit

/// How long a test waits for a state before it checks it anyway.
let settleTimeout: TimeInterval = 30

/// Polls `condition` until it holds or `timeout` has passed, and returns whether it held. Runs on
/// the caller's actor, so a main actor test reads its views on the main thread, and suspends
/// between reads, so the main queue and SwiftUI get to run in between.
///
/// It checks nothing itself: the caller `#expect`s the state after it, or wraps the call in one.
@discardableResult
func settle(
    timeout: TimeInterval = settleTimeout,
    isolation: isolated (any Actor)? = #isolation,
    until condition: @autoclosure () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if await condition() { return true }
        if Date() >= deadline || Task.isCancelled { return false }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

/// Waits for `condition` and fails the test where it is called if it never holds.
func expectSettled(
    _ condition: @autoclosure () async -> Bool,
    _ comment: Comment = "timed out waiting",
    timeout: TimeInterval = settleTimeout,
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let held = await settle(timeout: timeout, until: await condition())
    #expect(held, comment, sourceLocation: sourceLocation)
}

/// The value `read` returns once it has stopped changing: the same value twice in a row, a poll
/// apart. For a SwiftUI layout, which a loaded runner takes many times longer to finish.
func settledValue<Value: Equatable>(
    timeout: TimeInterval = settleTimeout,
    isolation: isolated (any Actor)? = #isolation,
    of read: () -> Value
) async -> Value {
    let deadline = Date().addingTimeInterval(timeout)
    var last = read()
    while Date() < deadline, !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 50_000_000)
        let next = read()
        if next == last { return next }
        last = next
    }
    return last
}

/// Lets everything already queued on the main queue run, `turns` hops deep, for the checks that
/// something did not happen. The form moves the focus in blocks it queues on the main queue, at
/// most two hops after the SwiftUI update that decides it, so once the hosted views have laid out
/// and these have run, a focus move that has not happened is not going to. Time plays no part, so
/// a slow runner cannot cut it short.
@MainActor
func drainMainQueue(laidOut window: UIWindow? = nil, turns: Int = 3) async {
    for _ in 0..<turns {
        window?.layoutIfNeeded()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { done.resume() }
        }
    }
    window?.layoutIfNeeded()
}
