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
/// - ``run(_:)``
public class Semaphore {
    /// The semaphore value.
    private var value: Int
    
    /// An array of continuations that release waiting tasks.
    private var continuations: [UnsafeContinuation<Void, Never>] = []
    
    /// This lock would be required even if ``Semaphore`` were made an actor,
    /// because `withUnsafeContinuation` suspends before it runs its closure
    /// argument. Also, by making ``Semaphore`` a plain class, we can expose a
    /// non-async ``signal()`` method.
    private let lock = NSLock()
    
    /// Creates a semaphore.
    ///
    /// - parameter value: The starting value for the semaphore. Do not pass a
    ///   value less than zero.
    public init(value: Int) {
        precondition(value >= 0, "Semaphore requires a value equal or greater than zero")
        self.value = value
    }
    
    /// Waits for, or decrements, a semaphore.
    ///
    /// Decrement the counting semaphore. If the resulting value is less than
    /// zero, this function suspends the current task until a signal occurs.
    /// Otherwise, no suspension happens.
    public func wait() async {
        lock.lock()
        
        value -= 1
        if value < 0 {
            await withUnsafeContinuation { continuation in
                // The first task to wait will be the first task woken by `signal`.
                // This is not intended to be a strong fifo guarantee, but just
                // an attempt at some fairness.
                continuations.insert(continuation, at: 0)
                lock.unlock()
            }
        } else {
            lock.unlock()
        }
    }
    
    /// Signals (increments) a semaphore.
    ///
    /// Increment the counting semaphore. If the previous value was less than
    /// zero, this function resumes a task currently suspended in ``wait()``.
    ///
    /// - returns This function returns true if a task is resumed. Otherwise,
    ///   false is returned.
    @discardableResult
    public func signal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        value += 1
        if let continuation = continuations.popLast() {
            continuation.resume()
            return true
        }
        return false
    }
    
    /// Waits, run an async function, and signals.
    ///
    /// The two sample codes below are equivalent:
    ///
    /// ```swift
    /// let value = await semaphore.run {
    ///     await getValue()
    /// }
    ///
    /// await semaphore.wait()
    /// let value = await getValue()
    /// semaphore.signal()
    /// ```
    public func run<T>(_ execute: @escaping () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await execute()
    }
}
