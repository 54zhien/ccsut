import Foundation

@main
struct AcademicReliabilityTests {
    static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)")
            if !value { failures += 1 }
        }
        func score(_ json: String) throws -> ScoreItem {
            try JSONDecoder().decode(ScoreItem.self, from: Data(json.utf8))
        }
        for counts in ["40/40", "40 / 40", " 40 / 40 ", "40\t/\t40"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": "fixture", "yxrl": counts, "sfkxk": "1"])
            let item = try JSONDecoder().decode(TeachingClass.self, from: data)
            check(item.enrolled == 40 && item.capacity == 40 && item.isFull && !item.canSelect,
                  "full elective remains unselectable with whitespace around its counts")
        }
        let passedScore = try score(#"{"xf":"2","jd":4,"sfjg":"1"}"#)
        let failedScore = try score(#"{"xf":"2","jd":0,"sfjg":"0"}"#)
        let pendingScore = try score(#"{"xf":"2","jd":null,"sfjg":null}"#)
        check(passedScore.passed && !passedScore.failed, "passing result is not counted as failed")
        check(failedScore.failed && !failedScore.passed, "explicit failing result is counted as failed")
        for flag in ["", " ", "unknown", "2"] {
            let item = try score("{\"sfjg\":\"\(flag)\"}")
            check(!item.failed && !item.passed, "unrecognized result stays neutral: '\(flag)'")
        }
        check(!pendingScore.failed && !pendingScore.hasGrade, "missing grade and result remain pending")
        let mixedScores = ScoreTerm(name: "fixture", items: [passedScore, pendingScore])
        check(mixedScores.gpa == 4 && mixedScores.credits == 4, "pending grades do not dilute GPA or remove displayed credits")
        let gradedScores = ScoreTerm(name: "fixture", items: [passedScore, failedScore])
        check(gradedScores.gpa == 2 && gradedScores.failedCount == 1, "zero GPA contributes its credits and explicit failure")
        check(WeekParser.parse("1-4，6-11") == [1,2,3,4,6,7,8,9,10,11], "Chinese separators preserve a missing teaching week")
        check(WeekParser.parse("1-8(单)") == [1,3,5,7], "odd-week suffix keeps only odd weeks")
        check(WeekParser.parse("1-8周（双周）") == [2,4,6,8], "even-week suffix keeps only even weeks")
        check(WeekParser.parse("0-2").isEmpty, "out-of-range teaching weeks are rejected")
        check(WeekParser.parse("1-2-3").isEmpty, "malformed ranges are rejected as a whole")
        let formatter = ISO8601DateFormatter()
        let sunday = formatter.date(from: "2026-10-25T23:59:00+08:00")!
        let monday = formatter.date(from: "2026-10-26T00:01:00+08:00")!
        let snapshot = TeachingWeekSnapshot(term: "2026-2027-1", account: "student-a", week: 7, verifiedAt: sunday)
        check(snapshot.week(on: monday, term: "2026-2027-1", account: "student-a") == 8, "Shanghai Monday advances the teaching week")
        check(snapshot.week(on: sunday.addingTimeInterval(-60), term: "2026-2027-1", account: "student-a") == nil, "future verification timestamps cannot label the current week")
        check(snapshot.week(on: monday, term: "2026-2027-1", account: "student-b") == nil, "a different account cannot reuse the week snapshot")
        check(snapshot.week(on: monday, term: "2026-2027-2", account: "student-a") == nil, "a new term cannot reuse the previous teaching week")
        check(snapshot.week(on: monday.addingTimeInterval(35 * 86400), term: "2026-2027-1", account: "student-a") == nil, "expired week snapshots cannot label this week")
        let mondaySnapshot = TeachingWeekSnapshot(term: "2026-2027-1", account: "student-a", week: 8, verifiedAt: monday)
        check(mondaySnapshot.week(on: monday.addingTimeInterval(30 * 86400), term: "2026-2027-1", account: "student-a") == nil, "cache age is limited by elapsed days as well as week boundaries")
        let unowned = TeachingWeekSnapshot(term: "2026-2027-1", account: "", week: 7, verifiedAt: sunday)
        check(unowned.week(on: monday, term: "2026-2027-1", account: "") == nil, "unverified identity cannot own a week snapshot")
        let page = #"<input value='2026-2027-2' name='xkxnxq'><input value='2026-2027-1' id='xnxq'><input name='xhid' value='student-key'>"#
        let context = try AcademicCalendarParser.timetable(page)
        check(context.term == "2026-2027-1" && context.studentKey == "student-key", "teaching term ignores next-term elective context")
        let namedPage = #"<select id='semesterPicker' name='xnxq'><option value='2026-2027-2'>next</option><option selected value='2026-2027-1'>current</option></select><input id='studentKey' name='xhid' value='key'>"#
        let named = try? AcademicCalendarParser.timetable(namedPage)
        check(named?.term == "2026-2027-1", "semantic field names work when DOM ids differ")
        let terms = try AcademicCalendarParser.examTerms(#"<option value='2027-2028-1'>new</option><option value='2023-2024-2'>old</option><option value='all'>all</option><a onclick="changeXn('2026-2027-2')">term</a>"#)
        check(terms == ["2027-2028-1","2026-2027-2","2023-2024-2"], "exam terms follow official options across academic years")
        // Sanitized semester controls from the user's captured kslist HTML (2026-10-22).
        // This mobile page has no <option> or changeXn controls.
        let capturedExamPage = #"""
        <span id="xq">2026-2027-1</span>
        <div id="xueqi_pop"><div class="censor_top_c">
          <a onclick="loadKspc('2026-2027-1');" class="cur">2026-2027-1</a>
          <a onclick="loadKspc('2025-2026-2');">2025-2026-2</a>
          <a onclick="loadKspc('2025-2026-1');">2025-2026-1</a>
          <a onclick="loadKspc('2024-2025-2');">2024-2025-2</a>
          <a onclick="loadKspc('2024-2025-1');">2024-2025-1</a>
        </div></div>
        <script>function loadKspc(xnxq) { /* requests batches for the chosen term */ }</script>
        """#
        check((try? AcademicCalendarParser.examTerms(capturedExamPage)) == ["2026-2027-1", "2025-2026-2", "2025-2026-1", "2024-2025-2", "2024-2025-1"], "captured mobile exam page exposes all five semesters via loadKspc")
        check((try? AcademicCalendarParser.examTerms(#"<a onclick="loadKspc('2025-2027-9');">invalid</a><a onclick="loadKsxx('batch-id');">batch</a>"#)) == nil, "exam batches and malformed terms cannot become semester requests")
        check((try? AcademicCalendarParser.timetable("<html>login</html>")) == nil, "missing academic context never invents a semester")
        check((try? AcademicCalendarParser.examTerms("2026-2027-1")) == nil, "arbitrary page text is not an official term option")
        let bad = try JSONDecoder().decode([ScheduleItem].self, from: Data(#"[{"kcmc":"course","xingqi":1,"djc":1,"zc":"garbled"}]"#.utf8))
        check((try? ScheduleValidation.slots(bad)) == nil, "malformed weeks cannot publish an all-weeks course")
        for suffix in ["", #", "zc": """#, #", "zc": "   ""#] {
            let missingWeeks = try JSONDecoder().decode([ScheduleItem].self, from: Data((#"[{"kcmc":"course","xingqi":1,"djc":1"# + suffix + "}]").utf8))
            check((try? ScheduleValidation.slots(missingWeeks)) == nil, "missing or blank week data cannot publish an all-weeks course")
        }
        let even = try JSONDecoder().decode([ScheduleItem].self, from: Data(#"[{"kcmc":"course","xingqi":1,"djc":1,"zc":"1-8(双)"}]"#.utf8))
        check(try ScheduleValidation.slots(even).first?.weeks == [2,4,6,8], "validated timetable preserves even weeks")
        let oldExam = try JSONDecoder().decode(ExamItem.self, from: Data(#"{"id":"old","kcmc":"retained"}"#.utf8))
        var displayed = [oldExam]
        enum ProbeError: Error { case offline }
        var calls: [String] = []
        do {
            displayed = try await ExamSnapshotLoader.load(terms: ["2026-2027-1","2025-2026-2"]) { term in
                calls.append(term)
                if term == "2025-2026-2" { throw ProbeError.offline }
                return [try JSONDecoder().decode(ExamItem.self, from: Data(#"{"id":"new"}"#.utf8))]
            }
            check(false, "partial examination response must fail")
        } catch {
            check(displayed.map(\.id) == ["old"] && calls.count == 2, "one failed term retains the prior complete examination snapshot")
        }
        let complete = try await ExamSnapshotLoader.load(terms: ["2026-2027-2"]) { _ in [oldExam] }
        check(complete.first?.term == "2026-2027-2", "exam grouping belongs to the queried term")
        check(ExamLocationPresentation.concise(building: "9号栋 南区 第3层", room: "9-112") == "9号栋 南区 9-112",
              "exam location keeps building, south area and room while omitting an explicit floor")
        check(ExamLocationPresentation.concise(building: "9号栋 北区三楼", room: "9-112 第四层") == "9号栋 北区 9-112",
              "exam location removes common numeric and Chinese floor details from either field")
        check(ExamLocationPresentation.concise(building: "9号楼", room: nil) == "9号楼",
              "exam location does not mistake a building number for a floor")
        check(ExamLocationPresentation.concise(building: "西侧综合实验室", room: nil) == "西侧综合实验室",
              "unrecognized exam locations remain intact")
        check(ExamLocationPresentation.concise(building: "B1/2区", room: nil) == "B1/2区",
              "unknown building codes keep meaningful punctuation")
        check(ExamLocationPresentation.concise(building: nil, room: "考场待现场通知") == "考场待现场通知",
              "an unknown room is preserved when building data is absent")
        check(ExamLocationPresentation.concise(building: "4层", room: nil) == "4层",
              "a location containing only a floor marker is retained rather than erased")
        print("Academic reliability failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
