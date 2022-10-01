import Dispatch
import XCTest
@testable import Semaphore

final class SemaphoreTests: XCTestCase {
    
    func testSignalWithoutWaitingTasks() async {
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
    
    func test_signal_returns_whether_it_wakes_a_waiting_task_or_not() async throws {
        let delay: UInt64 = 500_000_000
        
        // Check DispatchSemaphore behavior
        do {
            // Given a waiting thread
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
            // Given a waiting task
            let sem = Semaphore(value: 0)
            Task { await sem.wait() }
            try await Task.sleep(nanoseconds: delay)
            
            // First signal wakes the waiting task
            XCTAssertTrue(sem.signal())
            // Second signal does not wake any taks
            XCTAssertFalse(sem.signal())
        }
    }
    
    func test_wait_blocks_on_zero_semaphore_until_signal() async {
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
            // Then the task is initially blocked.
            Task {
                await sem.wait()
                ex1.fulfill()
                ex2.fulfill()
            }
            wait(for: [ex1], timeout: 0.5)
            
            // When a signal occurs, then the waiting task is woken.
            sem.signal()
            wait(for: [ex2], timeout: 0.5)
        }
    }
    
    func test_semaphore_as_a_resource_limiter() async {
        ///
        actor Runner {
            var count = 0
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
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<maxCount {
                    group.addTask {
                        await sem.wait()
                        await runner.run()
                        sem.signal()
                    }
                }
            }
            let maxCount = await runner.maxCount
            XCTAssertEqual(maxCount, count)
        }
    }
}
