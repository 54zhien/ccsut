// Compiled by run-elective-load-tests.py, which inserts the production methods.
import Foundation

// PRODUCTION_PAGE_LOAD_GATE

@MainActor private enum CookieJar { static var generation: UInt64 = 1 }

@MainActor private final class ElectiveLoadHarness {
    let enrolledModel: EnrolledCoursesModel
    var electiveState = ElectiveState<TeachingClass>()
    var activeLoadRequests = 0
    var isLoading = false
    let loadGate = PageLoadGate()
    var fetchCount = 0
    init(_ model: EnrolledCoursesModel) { enrolledModel = model }
    func handleCookieGenerationChange(expected: UInt64) -> Bool { expected != CookieJar.generation }
    func hasVerifiedSnapshot(for generation: UInt64) -> Bool { generation == CookieJar.generation }
    func fetch(force: Bool, refreshAuthentication: Bool, expectedGeneration: UInt64?) async { fetchCount += 1 }

    // PRODUCTION_ELECTIVE_LOAD
}

private actor ReadLatch {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    func block() async {
        entered = true
        observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { release = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func open() { release?.resume(); release = nil }
}

@main private struct ElectiveLoadTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        let latch = ReadLatch()
        var reads = 0
        let model = EnrolledCoursesModel(generation: { CookieJar.generation }, contextLoader: { _ in
            EnrolledCoursesContext(terms: ["2026-2027-1"], defaultTerm: "2026-2027-1")
        }, coursesLoader: { _, _ in
            reads += 1
            if reads == 1 { await latch.block() }
            return []
        })
        let harness = ElectiveLoadHarness(model)
        let first = Task { await harness.load() }
        await latch.waitForEntry()
        let joined = Task { await harness.load(force: true) }
        while harness.activeLoadRequests < 2 { await Task.yield() }
        check(reads == 1 && harness.fetchCount == 1 && harness.isLoading,
              "refresh joins the in-flight selected-results owner without a second read")
        await latch.open()
        await first.value; await joined.value
        check(model.isVerified && model.snapshot != nil && model.currentSummary?.count == 0,
              "joined refresh retains the completed verified selected-results snapshot and summary")
        check(!harness.isLoading && harness.activeLoadRequests == 0 && !model.isLoading,
              "both joined callers finish loading after their owner publishes")
        await harness.load(force: true)
        check(reads == 2 && harness.fetchCount == 2 && model.isVerified && model.currentSummary?.count == 0,
              "a later refresh owns a new read and publishes verified results")
        print("\(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
