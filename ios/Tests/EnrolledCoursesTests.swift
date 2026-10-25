import Foundation

@MainActor private final class GenerationBox { var value: UInt64 = 1 }
private actor ReadGate {
    private var entered = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    func block() async {
        entered = true; observers.forEach { $0.resume() }; observers = []
        await withCheckedContinuation { release = $0 }
    }
    func waitForEntry() async {
        if entered { return }; await withCheckedContinuation { observers.append($0) }
    }
    func open() { release?.resume(); release = nil }
}

@main struct EnrolledCoursesTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL") \(name)"); if !value { failures += 1 }
        }
        let current = "2026-2027-1", past = "2024-2025-1"
        func record(_ id: String, term: String = "2026-2027-1", method: String = "选课", status: String = "1") -> [String: Any] {
            ["id":id,"xnxq":term,"kcbh":"COURSE-\(id)","kcmc":"Course \(id)","jxbbh":"CLASS-\(id)",
             "jxbmc":"Class \(id)","rkjs":"Fixture teacher","xf":"1","xdfs":status,"xkfs":method,
             "hasChildren":true,"leaf":false]
        }
        func course(_ id: String, term: String = "2026-2027-1", method: String = "选课", status: String = "1") throws -> EnrolledCourse {
            try JSONDecoder().decode(EnrolledCourse.self, from: JSONSerialization.data(withJSONObject: record(id,term:term,method:method,status:status)))
        }
        func page(_ rows: [[String: Any]], pn: Int = 1, total: Int? = nil, size: Int = 100, pages: Int = 1) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["ret":0,"page":pn,"rows":size,"total":total ?? rows.count,"totalPages":pages,"results":rows])
        }
        let context = EnrolledCoursesContext(terms:[current,past],defaultTerm:current)
        let html = """
        <select id='other'><option value='2099-2100-1' selected>unrelated</option></select>
        <select name="xnxq" id="xnxq" multiple><option value="001">Choose</option>
        <option value="2026-2027-1" selected="selected">Current</option><option value='2024-2025-1'>Past</option></select>
        """
        do {
            let parsed = try EnrolledCoursesContext.parse(html:html)
            check(parsed.terms == [current,past] && parsed.defaultTerm == current,"only official selected-course terms and default are used")
        } catch { check(false,"official term selector parses") }
        for bad in ["<html>login</html>",html.replacingOccurrences(of:" selected=\"selected\"",with:""),html.replacingOccurrences(of:"value='2024-2025-1'",with:"value='2024-2025-1' selected")] {
            do { _ = try EnrolledCoursesContext.parse(html:bad); check(false,"missing or ambiguous default cannot be guessed") }
            catch { check(true,"missing or ambiguous default cannot be guessed") }
        }
        var requested: [Int] = []
        do {
            let rows = try await EnrolledCoursesLoader.load(term:current) { pn in
                requested.append(pn)
                return try page([record(pn == 1 ? "closed" : "assigned",method:pn == 1 ? "选课" : "配课")],pn:pn,total:2,size:1,pages:2)
            }
            check(rows.map(\.id) == ["closed","assigned"] && requested == [1,2],"complete results retain closed-batch and assigned courses across all pages")
        } catch { check(false,"complete results load independently of active batches") }
        do {
            let rows = try await EnrolledCoursesLoader.load(term:past) { _ in try page([record("old",term:past)]) }
            check(rows.count == 1 && rows[0].xnxq == past,"past term returns its own records")
            let empty = try await EnrolledCoursesLoader.load(term:past) { _ in try page([],pages:0) }
            check(empty.isEmpty,"explicit successful empty result is accepted")
        } catch { check(false,"past and empty results load") }
        let badBodies: [Data] = [
            Data(#"{"ret":0,"page":1,"rows":100,"total":0,"totalPages":0}"#.utf8),
            Data(#"{"ret":0,"page":1,"rows":100,"total":1,"totalPages":1,"results":[]}"#.utf8),
            Data(#"{"ret":0,"page":1,"rows":100,"total":-1,"totalPages":1,"results":[]}"#.utf8),
            try page([record("wrong-term",term:past)]),try page([record("")]),
            try page([record("duplicate"),record("duplicate")]),try page([record("x")],pn:2),
            Data(#"{"results":[],"page":1,"rows":100,"total":0,"totalPages":0}"#.utf8),
            Data("<html>login</html>".utf8)
        ]
        for (index,body) in badBodies.enumerated() {
            do { _ = try await EnrolledCoursesLoader.load(term:current) { _ in body }; check(false,"invalid grid \(index) is rejected, not a smaller complete snapshot") }
            catch { check(true,"invalid grid \(index) is rejected, not a smaller complete snapshot") }
        }
        do {
            _ = try await EnrolledCoursesLoader.load(term:current) { _ in Data(#"{"ret":-1,"msg":"session expired","results":"bad"}"#.utf8) }
            check(false,"business authentication failure wins over malformed results")
        } catch let error as APIError {
            if case .notLoggedIn = error { check(true,"business authentication failure wins over malformed results") }
            else { check(false,"business authentication maps to notLoggedIn") }
        }
        do {
            _ = try await EnrolledCoursesLoader.load(term:current) { pn in
                if pn == 2 { throw URLError(.timedOut) }
                return try page([record("first")],total:2,size:1,pages:2)
            }
            check(false,"later page failure rejects entire result")
        } catch { check(true,"later page failure rejects entire result") }

        let generation = GenerationBox()
        var fail = false
        let model = EnrolledCoursesModel(generation:{generation.value},contextLoader:{ _ in context },coursesLoader:{ term,_ in
            if fail { throw URLError(.timedOut) }; return [try course(term == current ? "closed" : "past",term:term)]
        })
        await model.load()
        check(model.snapshot?.map(\.id) == ["closed"] && model.isVerified,"model publishes complete current result without an active catalog")
        check(model.currentSummary?.count == 1 && model.currentSummary?.term == current,"current summary uses complete result count")
        fail = true; await model.load()
        check(model.snapshot?.first?.id == "closed" && !model.isVerified && model.errorText != nil,"failed same-term refresh retains content with an unverified notice")
        check(model.currentSummary == nil,"failed current-result refresh cannot keep an apparently verified summary")
        fail = false; await model.load()
        fail = false; await model.load(term:past)
        check(model.snapshot?.first?.id == "past" && model.selectedTerm == past,"term change replaces old content")
        check(model.currentSummary?.term == current,"history does not overwrite the current summary")
        fail = true; generation.value = 2; model.discardIfAccountChanged()
        check(model.snapshot == nil && model.context == nil && model.currentSummary == nil,"account switch clears records, context, and summary before a new read")
        await model.load()
        check(model.snapshot == nil && model.currentSummary == nil && !model.isVerified,"a failed new-account read cannot resurrect the previous account snapshot")

        let gate = ReadGate()
        let race = EnrolledCoursesModel(generation:{generation.value},contextLoader:{ _ in context },coursesLoader:{ term,_ in
            if term == past { await gate.block() }; return [try course(term == past ? "late" : "new",term:term)]
        })
        let old = Task { await race.load(term:past) }; await gate.waitForEntry()
        await race.load(term:current); await gate.open(); await old.value
        check(race.selectedTerm == current && race.snapshot?.first?.id == "new","late history response cannot replace a newer term request")
        let accountGate = ReadGate()
        let accountRace = EnrolledCoursesModel(generation:{generation.value},contextLoader:{ _ in context },coursesLoader:{ term,owner in
            if owner == 2 { await accountGate.block() }; return [try course(owner == 2 ? "old-account" : "new-account",term:term)]
        })
        let oldAccount = Task { await accountRace.load() }; await accountGate.waitForEntry()
        generation.value = 3; await accountRace.load(); await accountGate.open(); await oldAccount.value
        check(accountRace.snapshot?.first?.id == "new-account","late old-account response cannot wipe or publish over new-account records")

        let cancelGate = ReadGate()
        let cancelled = EnrolledCoursesModel(generation:{generation.value},contextLoader:{ _ in context },coursesLoader:{ term,_ in
            await cancelGate.block(); return [try course("cancelled",term:term)]
        })
        let cancelledRead = Task { await cancelled.load() }; await cancelGate.waitForEntry()
        cancelledRead.cancel(); await cancelGate.open(); await cancelledRead.value
        check(cancelled.snapshot == nil && !cancelled.isVerified && cancelled.errorText != nil && !cancelled.isLoading,
              "cancelled read remains explicitly unverified rather than a successful empty list")

        let link = EnrolledCoursesModel(generation:{generation.value},contextLoader:{ _ in context },coursesLoader:{ term,_ in [try course("match",term:term)] })
        await link.load(catalogGeneration:generation.value)
        func catalog(_ json: String) throws -> ElectiveState<TeachingClass> {
            let c = try JSONDecoder().decode(TeachingClass.self,from:Data(json.utf8))
            var b = ElectiveSnapshotBuilder<TeachingClass>(); b.append([ElectiveCourseRecord(id:c.id,value:c,actionFacts:ElectiveCourseActionFacts(isSelected:c.isSelected,selectionFlag:c.sfkxk,isFull:c.isFull))],batchID:"live")
            var s = ElectiveState<TeachingClass>(); s.publish(b.snapshot,generation:generation.value); return s
        }
        let live = try catalog(#"{"id":"match","jxbbh":"CLASS-match","status":"1"}"#)
        let matched = try course("match")
        check(link.currentCourse(for:matched,catalog:live,catalogTerm:current)?.id == "match","only exact verified current teaching class may reuse the existing action card")
        check(link.currentCourse(for:try course("closed"),catalog:live,catalogTerm:current) == nil,"closed batch record cannot acquire a fabricated action mapping")
        check(link.currentCourse(for:try course("match",method:"配课"),catalog:live,catalogTerm:current) == nil,"assigned course cannot acquire a drop action")
        check(link.currentCourse(for:try course("match",status:"other"),catalog:live,catalogTerm:current) == nil,"unknown study status remains read-only")
        let conflicting = try catalog(#"{"id":"match","jxbbh":"CLASS-match","status":"0"}"#)
        check(link.currentCourse(for:matched,catalog:conflicting,catalogTerm:current) == nil,"conflicting active selection cannot enable a drop or enrollment")
        let otherClass = try catalog(#"{"id":"match","jxbbh":"OTHER","status":"1"}"#)
        check(link.currentCourse(for:matched,catalog:otherClass,catalogTerm:current) == nil,"course id without matching teaching-class number is insufficient")
        check(link.currentCourse(for:matched,catalog:live,catalogTerm:past) == nil,"different catalog term cannot grant mutation authority")
        await link.load()
        check(link.currentCourse(for:matched,catalog:live,catalogTerm:current) == nil,
              "an independent selected-result retry cannot reactivate an older catalog snapshot")
        await link.load(term:past)
        check(link.currentCourse(for:matched,catalog:live,catalogTerm:current) == nil,"history is read-only even when an id happens to match a current class")
        print("Enrolled course failures: \(failures)"); exit(failures == 0 ? 0 : 1)
    }
}
