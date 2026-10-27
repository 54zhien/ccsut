import Foundation

actor FixtureCampusReader: CampusReading {
    var failLeave = false
    var failTravel: CampusTravelKind?
    var delay = false
    var pages: [Int] = []
    func configure(fail: Bool = false, delay: Bool = false, travel: CampusTravelKind? = nil) {
        failLeave = fail; self.delay = delay; failTravel = travel
    }
    func leaveRecords(page: Int, size: Int) async throws -> CampusLeavePage {
        pages.append(page)
        if delay { try await Task.sleep(for: .milliseconds(100)) }
        if failLeave { throw CampusError.serviceUnavailable }
        return try CampusDecoder.leavePage(Data("""
        {"data":{"list":[{"id":"fixture-\(page)","status":0}],"total":40,"pageNum":\(page),"pageSize":20,"hasNextPage":\(page < 2)}}
        """.utf8))
    }
    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord] {
        if delay { try await Task.sleep(for: .milliseconds(100)) }
        if failTravel == kind { throw CampusError.serviceUnavailable }
        return try CampusDecoder.travelRecords(Data("{\"code\":\"2000\",\"data\":[{\"openid\":\"\(kind.rawValue)\"}]}".utf8))
    }
}

final class FixtureEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1
    func current() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func change() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

@main
struct CampusRecordsModelTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ title: String) {
            print("\(condition ? "PASS" : "FAIL") \(title)")
            if !condition { failures += 1 }
        }
        let reader = FixtureCampusReader()
        let epoch = FixtureEpoch()
        let model = CampusRecordsModel(api: reader, currentGeneration: { epoch.current() })
        await model.loadLeave(reset: true)
        check(model.leave.page == 1 && model.leave.items.count == 1, "first load publishes complete page")
        await reader.configure(fail: true)
        await model.loadLeave(reset: false)
        check(model.leave.page == 1 && model.leave.items.count == 1 && model.leaveError != nil, "failed pagination retains data and page")
        await reader.configure()
        await model.loadLeave(reset: false)
        check(model.leave.page == 2 && model.leave.items.count == 2 && model.leaveError == nil, "pagination retry uses same page")
        await reader.configure(fail: true)
        await model.loadLeave(reset: true)
        check(model.leave.page == 2 && model.leave.items.count == 2 && model.leaveFailureWasRefresh, "failed refresh retains all pages")
        await reader.configure()
        await model.loadLeave(reset: true)
        check(model.leave.page == 1 && model.leave.items.count == 1, "successful refresh replaces prior pages")
        await reader.configure(delay: true)
        let pending = Task { await model.loadLeave(reset: false) }
        try await Task.sleep(for: .milliseconds(10))
        var joinedLeaveStarted = false
        var joinedLeaveFinished = false
        let joinedLeave = Task {
            joinedLeaveStarted = true
            await model.loadLeave(reset: true)
            joinedLeaveFinished = true
        }
        while !joinedLeaveStarted { await Task.yield() }
        check(!joinedLeaveFinished, "refresh waits for an in-flight leave read")
        await pending.value
        await joinedLeave.value
        let pages = await reader.pages
        check(Array(pages.suffix(2)) == [2, 1] && pages.count == 7,
              "refresh requested during pagination runs once after the current page completes")
        check(model.leave.page == 1 && model.leave.items.map(\.id) == ["fixture-1"],
              "the deferred refresh replaces the just-completed pagination state")
        await reader.configure(delay: true)
        let cancelPendingLeave = Task { await model.loadLeave(reset: false) }
        while !model.isLoadingLeave { await Task.yield() }
        model.cancel()
        await cancelPendingLeave.value
        check(model.leave.page == 1 && !model.isLoadingLeave && model.leaveError == nil, "leaving page cancels pending read without error")
        await reader.configure()
        await model.loadTravel(kind: .departure)
        await reader.configure(travel: .returning)
        await model.loadTravel(kind: .returning)
        check(model.travel[.departure]?.count == 1 && model.travelErrors[.returning] != nil, "travel categories retain independent success and failure")
        await reader.configure(delay: true)
        let pendingTravel = Task { await model.loadTravel(kind: .departure) }
        while !model.loadingTravel.contains(.departure) { await Task.yield() }
        var joinedTravelStarted = false
        var joinedTravelFinished = false
        let joinedTravel = Task {
            joinedTravelStarted = true
            await model.loadTravel(kind: .departure)
            joinedTravelFinished = true
        }
        while !joinedTravelStarted { await Task.yield() }
        check(!joinedTravelFinished, "refresh waits for an in-flight travel read")
        model.cancel()
        await pendingTravel.value
        await joinedTravel.value
        check(joinedTravelFinished && !model.loadingTravel.contains(.departure), "cancellation releases joined travel refresh")
        await reader.configure(delay: true)
        let oldAccount = Task { await model.loadLeave(reset: false) }
        try await Task.sleep(for: .milliseconds(10))
        epoch.change()
        await oldAccount.value
        check(model.leave.items.isEmpty && model.travel.isEmpty, "account change clears old record state")
        if failures > 0 { exit(1) }
    }
}
