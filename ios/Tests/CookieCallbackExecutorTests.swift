import Foundation

@main struct CookieCallbackExecutorTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            FileHandle.standardError.write(Data("\(value ? "PASS" : "FAIL") \(name)\n".utf8))
            if !value { failures += 1 }
        }
        let fromMain: Bool = try await CookieCallback.wait { complete in
            complete(Thread.isMainThread)
        }
        check(fromMain, "WebKit callback registration stays on the main thread after await")

        let fromBackground = try await Task.detached {
            try await CookieCallback<Bool>.wait { complete in
                complete(Thread.isMainThread)
            }
        }.value
        check(fromBackground, "background callers register WebKit callbacks on the main thread")

        let first: Int = try await CookieCallback.wait { complete in
            complete(7)
            complete(9)
        }
        check(first == 7, "duplicate callbacks still complete only once")
        do {
            let _: Int = try await CookieCallback.wait(timeout: .milliseconds(10)) { _ in }
            check(false, "missing callback must time out")
        } catch {
            check((error as? URLError)?.code == .timedOut, "missing callback times out")
        }
        var pendingCompletion: (@Sendable (Int) -> Void)?
        let canceled = Task { () -> Int in
            try await CookieCallback.wait { pendingCompletion = $0 }
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while pendingCompletion == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        check(pendingCompletion != nil, "callback is registered before cancellation")
        canceled.cancel()
        do {
            _ = try await canceled.value
            check(false, "canceled wait must throw")
        } catch {
            check(error is CancellationError, "registered wait cancels without waiting for WebKit")
        }
        pendingCompletion?(17)
        check(true, "late callback after cancellation does not resume twice")
        exit(failures == 0 ? 0 : 1)
    }
}
