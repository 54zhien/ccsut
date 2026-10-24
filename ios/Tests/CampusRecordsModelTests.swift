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
        await model.loadLeave(reset: true)
        let pages = await reader.pages
        check(pages.last == 2 && pages.count == 6, "overlapping refresh cannot race pagination")
        model.cancel()
        await pending.value
        check(model.leave.page == 1 && !model.isLoadingLeave && model.leaveError == nil, "leaving page cancels pending read without error")
        await reader.configure()
        await model.loadTravel(kind: .departure)
        await reader.configure(travel: .returning)
        await model.loadTravel(kind: .returning)
        check(model.travel[.departure]?.count == 1 && model.travelErrors[.returning] != nil, "travel categories retain independent success and failure")
        await reader.configure(delay: true)
        let oldAccount = Task { await model.loadLeave(reset: false) }
        try await Task.sleep(for: .milliseconds(10))
        epoch.change()
        await oldAccount.value
        check(model.leave.items.isEmpty && model.travel.isEmpty, "account change clears old record state")
        if failures > 0 { exit(1) }
    }
}
