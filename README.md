# Semaphore

**A Synchronization Primitive for Swift Concurrency**

**Requirements**: iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ • Swift 5.7+ / Xcode 14+

📖 **[Documentation](https://swiftpackageindex.com/groue/Semaphore/documentation)**

---

This package provides `AsyncSemaphore`, a [traditional counting semaphore](https://en.wikipedia.org/wiki/Semaphore_(programming)).

Unlike [`DispatchSemaphore`], it does not block any thread. Instead, Swift concurrency tasks are suspended "awaiting" for the semaphore.

### Usage

You can use a semaphore to suspend a task and resume it later:

```swift
let semaphore = AsyncSemaphore(value: 0)

Task {
  // Suspends the task until a signal occurs.
  await semaphore.wait()
  await doSomething()
}

// Resumes the suspended task.
semaphore.signal()
```

An actor can use a semaphore so that its methods can't run concurrently, avoiding the "actor reentrancy problem":

```swift
actor MyActor {
  private let semaphore = AsyncSemaphore(value: 1)
  
  func serializedMethod() async {
    // Makes sure no two tasks can execute
    // serializedMethod() concurrently. 
    await semaphore.wait()
    defer { semaphore.signal() }
    
    await doSomething()
    await doSomethingElse()
  }
}
```

A semaphore can generally limit the number of concurrent accesses to a resource:

```swift
class Downloader {
  private let semaphore: AsyncSemaphore

  /// Creates a Downloader that can run at most
  /// `maxDownloadCount` concurrent downloads. 
  init(maxDownloadCount: Int) {
    semaphore = AsyncSemaphore(value: maxDownloadCount) 
  }

  func download(...) async throws -> Data {
    try await semaphore.waitUnlessCancelled()
    defer { semaphore.signal() }
    return try await ...
  }
}
```

You can see in the latest example that the `wait()` method has a `waitUnlessCancelled` variant that throws `CancellationError` if the task is cancelled before a signal occurs.

For a nice introduction to semaphores, see [The Beauty of Semaphores in Swift 🚦](https://medium.com/@roykronenfeld/semaphores-in-swift-e296ea80f860). The article discusses [`DispatchSemaphore`], but it can easily be ported to Swift concurrency: get inspiration from the above examples. 

[`DispatchSemaphore`]: https://developer.apple.com/documentation/dispatch/dispatchsemaphore
