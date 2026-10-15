import Foundation

/// Carries the cancellation of the host's task to the 3DS screen, which runs on the main thread
/// and has to close when the task waiting for it is cancelled.
///
/// ``cancel()`` may run on any thread, before the flow has started or after it has finished. It
/// marks the cancellation at once, so an outcome the screen reports in the same main-thread pass
/// already sees it and ends as `CancellationError` rather than as a closed screen. Only the
/// handler, which touches the screen, waits for the main thread.
final class HostCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    /// Main thread only.
    private var handler: (() -> Void)?

    /// Whether the host's task has been cancelled. Safe on any thread.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Called from the task's cancellation handler.
    func cancel() {
        lock.lock()
        let isFirst = !cancelled
        cancelled = true
        lock.unlock()
        guard isFirst else { return }
        DispatchQueue.main.async {
            let handler = self.handler
            self.handler = nil
            handler?()
        }
    }

    /// Runs `handler` once the task is cancelled, right away when it already is. Main thread only.
    func onCancel(_ handler: @escaping () -> Void) {
        if isCancelled {
            handler()
        } else {
            self.handler = handler
        }
    }
}
