// To run this playground, open Semaphore.xcworkspace with Xcode.
//
// Examples based on https://medium.com/@roykronenfeld/semaphores-in-swift-e296ea80f860
import Semaphore

do {
    // Sample run:
    //
    // Kid 1 - wait
    // Kid 1 - wait finished
    // Kid 2 - wait
    // Kid 3 - wait
    // Kid 1 - done with iPad
    // Kid 2 - wait finished
    // Kid 2 - done with iPad
    // Kid 3 - wait finished
    // Kid 3 - done with iPad

    let semaphore = Semaphore(value: 1)
    await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            print("Kid 1 - wait")
            await semaphore.wait()
            print("Kid 1 - wait finished")
            try await Task.sleep(nanoseconds: 1_000_000_000) // Kid 1 playing with iPad
            semaphore.signal()
            print("Kid 1 - done with iPad")
        }
        group.addTask {
            print("Kid 2 - wait")
            await semaphore.wait()
            print("Kid 2 - wait finished")
            try await Task.sleep(nanoseconds: 1_000_000_000) // Kid 2 playing with iPad
            semaphore.signal()
            print("Kid 2 - done with iPad")
        }
        group.addTask {
            print("Kid 3 - wait")
            await semaphore.wait()
            print("Kid 3 - wait finished")
            try await Task.sleep(nanoseconds: 1_000_000_000) // Kid 3 playing with iPad
            semaphore.signal()
            print("Kid 3 - done with iPad")
        }
    }
}

do {
    // Sample run:
    //
    // Downloading song 1
    // Downloading song 2
    // Downloading song 3
    // Downloaded song 1
    // Downloaded song 3
    // Downloaded song 2
    // Downloading song 4
    // Downloading song 5
    // Downloading song 6
    // Downloaded song 4
    // Downloaded song 5
    // Downloaded song 6
    // Downloading song 7
    // Downloading song 8
    // Downloading song 9
    // Downloaded song 7
    // Downloaded song 8
    // Downloaded song 9
    // Downloading song 10
    // Downloading song 11
    // Downloading song 12
    // Downloaded song 10
    // Downloaded song 11
    // Downloaded song 12
    // Downloading song 13
    // Downloading song 14
    // Downloading song 15
    // Downloaded song 13
    // Downloaded song 14
    // Downloaded song 15
    
    let semaphore = Semaphore(value: 3)
    await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<15 {
            group.addTask {
                let songNumber = i + 1
                await semaphore.wait()
                print("Downloading song", songNumber)
                try await Task.sleep(nanoseconds: 2_000_000_000) // Download take ~2 sec each
                print("Downloaded song", songNumber)
                semaphore.signal()
            }
        }
    }
}
