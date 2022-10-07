import Dispatch
import XCTest
@testable import Semaphore

final class AsyncSemaphoreTests: XCTestCase {
    
    func testSignalWithoutSuspendedTasks() async {
        // Check DispatchSemaphore behavior
        do {
            do {
                let sem = DispatchSemaphore(value: 0)
                XCTAssertFalse(sem.signal() != 0)
            }
            do {
                let sem = DispatchSemaphore(value: 1)
                XCTAssertFalse(sem.signal() != 0)
            }
            do {
                let sem = DispatchSemaphore(value: 2)
                XCTAssertFalse(sem.signal() != 0)
            }
        }
        
        // Test that AsyncSemaphore behaves identically
        do {
            do {
                let sem = AsyncSemaphore(value: 0)
                let woken = sem.signal()
                XCTAssertFalse(woken)
            }
            do {
                let sem = AsyncSemaphore(value: 1)
                let woken = sem.signal()
                XCTAssertFalse(woken)
            }
            do {
                let sem = AsyncSemaphore(value: 2)
                let woken = sem.signal()
                XCTAssertFalse(woken)
            }
        }
    }
    
    func test_signal_returns_whether_it_resumes_a_suspended_task_or_not() async throws {
        let delay: UInt64 = 500_000_000
        
        // Check DispatchSemaphore behavior
        do {
            // Given a thread waiting for the semaphore
            let sem = DispatchSemaphore(value: 0)
            Thread { sem.wait() }.start()
            try await Task.sleep(nanoseconds: delay)
            
            // First signal wakes the waiting thread
            XCTAssertTrue(sem.signal() != 0)
            // Second signal does not wake any thread
            XCTAssertFalse(sem.signal() != 0)
        }
        
        // Test that AsyncSemaphore behaves identically
        do {
            // Given a task suspended on the semaphore
            let sem = AsyncSemaphore(value: 0)
            Task { await sem.wait() }
            try await Task.sleep(nanoseconds: delay)
            
            // First signal resumes the suspended task
            XCTAssertTrue(sem.signal())
            // Second signal does not resume any task
            XCTAssertFalse(sem.signal())
        }
    }
    
    func test_wait_suspends_on_zero_semaphore_until_signal() async {
        // Check DispatchSemaphore behavior
        do {
            // Given a zero semaphore
            let sem = DispatchSemaphore(value: 0)
            
            // When a thread waits for this semaphore,
            let ex1 = expectation(description: "wait")
            ex1.isInverted = true
            let ex2 = expectation(description: "woken")
            Thread {
                sem.wait()
                ex1.fulfill()
                ex2.fulfill()
            }.start()
            
            // Then the thread is initially blocked.
            wait(for: [ex1], timeout: 0.5)
            
            // When a signal occurs, then the waiting thread is woken.
            sem.signal()
            wait(for: [ex2], timeout: 1)
        }
        
        // Test that AsyncSemaphore behaves identically
        do {
            // Given a zero semaphore
            let sem = AsyncSemaphore(value: 0)
            
            // When a task waits for this semaphore,
            let ex1 = expectation(description: "wait")
            ex1.isInverted = true
            let ex2 = expectation(description: "woken")
            Task {
                await sem.wait()
                ex1.fulfill()
                ex2.fulfill()
            }
            
            // Then the task is initially suspended.
            wait(for: [ex1], timeout: 0.5)
            
            // When a signal occurs, then the suspended task is resumed.
            sem.signal()
            wait(for: [ex2], timeout: 0.5)
        }
    }
    
