import Dispatch
import XCTest
@testable import Semaphore

final class SemaphoreTests: XCTestCase {
    
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
        
        // Test that Semaphore behaves identically
        do {
            do {
                let sem = Semaphore(value: 0)
                let woken = sem.signal()
                XCTAssertFalse(woken)
            }
            do {
                let sem = Semaphore(value: 1)
                let woken = sem.signal()
                XCTAssertFalse(woken)
            }
            do {
                let sem = Semaphore(value: 2)
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
        
        // Test that Semaphore behaves identically
        do {
            // Given a task suspended on the semaphore
            let sem = Semaphore(value: 0)
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
            let ex1 = expectation(description: "wait")
            ex1.isInverted = true
            let ex2 = expectation(description: "woken")
            
            // When a thread waits for this semaphore,
            // Then the thread is initially blocked.
            Thread {
                sem.wait()
                ex1.fulfill()
                ex2.fulfill()
            }.start()
            wait(for: [ex1], timeout: 0.5)
            
            // When a signal occurs, then the waiting thread is woken.
            sem.signal()
            wait(for: [ex2], timeout: 1)
        }
        
        // Test that Semaphore behaves identically
        do {
            // Given a zero semaphore
            let sem = Semaphore(value: 0)
            let ex1 = expectation(description: "wait")
            ex1.isInverted = true
            let ex2 = expectation(description: "woken")
            
            // When a task waits for this semaphore,
            // Then the task is initially suspended.
            Task {
                await sem.wait()
                ex1.fulfill()
                ex2.fulfill()
            }
            wait(for: [ex1], timeout: 0.5)
            
            // When a signal occurs, then the suspended task is resumed.
            sem.signal()
            wait(for: [ex2], timeout: 0.5)
        }
    }
    
    func test_semaphore_as_a_resource_limiter() async {
        /// An actor that counts the maximum number of concurrent executions of
        /// the `run()` method.
        actor Runner {
            private var count = 0
            var maxCount = 0
            
            func run() async {
                count += 1
                maxCount = max(maxCount, count)
                try! await Task.sleep(nanoseconds: 100_000_000)
                count -= 1
            }
        }
        let maxCount = 10
        for count in 1...maxCount {
            let runner = Runner()
            let sem = Semaphore(value: count)
            
            // Spawn many concurrent tasks
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<(maxCount * 2) {
                    group.addTask {
                        await sem.wait()
                        await runner.run()
                        sem.signal()
                    }
                }
            }
            
            // The maximum number of concurrent executions of the `run()`
            // method must be identical to the initial value of the semaphore.
            let maxCount = await runner.maxCount
            XCTAssertEqual(maxCount, count)
        }
    }
}
