// Copyright (C) 2022 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation

/// An object that controls access to a resource across multiple execution
/// contexts through use of a traditional counting semaphore.
///
/// Unlike `DispatchSemaphore`,  ``Semaphore`` does not block any thread.
/// Instead, it suspends Swift concurrency tasks.
///
/// ## Topics
///
/// ### Creating a Semaphore
///
/// - ``init(value:)``
///
/// ### Signaling the Semaphore
///
/// - ``signal()``
///
/// ### Blocking on the Semaphore
///
/// - ``wait()``
/// - ``waitUntilTaskCancellation()``
public final class Semaphore {
    /// The semaphore value.
    private var value: Int
    
    private class Suspension {
        enum State {
            case pending
            case suspendedUntilTaskCancellation(UnsafeContinuation<Void, Error>)
            case suspended(UnsafeContinuation<Void, Never>)
            case cancelled
        }
        
        var state: State
        
        init() {
            state = .pending
        }
        
        init(continuation: UnsafeContinuation<Void, Never>) {
            state = .suspended(continuation)
        }
    }
    
    private var suspensions: [Suspension] = []
    
    /// This lock would be required even if ``Semaphore`` were made an actor,
    /// because `withUnsafeContinuation` suspends before it runs its closure
    /// argument. Also, by making ``Semaphore`` a plain class, we can expose a
    /// non-async ``signal()`` method. The lock is recursive in order to handle
    /// cancellation (see the implementation of ``wait()``).
    private let lock = NSRecursiveLock()
    
    /// Creates a semaphore.
    ///
    /// - parameter value: The starting value for the semaphore. Do not pass a
    ///   value less than zero.
    public init(value: Int) {
        precondition(value >= 0, "Semaphore requires a value equal or greater than zero")
        self.value = value
    }
    
    deinit {
        precondition(suspensions.isEmpty, "Semaphore is deallocated while some task(s) are suspended waiting for a signal.")
    }
    
    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than
    /// zero, this function suspends the current task until a signal occurs,
    /// without blocking the underlying thread. Otherwise, no suspension happens.
    public func wait() async {
        lock.lock()
        
        value -= 1
        if value >= 0 {
            lock.unlock()
            return
        }
        
        await withUnsafeContinuation { continuation in
            // Register the continuation that `signal` will resume.
            //
            // The first suspended task will be the first task resumed by `signal`.
            // This is not intended to be a strong fifo guarantee, but just
            // an attempt at some fairness.
            suspensions.insert(Suspension(continuation: continuation), at: 0)
            lock.unlock()
        }
    }
    
    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than
    /// zero, this function suspends the current task until a signal occurs,
    /// without blocking the underlying thread. Otherwise, no suspension happens.
    ///
    /// - Throws: If the task is canceled before a signal occurs, this function
    ///   throws `CancellationError`.
    public func waitUntilTaskCancellation() async throws {
        lock.lock()
        
        value -= 1
        if value >= 0 {
            lock.unlock()
            // All code paths check for cancellation
            try Task.checkCancellation()
            return
        }
        
        // Get ready for being suspended waiting for a continuation, or for
        // early cancellation.
        let suspension = Suspension()
        
        try await withTaskCancellationHandler {
            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
                if case .cancelled = suspension.state {
                    // Current task was already cancelled when withTaskCancellationHandler
                    // was invoked.
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else {
                    // Current task was not cancelled: register the continuation
                    // that `signal` will resume.
                    //
                    // The first suspended task will be the first task resumed by `signal`.
                    // This is not intended to be a strong fifo guarantee, but just
                    // an attempt at some fairness.
                    suspension.state = .suspendedUntilTaskCancellation(continuation)
                    suspensions.insert(suspension, at: 0)
                    lock.unlock()
                }
            }
        } onCancel: {
            // withTaskCancellationHandler may immediately call this block (if
            // the current task is cancelled), or call it later (if the task is
            // cancelled later). In the first case, we're still holding the lock,
            // waiting for the continuation. In the second case, we do not hold
            // the lock. This is the reason why we use a recursive lock.
            lock.lock()
            defer { lock.unlock() }
            
            // We're no longer waiting for a signal
            value += 1
            if let index = suspensions.firstIndex(where: { $0 === suspension }) {
                suspensions.remove(at: index)
            }
            
            if case let .suspendedUntilTaskCancellation(continuation) = suspension.state {
                // Task is cancelled while suspended: resume with a CancellationError.
                continuation.resume(throwing: CancellationError())
            } else {
                // Current task is cancelled
                // Next step: withUnsafeThrowingContinuation right above
                suspension.state = .cancelled
            }
        }
    }
    
    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore. If the previous value was less than
    /// zero, this function resumes a task currently suspended in ``wait()``.
    ///
    /// - returns This function returns true if a suspended task is resumed.
    ///   Otherwise, false is returned.
    @discardableResult
    public func signal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        value += 1
        
        switch suspensions.popLast()?.state {
        case let .suspendedUntilTaskCancellation(continuation):
            continuation.resume()
            return true
        case let .suspended(continuation):
            continuation.resume()
            return true
        default:
            break
        }
        
        return false
    }
}
