import Foundation
import Observation

struct EnrolledCourse: Decodable, Identifiable, Hashable {
    let id: String
    let xnxq: String
    let kcbh: String?
    let kcmc: String?
    let jxbmc: String?
    let jxbbh: String?
    let rkjs: String?
    let xf: String?
    let xdfs: String?
    let xkfs: String?
    let sksjdd: String?
    let kcxz: String?
    let kclx: String?
    let skfs: String?
    var studyStatus: String { xdfs == "1" ? "正常修读" : "修读状态待核实" }
}

struct EnrolledCoursesContext: Equatable {
    let terms: [String]
    let defaultTerm: String

    static func isTerm(_ value: String) -> Bool {
        let p = value.split(separator:"-")
        guard p.count == 3, p[0].count == 4, p[1].count == 4,
              let year = Int(p[0]), let next = Int(p[1]), next == year + 1,
              (1900...2200).contains(year), ["1","2","3"].contains(String(p[2])) else { return false }
        return true
    }

    /// Parse only the official personal-course selector, never unrelated page text or dates.
    static func parse(html: String) throws -> Self {
        let selectors = matches(#"<select\b([^>]*)>([\s\S]*?)</select>"#, html).filter {
            let a = attributes($0[1]); return a["id"] == "xnxq" || a["name"] == "xnxq"
        }
        guard selectors.count == 1 else { throw APIError.decoding("无法确认已选课程的学期选项") }
        var terms = Set<String>(), selected = Set<String>()
        for option in matches(#"<option\b([^>]*)>([\s\S]*?)</option>"#, selectors[0][2]) {
            guard let value = attributes(option[1])["value"], isTerm(value) else { continue }
            terms.insert(value)
            if option[1].range(of:#"(?:^|\s)selected(?:\s|=|$)"#,options:[.regularExpression,.caseInsensitive]) != nil {
                selected.insert(value)
            }
        }
        guard !terms.isEmpty, selected.count == 1, let current = selected.first else {
            throw APIError.decoding("无法确认已选课程的默认学期")
        }
        return Self(terms:terms.sorted(by:>),defaultTerm:current)
    }

    private static func attributes(_ value: String) -> [String:String] {
        var result: [String:String] = [:]
        for m in matches(#"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,value) {
            result[m[1].lowercased()] = m[2...4].first { !$0.isEmpty } ?? ""
        }
        return result
    }
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in:text,range:NSRange(location:0,length:ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at:$0).location == NSNotFound ? "" : ns.substring(with:match.range(at:$0)) }
        }
    }
}

enum EnrolledCoursesLoader {
    private struct Status: Decodable { let ret: Int; let msg: String? }
    private struct Page: Decodable {
        let page: Int
        let rows: Int
        let total: Int
        let totalPages: Int
        let results: [EnrolledCourse]
    }
    /// The grid is a flat status/results response, not the shared ret/data envelope.
    /// Collect locally and publish only when every page agrees on the complete result.
    static func load(term: String, fetch: (Int) async throws -> Data) async throws -> [EnrolledCourse] {
        guard EnrolledCoursesContext.isTerm(term) else { throw APIError.decoding("已选课程学期无效") }
        var collected: [EnrolledCourse] = [], ids = Set<String>()
        var total: Int?, pages: Int?, size: Int?
        for pn in 1...1000 {
            try Task.checkCancellation()
            let data = try await fetch(pn)
            try Task.checkCancellation()
            let status = try APIResponseDecoder.decodeBare(Status.self,from:data)
            guard status.ret == 0 else { throw APIResponseDecoder.businessError(status.ret,message:status.msg) }
            let page = try APIResponseDecoder.decodeBare(Page.self,from:data)
            guard page.page == pn, (1...10000).contains(page.rows), (0...100000).contains(page.total),
                  (0...1000).contains(page.totalPages),
                  page.totalPages == max(1,(page.total + page.rows - 1) / page.rows)
                    || (page.total == 0 && page.totalPages == 0) else {
                throw APIError.decoding("已选课程分页信息无效")
            }
            if let total, let pages, let size {
                guard total == page.total, pages == page.totalPages, size == page.rows else {
                    throw APIError.decoding("已选课程在分页读取期间发生变化，请重试")
                }
            } else { total = page.total; pages = page.totalPages; size = page.rows }
            let expected = min(page.rows,max(0,page.total - collected.count))
            guard page.results.count == expected else { throw APIError.decoding("已选课程结果不完整") }
            for row in page.results {
                guard !row.id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                      row.xnxq == term, ids.insert(row.id).inserted else {
                    throw APIError.decoding("已选课程标识重复、缺失或学期不匹配")
                }
                // Parent rows are personal teaching classes too; leaf is not an enrollment status.
                collected.append(row)
            }
            if pn >= page.totalPages {
                guard collected.count == page.total else { throw APIError.decoding("已选课程结果不完整") }
                return collected
            }
        }
        throw APIError.decoding("已选课程页数超过安全读取范围")
    }
}

