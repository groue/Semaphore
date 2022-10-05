# Semaphore

`Semaphore` is an object that controls access to a resource across multiple execution contexts through use of a traditional counting semaphore.

Unlike [`DispatchSemaphore`], `Semaphore` does not block any thread. Instead, it suspends Swift concurrency tasks.

### Usage

You can use a semaphore to suspend a task and resume it later:

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

You can use a semaphore in order to make sure an actor's methods can't run concurrently:

```swift
actor MyActor {
    private let semaphore = Semaphore(value: 1)
    
    func serializedMethod() async {
        // Makes sure no two tasks can execute self.serializedMethod() concurrently. 
        await semaphore.wait()
        defer { semaphore.signal() }
        
        await doSomething()
        await doSomethingElse()
    }
}
```

The `wait()` method has a `waitUnlessCancelled()` variant that throws `CancellationError` if the task is cancelled before a signal occurs.

For a nice introduction to semaphores, see [The Beauty of Semaphores in Swift 🚦](https://medium.com/@roykronenfeld/semaphores-in-swift-e296ea80f860). The article discusses [`DispatchSemaphore`], but it can easily be ported to Swift concurrency: see the [demo playground](Demo/SemaphorePlayground.playground/Contents.swift) of this package. 

[`DispatchSemaphore`]: https://developer.apple.com/documentation/dispatch/dispatchsemaphore