    func test_cancellation_while_suspended_throws_CancellationError() async throws {
        let sem = AsyncSemaphore(value: 0)
        let ex = expectation(description: "cancellation")
        let task = Task {
            do {
                try await sem.waitUnlessCancelled()
                XCTFail("Expected CancellationError")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error")
            }
            ex.fulfill()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        wait(for: [ex], timeout: 1)
    }
    
    func test_cancellation_before_suspension_throws_CancellationError() async throws {
        let sem = AsyncSemaphore(value: 0)
        let ex = expectation(description: "cancellation")
        let task = Task {
            // Uncancellable delay
            await withUnsafeContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    continuation.resume()
                }
            }
            do {
                try await sem.waitUnlessCancelled()
                XCTFail("Expected CancellationError")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error")
            }
            ex.fulfill()
        }
        task.cancel()
        wait(for: [ex], timeout: 5)
    }
    
    func test_that_cancellation_while_suspended_increments_the_semaphore() async throws {
        // Given a task cancelled while suspended on a semaphore,
        let sem = AsyncSemaphore(value: 0)
        let task = Task {
            try await sem.waitUnlessCancelled()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        
        // When a task waits for this semaphore,
        let ex1 = expectation(description: "wait")
        ex1.isInverted = true
        let ex2 = expectation(description: "woken")
        Task {
            await sem.wait()
            ex1.fulfill()
            ex2.fulfill()
        }
        
        // Then the task is initially suspended.
        wait(for: [ex1], timeout: 0.5)
        
        // When a signal occurs, then the suspended task is resumed.
        sem.signal()
        wait(for: [ex2], timeout: 0.5)
    }
    
    func test_that_cancellation_before_suspension_increments_the_semaphore() async throws {
        // Given a task cancelled before it waits on a semaphore,
        let sem = AsyncSemaphore(value: 0)
        let task = Task {
            // Uncancellable delay
            await withUnsafeContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    continuation.resume()
                }
            }
            try await sem.waitUnlessCancelled()
        }
        task.cancel()
        
        // When a task waits for this semaphore,
        let ex1 = expectation(description: "wait")
        ex1.isInverted = true
        let ex2 = expectation(description: "woken")
        Task {
            await sem.wait()
            ex1.fulfill()
            ex2.fulfill()
        }
        
        // Then the task is initially suspended.
        wait(for: [ex1], timeout: 0.5)
        
        // When a signal occurs, then the suspended task is resumed.
        sem.signal()
        wait(for: [ex2], timeout: 0.5)
    }
    
    // Test that semaphore can limit the number of concurrent executions of
    // an actor method.
    func test_semaphore_as_a_resource_limiter_on_actor_method() async {
        /// An actor that limits the number of concurrent executions of
        /// its `run()` method, and counts the effective number of
        /// concurrent executions for testing purpose.
        actor Runner {
            private let semaphore: AsyncSemaphore
            private var count = 0
            private(set) var effectiveMaxConcurrentRuns = 0
            
            init(maxConcurrentRuns: Int) {
                semaphore = AsyncSemaphore(value: maxConcurrentRuns)
            }
            
            func run() async {
                await semaphore.wait()
                defer { semaphore.signal()}
                
                count += 1
                effectiveMaxConcurrentRuns = max(effectiveMaxConcurrentRuns, count)
                try! await Task.sleep(nanoseconds: 100_000_000)
                count -= 1
            }
        }
        
        for maxConcurrentRuns in 1...10 {
            let runner = Runner(maxConcurrentRuns: maxConcurrentRuns)
            
            // Spawn many concurrent tasks
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        await runner.run()
                    }
                }
            }
            
            let effectiveMaxConcurrentRuns = await runner.effectiveMaxConcurrentRuns
            XCTAssertEqual(effectiveMaxConcurrentRuns, maxConcurrentRuns)
        }
    }
    
    // Test that semaphore can limit the number of concurrent executions of
    // an async method.
    func test_semaphore_as_a_resource_limiter_on_async_method() async {
        /// A class that limits the number of concurrent executions of
        /// its `run()` method, and counts the effective number of
        /// concurrent executions for testing purpose.
        @MainActor
        class Runner {
            private let semaphore: AsyncSemaphore
            private var count = 0
            private(set) var effectiveMaxConcurrentRuns = 0
            
            init(maxConcurrentRuns: Int) {
                semaphore = AsyncSemaphore(value: maxConcurrentRuns)
            }
            
            func run() async {
                await semaphore.wait()
                defer { semaphore.signal()}
                
                count += 1
                effectiveMaxConcurrentRuns = max(effectiveMaxConcurrentRuns, count)
                try! await Task.sleep(nanoseconds: 100_000_000)
                count -= 1
            }
        }
        
        for maxConcurrentRuns in 1...10 {
            let runner = await Runner(maxConcurrentRuns: maxConcurrentRuns)
            
            // Spawn many concurrent tasks
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        await runner.run()
                    }
                }
            }
            
            let effectiveMaxConcurrentRuns = await runner.effectiveMaxConcurrentRuns
            XCTAssertEqual(effectiveMaxConcurrentRuns, maxConcurrentRuns)
        }
    }
    
    // Test that semaphore can limit the number of concurrent executions of
    // an async method, even when interactions with Swift concurrency runtime
    // are (as much as possible) initiated from a single thread.
    func test_semaphore_as_a_resource_limiter_on_single_thread() async {
        /// A class that limits the number of concurrent executions of
        /// its `run()` method, and counts the effective number of
        /// concurrent executions for testing purpose.
        @MainActor
        class Runner {
            private let semaphore: AsyncSemaphore
            private var count = 0
            private(set) var effectiveMaxConcurrentRuns = 0
            
            init(maxConcurrentRuns: Int) {
                semaphore = AsyncSemaphore(value: maxConcurrentRuns)
            }
            
            func run() async {
                await semaphore.wait()
                defer { semaphore.signal()}
                
                count += 1
                effectiveMaxConcurrentRuns = max(effectiveMaxConcurrentRuns, count)
                try! await Task.sleep(nanoseconds: 100_000_000)
                count -= 1
            }
        }
        
        await Task { @MainActor in
            let runner = Runner(maxConcurrentRuns: 3)
            async let x0: Void = runner.run()
            async let x1: Void = runner.run()
            async let x2: Void = runner.run()
            async let x3: Void = runner.run()
            async let x4: Void = runner.run()
            async let x5: Void = runner.run()
            async let x6: Void = runner.run()
            async let x7: Void = runner.run()
            async let x8: Void = runner.run()
            async let x9: Void = runner.run()
            _ = await (x0, x1, x2, x3, x4, x5, x6, x7, x8, x9)
            let effectiveMaxConcurrentRuns = runner.effectiveMaxConcurrentRuns
            XCTAssertEqual(effectiveMaxConcurrentRuns, 3)
        }.value
    }
    
    // Test that semaphore can limit the number of concurrent executions of
    // an actor method, even when cancellation support is enabled.
    func test_semaphore_as_a_resource_limiter_on_actor_method_with_cancellation_support() async {
        /// An actor that limits the number of concurrent executions of
        /// its `run()` method, and counts the effective number of
        /// concurrent executions for testing purpose.
        actor Runner {
            private let semaphore: AsyncSemaphore
            private var count = 0
            private(set) var effectiveMaxConcurrentRuns = 0
            
            init(maxConcurrentRuns: Int) {
                semaphore = AsyncSemaphore(value: maxConcurrentRuns)
            }
            
            func run() async throws {
                try await semaphore.waitUnlessCancelled()
                defer { semaphore.signal()}
                
                count += 1
                effectiveMaxConcurrentRuns = max(effectiveMaxConcurrentRuns, count)
                try! await Task.sleep(nanoseconds: 100_000_000)
                count -= 1
            }
        }
        
        for maxConcurrentRuns in 1...10 {
            let runner = Runner(maxConcurrentRuns: maxConcurrentRuns)
            
            // Spawn many concurrent tasks
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask {
                        try await runner.run()
                    }
                }
            }
            
            let effectiveMaxConcurrentRuns = await runner.effectiveMaxConcurrentRuns
            XCTAssertEqual(effectiveMaxConcurrentRuns, maxConcurrentRuns)
        }
    }
}
