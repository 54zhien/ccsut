// Compiled by run-elective-load-tests.py, which inserts the production methods.
import Foundation

// PRODUCTION_PAGE_LOAD_GATE

@MainActor private enum CookieJar { static var generation: UInt64 = 1 }

@MainActor private final class SessionFixture {
    var refreshCount = 0
    func refresh() async { refreshCount += 1 }
}

@MainActor private final class APIClient {
    static let shared = APIClient()
    var initResult: Result<ElectiveInit, Error> = .success(fixtureInit)
    var pageResult: Result<TeachingClassPage, Error> = .success(fixturePage)
    var pageResultsByBatch: [String: Result<TeachingClassPage, Error>] = [:]
    var initCalls = 0
    func reset() {
        initResult = .success(Self.fixtureInit)
        pageResult = .success(Self.fixturePage)
        pageResultsByBatch = [:]
        initCalls = 0
    }
    func electiveInit() async throws -> ElectiveInit {
        initCalls += 1
        return try initResult.get()
    }
    func teachingClasses(batch: (String, String)?) async throws -> TeachingClassPage {
        if let batch, let result = pageResultsByBatch[batch.0] { return try result.get() }
        return try pageResult.get()
    }
    static var fixtureInit: ElectiveInit {
        try! JSONDecoder().decode(ElectiveInit.self, from: Data(
            #"{"xkxnxq":"2026-2027-1","pcencs":{"live":"encrypted"}}"#.utf8))
    }
    static var fixturePage: TeachingClassPage {
        try! JSONDecoder().decode(TeachingClassPage.self, from: Data(
            #"{"initData":[{"id":"catalog-course","kcmc":"Catalog course","sfkxk":"1","yxrl":"1/10"}]}"#.utf8))
    }
    static var multiBatchInit: ElectiveInit {
        try! JSONDecoder().decode(ElectiveInit.self, from: Data(
            #"{"xkxnxq":"2026-2027-1","pcencs":{"a":"encrypted-a","b":"encrypted-b"}}"#.utf8))
    }
}

@MainActor private final class ElectiveLoadHarness {
    let enrolledModel: EnrolledCoursesModel
    var electiveState = ElectiveState<TeachingClass>()
    var activeLoadRequests = 0
    var isLoading = false
    let loadGate = PageLoadGate()
    var fetchCount: Int { APIClient.shared.initCalls }
    var initData: ElectiveInit?
    var pending: String?
    var detail: TeachingClass?
    var errorText: String?
    let session = SessionFixture()
    init(_ model: EnrolledCoursesModel) { enrolledModel = model }
    func handleCookieGenerationChange(expected: UInt64) -> Bool { expected != CookieJar.generation }
    func hasVerifiedSnapshot(for generation: UInt64) -> Bool {
        electiveState.isSnapshotVerified && electiveState.snapshotGeneration == generation
    }

    // PRODUCTION_ELECTIVE_LOAD
    // PRODUCTION_ELECTIVE_FETCH
    // PRODUCTION_ELECTIVE_RECORDS
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
    @MainActor static func main() async throws {
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

        let current = "2026-2027-1", past = "2025-2026-2"
        func selectedModel() -> EnrolledCoursesModel {
            EnrolledCoursesModel(generation: { CookieJar.generation }, contextLoader: { _ in
                EnrolledCoursesContext(terms: [current, past], defaultTerm: current)
            }, coursesLoader: { term, _ in
                [try JSONDecoder().decode(EnrolledCourse.self, from: JSONSerialization.data(withJSONObject:
                    ["id":"selected-\(term)","xnxq":term,"kcmc":"Closed-channel elective",
                     "xkfs":"选课","xf":"1","xdfs":"1"]))]
            })
        }
        for failsAtInit in [true, false] {
            APIClient.shared.reset()
            let closedModel = selectedModel()
            let closed = ElectiveLoadHarness(closedModel)
            await closed.load()
            if failsAtInit {
                APIClient.shared.initResult = .failure(APIError.business(-1, "没有可选的教学班"))
            } else {
                APIClient.shared.pageResult = .failure(APIError.business(-1, "没有可选的教学班"))
            }
            await closed.load(force: true)
            check(closed.errorText == nil && closed.electiveState.isChannelClosed
                  && closed.electiveState.snapshot == nil
                  && !closed.electiveState.isSnapshotVerified,
                  "known channel closure at \(failsAtInit ? "initialization" : "catalog") clears stale catalog without a retry error")
            check(closedModel.snapshot?.map(\.id) == ["selected-2026-2027-1"]
                  && closedModel.isVerified && closedModel.currentSummary?.count == 1,
                  "closed catalog still publishes independently verified selected results")
            await closedModel.load(term: past)
            check(closedModel.snapshot?.map(\.id) == ["selected-2025-2026-2"] && closedModel.isVerified,
                  "closed catalog does not prevent historical selected-term reads")
            APIClient.shared.reset()
            await closed.load(force: true)
            check(closed.errorText == nil && !closed.electiveState.isChannelClosed
                  && closed.electiveState.isSnapshotVerified && closed.electiveState.snapshot?.courses.count == 1,
                  "a later successful catalog read replaces closure with a verified actionable snapshot")
        }

        for error: Error in [APIError.business(-2, "没有可选的教学班"),
                             APIError.business(-1, "没有可选的教学班，请稍后重试"),
                             APIError.http(503), URLError(.notConnectedToInternet)] {
            APIClient.shared.reset()
            let failed = ElectiveLoadHarness(selectedModel())
            await failed.load()
            APIClient.shared.pageResult = .failure(error)
            await failed.load(force: true)
            check(failed.errorText != nil && !failed.electiveState.isChannelClosed
                  && failed.electiveState.snapshot?.courses.count == 1
                  && !failed.electiveState.isSnapshotVerified,
                  "unverified closure/business/transport failure preserves retry feedback and disables stale catalog actions: \(error)")
        }

        let closure = APIError.business(-1, "没有可选的教学班")
        for closedBatch in ["a", "b"] {
            let openBatch = closedBatch == "a" ? "b" : "a"
            APIClient.shared.reset()
            APIClient.shared.initResult = .success(APIClient.multiBatchInit)
            APIClient.shared.pageResultsByBatch[closedBatch] = .failure(closure)
            let mixed = ElectiveLoadHarness(selectedModel())
            await mixed.load()
            check(mixed.errorText == nil && !mixed.electiveState.isChannelClosed
                  && mixed.electiveState.isSnapshotVerified
                  && mixed.electiveState.snapshot?.courseIDs == ["catalog-course"]
                  && mixed.electiveState.snapshot?.batchIDsByCourse == ["catalog-course": [openBatch]],
                  "closed batch \(closedBatch) does not discard courses or invent memberships from successful batch \(openBatch)")
            check(mixed.electiveState.actionDecision(for: "catalog-course", kind: .enroll,
                                                    generation: CookieJar.generation) == .allowed(batchID: openBatch),
                  "mixed closure retains the verified course's successful batch for guarded actions")

            APIClient.shared.pageResultsByBatch[openBatch] = .success(try JSONDecoder().decode(
                TeachingClassPage.self, from: Data(#"{"initData":[]}"#.utf8)))
            await mixed.load(force: true)
            check(mixed.errorText == nil && !mixed.electiveState.isChannelClosed
                  && mixed.electiveState.isSnapshotVerified
                  && mixed.electiveState.snapshot?.courses.isEmpty == true,
                  "a successful empty batch \(openBatch) prevents closure of the entire catalog")

            for error: Error in [APIError.notLoggedIn, APIError.business(-1, "没有可选的教学班，请稍后重试"),
                                 APIError.http(503), URLError(.notConnectedToInternet)] {
                APIClient.shared.reset()
                let failed = ElectiveLoadHarness(selectedModel())
                await failed.load()
                APIClient.shared.initResult = .success(APIClient.multiBatchInit)
                APIClient.shared.pageResultsByBatch = [closedBatch: .failure(closure), openBatch: .failure(error)]
                await failed.load(force: true)
                let authenticationFailure = (error as? APIError).map {
                    if case .notLoggedIn = $0 { return true }; return false
                } ?? false
                check(!failed.electiveState.isChannelClosed && !failed.electiveState.isSnapshotVerified
                      && failed.electiveState.snapshot?.courseIDs == ["catalog-course"]
                      && failed.errorText != nil,
                      "closed batch \(closedBatch) cannot suppress a real failure or verify stale catalog data: \(error)")
                check(authenticationFailure
                      ? failed.session.refreshCount == 1
                      : failed.session.refreshCount == 0 && failed.errorText == error.localizedDescription,
                      "mixed closure preserves the actual failure's authentication or retry handling: \(error)")
            }
        }

        APIClient.shared.reset()
        let allClosed = ElectiveLoadHarness(selectedModel())
        await allClosed.load()
        APIClient.shared.initResult = .success(APIClient.multiBatchInit)
        APIClient.shared.pageResultsByBatch = ["a": .failure(closure), "b": .failure(closure)]
        await allClosed.load(force: true)
        check(allClosed.errorText == nil && allClosed.electiveState.isChannelClosed
              && allClosed.electiveState.snapshot == nil && !allClosed.electiveState.isSnapshotVerified
              && allClosed.enrolledModel.isVerified && allClosed.enrolledModel.currentSummary?.count == 1,
              "closure of every batch clears the catalog and retains independent selected results")

        APIClient.shared.reset()
        let expired = ElectiveLoadHarness(selectedModel())
        APIClient.shared.initResult = .failure(APIError.notLoggedIn)
        await expired.load()
        check(expired.errorText != nil && expired.session.refreshCount == 1,
              "authentication failure retains its renewal and retry feedback")
        print("\(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
