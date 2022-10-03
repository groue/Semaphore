# Semaphore

`Semaphore` is an object that controls access to a resource across multiple execution contexts through use of a traditional counting semaphore.

Unlike [`DispatchSemaphore`], `Semaphore` does not block any thread. Instead, it suspends Swift concurrency tasks.

### Usage

```swift
let semaphore = Semaphore(value: 0)

Task {
    // Suspends the task until a signal occurs.
    await semaphore.wait()
    await doSomething()
}

// Resumes the suspended task.
semaphore.signal()
```

The `wait()` method has a `waitUnlessCancelled()` variant that throws `CancellationError` if the task is cancelled before a signal occurs.

For a nice introduction to semaphores, see [The Beauty of Semaphores in Swift 🚦](https://medium.com/@roykronenfeld/semaphores-in-swift-e296ea80f860). The article discusses [`DispatchSemaphore`], but it can easily be ported to Swift concurrency: see the [demo playground](Demo/SemaphorePlayground.playground/Contents.swift) of this package. 

[`DispatchSemaphore`]: https://developer.apple.com/documentation/dispatch/dispatchsemaphore
