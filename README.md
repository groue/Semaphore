# Semaphore

`Semaphore` is an object that controls access to a resource across multiple execution contexts through use of a traditional counting semaphore.

Unlike [`DispatchSemaphore`](https://developer.apple.com/documentation/dispatch/dispatchsemaphore), `Semaphore` does not block any thread. Instead, it suspends Swift concurrency tasks.

### Usage

```swift
let semaphore = Semaphore(value: 0)

Task {
    // Suspends the task until a signal occurs.
    try await semaphore.wait()
    await doSomething()
}

// Resumes the suspended task.
semaphore.signal()
```

The `wait()` method throws `CancellationError` if the task is cancelled while waiting for a signal.

Semaphores also provide a way to restrict the access to a limited resource. The sample code below makes sure that `downloadAndSave()` waits until the previous call has completed:

```swift
let semaphore = Semaphore(value: 1)

// There is at most one task that is downloading and saving at any given time
func downloadAndSave() async throws {
    try await semaphore.wait()
    let value = try await downloadValue()
    try await save(value)
    semaphore.signal()
}
```

When you frequently wrap some asynchronous code between `wait()` and `signal()`, you may enjoy the `run` convenience method, which is equivalent:

```swift
func downloadAndSave() async throws {
    await semaphore.run {
        let value = try await downloadValue()
        try await save(value)
    }
}
```
