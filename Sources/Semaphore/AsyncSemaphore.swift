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
/// You increment a semaphore count by calling the ``signal()`` method, and
/// decrement a semaphore count by calling ``wait()`` or one of its variants.
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
/// ### Waiting for the Semaphore
///
/// - ``wait()``
/// - ``waitUnlessCancelled()``
public final class AsyncSemaphore: @unchecked Sendable {
    /// "Waiting for a signal" is easily said, but several possible states exist.
    private class Suspension {
        enum State {
            /// Initial state. Next is suspended, or cancelled.
            case pending
            
            /// Waiting for a signal, with support for cancellation.
            case suspendedUnlessCancelled(UnsafeContinuation<Void, Error>)
            
            /// Waiting for a signal, with no support for cancellation.
            case suspended(UnsafeContinuation<Void, Never>)
            
            /// Cancelled before we have started waiting.
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
    
    // MARK: - Internal State
    
    /// The semaphore value.
    private var value: Int
    
    /// As many elements as there are suspended tasks waiting for a signal.
    /// We store `Suspension` instances instead of `UnsafeContinuation`, because
    /// we support cancellation by removing `Suspension` instances from
    /// this array.
    private var suspensions: [Suspension] = []
    
    /// The lock that protects `value` and `suspensions`.
    ///
    /// It is recursive in order to handle cancellation (see the implementation
    /// of ``waitUnlessCancelled()``).
    private let _lock = NSRecursiveLock()
    
    // MARK: - Creating a Semaphore
    
    /// Creates a semaphore.
    ///
    /// - parameter value: The starting value for the semaphore. Do not pass a
    ///   value less than zero.
    public init(value: Int) {
        precondition(value >= 0, "AsyncSemaphore requires a value equal or greater than zero")
        self.value = value
    }
    
    deinit {
        precondition(suspensions.isEmpty, "AsyncSemaphore is deallocated while some task(s) are suspended waiting for a signal.")
    }
    
    // MARK: - Locking
    //
    // Swift concurrency is... unfinished. We really need to protect our inner
    // state (`value` and `suspension`) across the calls to
    // `withUnsafeContinuation`. Unfortunately, this method introduces a
    // suspension point. So we need a lock. But the Swift compiler is never out
    // of funny jokes:
    //
    // > Instance method 'lock' is unavailable from asynchronous contexts;
    // > Use async-safe scoped locking instead; this is an error in Swift 6
    //
    // This is very immature, because we don't quite have any other solution.
    // Maybe the authors of Swift concurrency will find it interesting
    // eventually to provide 1. building blocks that 2. solve known problems
    // and 3. back deploy. So far they're busy polishing something else.
    //
    // So let's just hide the lock and mute this stupid warning:
    func lock() { _lock.lock() }
    func unlock() { _lock.unlock() }
    
    // MARK: - Waiting for the Semaphore
    
    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than
    /// zero, this function suspends the current task until a signal occurs,
    /// without blocking the underlying thread. Otherwise, no suspension happens.
    public func wait() async {
        lock()
        
        value -= 1
        if value >= 0 {
            unlock()
            return
        }
        
        await withUnsafeContinuation { continuation in
            // Register the continuation that `signal` will resume.
            //
            // The first suspended task will be the first task resumed by `signal`.
            // This is not intended to be a strong fifo guarantee, but just
            // an attempt at some fairness.
            suspensions.insert(Suspension(continuation: continuation), at: 0)
            unlock()
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
    public func waitUnlessCancelled() async throws {
        lock()
        
        value -= 1
        if value >= 0 {
            unlock()
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
                    unlock()
                    continuation.resume(throwing: CancellationError())
                } else {
                    // Current task was not cancelled: register the continuation
                    // that `signal` will resume.
                    //
                    // The first suspended task will be the first task resumed by `signal`.
                    // This is not intended to be a strong fifo guarantee, but just
                    // an attempt at some fairness.
                    suspension.state = .suspendedUnlessCancelled(continuation)
                    suspensions.insert(suspension, at: 0)
                    unlock()
                }
            }
        } onCancel: {
            // withTaskCancellationHandler may immediately call this block (if
            // the current task is cancelled), or call it later (if the task is
            // cancelled later). In the first case, we're still holding the lock,
            // waiting for the continuation. In the second case, we do not hold
            // the lock. Being able to handle both situations is the reason why
            // we use a recursive lock.
            lock()
            defer { unlock() }
            
            // We're no longer waiting for a signal
            value += 1
            if let index = suspensions.firstIndex(where: { $0 === suspension }) {
                suspensions.remove(at: index)
            }
            
            if case let .suspendedUnlessCancelled(continuation) = suspension.state {
                // Task is cancelled while suspended: resume with a CancellationError.
                continuation.resume(throwing: CancellationError())
            } else {
                // Current task is cancelled
                // Next step: withUnsafeThrowingContinuation right above
                suspension.state = .cancelled
            }
        }
    }
    
    // MARK: - Signaling the Semaphore
    
    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore. If the previous value was less than
    /// zero, this function resumes a task currently suspended in ``wait()``.
    ///
    /// - returns This function returns true if a suspended task is resumed.
    ///   Otherwise, false is returned.
    @discardableResult
    public func signal() -> Bool {
        lock()
        defer { unlock() }
        
        value += 1
        
        switch suspensions.popLast()?.state {
        case let .suspendedUnlessCancelled(continuation):
            continuation.resume()
            return true
        case let .suspended(continuation):
            continuation.resume()
            return true
        default:
            return false
        }
    }
}