struct EnrolledCoursesSummary: Equatable { let count: Int; let term: String }

@MainActor @Observable final class EnrolledCoursesModel {
    private(set) var context: EnrolledCoursesContext?
    private(set) var selectedTerm: String?
    private(set) var snapshot: [EnrolledCourse]?
    private(set) var isVerified = false
    private(set) var isLoading = false
    private(set) var errorText: String?
    private(set) var currentSummary: EnrolledCoursesSummary?
    private let generation: () -> UInt64
    private let contextLoader: (UInt64) async throws -> EnrolledCoursesContext
    private let coursesLoader: (String, UInt64) async throws -> [EnrolledCourse]
    private var ownerGeneration: UInt64?
    private var requestVersion: UInt64 = 0
    init(generation: @escaping () -> UInt64, contextLoader: @escaping (UInt64) async throws -> EnrolledCoursesContext,
         coursesLoader: @escaping (String, UInt64) async throws -> [EnrolledCourse]) {
        self.generation = generation; self.contextLoader = contextLoader; self.coursesLoader = coursesLoader
    }
    func load(term: String? = nil, refreshContext: Bool = false) async {
        discardIfAccountChanged()
        let owner = generation()
        ownerGeneration = owner
        requestVersion &+= 1
        let version = requestVersion
        if let term, term != selectedTerm { snapshot = nil; selectedTerm = term }
        isLoading = true; isVerified = false; errorText = nil
        defer { if accepts(version,owner:owner) { isLoading = false } }
        do {
            if context == nil || refreshContext {
                let fetched = try await contextLoader(owner)
                guard accepts(version,owner:owner), !Task.isCancelled else { return }
                context = fetched
            }
            guard let context else { throw APIError.empty }
            let target = term ?? selectedTerm ?? context.defaultTerm
            guard context.terms.contains(target) else { throw APIError.decoding("该学期不在教务提供的已选查询范围内") }
            if selectedTerm != target { snapshot = nil }
            selectedTerm = target
            let courses = try await coursesLoader(target,owner)
            guard accepts(version,owner:owner), !Task.isCancelled else { return }
            guard courses.allSatisfy({$0.xnxq == target}) else { throw APIError.decoding("已选课程学期不匹配") }
            snapshot = courses.sorted { ($0.kcmc ?? "").localizedStandardCompare($1.kcmc ?? "") == .orderedAscending }
            isVerified = true
            if target == context.defaultTerm { currentSummary = EnrolledCoursesSummary(count:courses.count,term:target) }
        } catch {
            guard accepts(version,owner:owner), !Task.isCancelled else { return }
            errorText = (error as? APIError)?.localizedDescription ?? "完整已选结果读取失败，请重试"
        }
    }
    func invalidate() { requestVersion &+= 1; isVerified = false; isLoading = false }
    func discardIfAccountChanged() {
        guard let ownerGeneration, ownerGeneration != generation() else { return }
        requestVersion &+= 1
        self.ownerGeneration = nil
        context = nil; selectedTerm = nil; snapshot = nil; currentSummary = nil
        isVerified = false; isLoading = false; errorText = nil
    }
    private func accepts(_ version: UInt64, owner: UInt64) -> Bool {
        guard owner == generation() else { discardIfAccountChanged(); return false }
        return version == requestVersion
    }
    func currentCourse(for record: EnrolledCourse, catalog: ElectiveState<TeachingClass>, catalogTerm: String?) -> TeachingClass? {
        guard isVerified, !isLoading, ownerGeneration == generation(),
              let context, selectedTerm == context.defaultTerm, record.xnxq == selectedTerm,
              record.xnxq == catalogTerm, record.xdfs == "1", record.xkfs == "选课",
              snapshot?.contains(record) == true,
              catalog.isSnapshotVerified, catalog.snapshotGeneration == generation(),
              let number = record.jxbbh, !number.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              let course = catalog.snapshot?.courses.first(where:{$0.id == record.id}),
              course.jxbbh == number, course.isSelected else { return nil }
        return course
    }
}
