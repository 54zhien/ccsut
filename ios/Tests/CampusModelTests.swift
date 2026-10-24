import Foundation

@main
struct CampusModelTests {
    static func main() throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        func rejected(_ json: String, expected: CampusError) -> Bool {
            do { _ = try CampusDecoder.travelRecords(Data(json.utf8)); return false }
            catch { return error as? CampusError == expected }
        }
        let leave = """
        {"message":"success","errorMessage":null,"data":{"list":[{
          "id":"fixture-leave","leaveTypeName":"病假","beginTime":"2026-10-01 08:00:00",
          "endTime":"2026-10-02 08:00:00","leaveDay":1.5,"status":0,
          "reason":"联系电话 18000000000","phone":"18000000000","cert":"11000020000101001X"
        }],"total":2,"pageNum":1,"pageSize":1,"hasNextPage":true}}
        """
        let page = try CampusDecoder.leavePage(Data(leave.utf8))
        check(page.items.count == 1 && page.page == 1 && page.hasMore, "leave pagination reads data.list")
        check(page.items[0].days == Decimal(string: "1.5"), "fractional leave days remain decimal")
        check(page.items[0].statusText == "待审核", "only verified pending leave status is named")
        check(!page.items[0].reason!.contains("18000000000"), "reason is masked while decoding")
        let returned = try CampusDecoder.travelRecords(Data("""
        {"message":"success","errorMessage":null,"data":[{"openid":"fixture-return","batchName":"示例假期",
        "status":"待审核","phone":"18000000000","jzPhone":"18000000001","txdz":"示例区县"}]}
        """.utf8))
        check(returned[0].title == "示例假期" && returned[0].statusText == "待审核", "return envelope reads data array")
        let departure = try CampusDecoder.travelRecords(Data("""
        {"code":"2000","msg":"success","data":[{"openid":"fixture-departure","typeName":"示例节假日",
        "isLeave":"1","status":"已登记","reason":"银行卡 6222000000000000000","txdz":null,"startDate":null}]}
        """.utf8))
        check(departure[0].title == "示例节假日" && departure[0].startDate == nil, "departure accepts string code and null dates")
        check(!departure[0].reason!.contains("6222000000000000000"), "travel reason never retains bank number")
        check(rejected("{\"code\":\"5000\",\"data\":[]}", expected: .serviceUnavailable), "business failure cannot become empty records")
        check(rejected("{\"code\":\"401\",\"data\":[]}", expected: .authentication), "JSON authentication failure is recognized")
        check(rejected("{\"message\":\"ok\",\"errorMessage\":\"private fixture error\",\"data\":[]}", expected: .serviceUnavailable), "errorMessage is checked without exposing it")
        check(rejected("{\"message\":\"ok\"}", expected: .invalidResponse), "missing payload fails visibly")
        check(rejected("{\"code\":\"2000\",\"data\":{}}", expected: .invalidResponse), "wrong payload shape fails visibly")
        check(rejected("{\"code\":\"2000\",\"data\":[{}]}", expected: .invalidResponse), "missing record identity is not silently invented")
        let empty = try CampusDecoder.travelRecords(Data("{\"code\":\"2000\",\"data\":[]}".utf8))
        check(empty.isEmpty, "valid empty response remains empty")
        for number in ["18000000000", "11000020000101001X", "6222000000000000000", "6222 0000 0000 0000 000"] {
            check(!CampusPrivacy.redact("联系：\(number)").contains(number), "sensitive numeric text is masked")
        }
        check(CampusPrivacy.redact("2026-10-24 病假") == "2026-10-24 病假", "ordinary date text remains readable")
        check(!CampusError.invalidResponse.localizedDescription.contains("private fixture error"), "errors have fixed safe copy")

        var state = CampusPageState()
        try state.apply(page, reset: true)
        check(state.page == 1 && state.items.count == 1, "first page commits atomically")
        let before = state.items
        do { try state.apply(page, reset: false); check(false, "out-of-order page rejected") }
        catch { check(state.page == 1 && state.items == before, "rejected page leaves prior state unchanged") }
        let next = try CampusDecoder.leavePage(Data("""
        {"data":{"list":[{"id":"second","status":99}],"total":2,"pageNum":2,"pageSize":1,"hasNextPage":false}}
        """.utf8))
        try state.apply(next, reset: false)
        check(state.page == 2 && state.items.count == 2 && !state.hasMore, "next page appends without skipping")
        check(state.items[1].statusText == "状态 99", "unknown status does not get guessed")
        try state.apply(page, reset: true)
        check(state.items.count == 1 && state.page == 1 && state.hasMore, "successful refresh replaces pages")
        if failures > 0 { exit(1) }
    }
}
