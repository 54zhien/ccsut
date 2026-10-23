//
//  API.swift
//  CCSUT
//
//  网络层：所有 /admin/** 请求 + 课表 HTML 解析
//
//  认证方式：纯 Cookie（withCredentials），没有 token、没有签名
//

import Foundation

// MARK: - 错误

enum APIError: LocalizedError {
    case notLoggedIn
    case http(Int)
    case business(Int, String)
    case empty
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "登录已失效，请重新登录"
        case .http(let code): return "网络错误 HTTP \(code)"
        case .business(let ret, let msg): return "接口返回错误 [\(ret)] \(msg)"
        case .empty: return "接口返回空数据"
        case .decoding(let what): return "数据解析失败：\(what)"
        }
    }
}

// MARK: - 客户端

final class APIClient {
    static let shared = APIClient()

    /// 诊断用：最近一次请求的路径 + 响应片段
    nonisolated(unsafe) static var lastTrace = ""

    private let base = URL(string: "https://tls.ccsut.cn")!
    private let session: URLSession

    /// 教务系统对移动端 UA 没有特殊处理，用 iPhone UA 即可
    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    init(configuration: URLSessionConfiguration = .default) {
        let cfg = configuration
        // 所有原生请求只使用 CookieJar；逐跳收取 Cookie，避免系统池覆盖请求头。
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil

        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 20
        session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
    }

    // MARK: 基础请求

    private func makeRequest(_ path: String, method: String, query: [URLQueryItem] = [], form: [String: String]? = nil) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://tls.ccsut.cn/frontend/views/student/xkPage/index.html", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        if let form {
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = form
                .map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }
                .joined(separator: "&")
                .data(using: .utf8)
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await response(for: req)

        if let path = req.url?.path, path.contains("listjxbDataV2") || path.contains("listV2") {
            let body = String(data: data, encoding: .utf8) ?? ""
            let hasInit = body.contains("initData")
            Self.lastTrace = "\(path.components(separatedBy: "/").last ?? "") \(data.count)b initData=\(hasInit ? "有" : "无")"
        }
        return (data, http)
    }

    /// 认证和业务共用同一条传输路径。禁止自动跳转，每跳重新匹配 Cookie。
    /// timeout 是整个跳转链的预算，避免冷启动被多次超时拖住。
    func response(for request: URLRequest, timeout: TimeInterval = 20,
                  allowAuthenticationRedirects: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var req = request
        let generation = CookieJar.generation
        let deadline = Date().addingTimeInterval(timeout)
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard CookieJar.generation == generation else { throw CancellationError() }
            guard !CookieJar.shared.isEmpty else { throw APIError.notLoggedIn }
            guard let url = req.url, url.scheme == "https",
                  let host = url.host, host == "ccsut.cn" || host.hasSuffix(".ccsut.cn")
            else { throw APIError.notLoggedIn }
            if !allowAuthenticationRedirects, Self.isAuthenticationURL(url) { throw APIError.notLoggedIn }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw URLError(.timedOut) }
            req.timeoutInterval = remaining
            req.httpShouldHandleCookies = false
            req.setValue(CookieJar.header(for: url), forHTTPHeaderField: "Cookie")

            let (data, resp) = try await session.data(for: req)
            try Task.checkCancellation()
            guard CookieJar.generation == generation else { throw CancellationError() }
            guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1) }
            if let fields = http.allHeaderFields as? [String: String] {
                CookieJar.upsert(HTTPCookie.cookies(withResponseHeaderFields: fields, for: url),
                                 generation: generation)
            }
            if [401, 403].contains(http.statusCode) { throw APIError.notLoggedIn }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL
                else { throw APIError.http(http.statusCode) }
                if http.statusCode == 303 || ([301, 302].contains(http.statusCode) && req.httpMethod == "POST") {
                    req.httpMethod = "GET"
                    req.httpBody = nil
                    req.setValue(nil, forHTTPHeaderField: "Content-Type")
                    req.setValue(nil, forHTTPHeaderField: "Content-Length")
                }
                // 不把业务 POST 的表单转发到另一个认证域。
                if next.host != url.host, req.httpBody != nil { throw APIError.notLoggedIn }
                req.url = next
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
            if !allowAuthenticationRedirects, let final = http.url, Self.isAuthenticationURL(final) {
                throw APIError.notLoggedIn
            }
            return (data, http)
        }
        throw URLError(.httpTooManyRedirects)
    }

    static func isAuthenticationURL(_ url: URL) -> Bool {
        if url.host == "auth.ccsut.cn" { return true }
        let path = url.path.lowercased()
        return path == "/admin/caslogin" || path.hasPrefix("/admin/login") || path.contains("loginfailpage")
    }

    // MARK: 泛型 JSON

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await decode(send(makeRequest(path, method: "GET", query: query)))
    }

    func post<T: Decodable>(_ path: String, form: [String: String] = [:]) async throws -> T {
        try await decode(send(makeRequest(path, method: "POST", form: form)))
    }

    private func decode<T: Decodable>(_ result: (Data, HTTPURLResponse)) throws -> T {
        let (data, _) = result
        guard !data.isEmpty else { throw APIError.empty }

        // 先按统一壳解
        if let env = try? JSONDecoder().decode(APIEnvelope<T>.self, from: data) {
            if env.ret != 0 {
                throw APIError.business(env.ret, env.msg ?? "")
            }
            if let payload = env.data { return payload }
            throw APIError.empty
        }
        // 少数接口直接返回裸数据
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw APIError.decoding(preview)
        }
    }

    // MARK: HTML

    func html(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        let (data, _) = try await send(makeRequest(path, method: "GET", query: query))
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - 业务接口

extension APIClient {
    /// 选课页初始化：学生信息、字典、批次加密串
    func electiveInit() async throws -> ElectiveInit {
        try await post("/admin/xsd/xk/listV2")
    }

    /// 教学班列表
    /// - Parameters:
    ///   - keyword: 课程名模糊搜索
    ///   - batch: (pcid, pcenc)，来自 ElectiveInit.pcencs；不传则按当前开放批次
    func teachingClasses(keyword: String = "", batch: (pcid: String, pcenc: String)? = nil) async throws -> TeachingClassPage {
        var form: [String: String] = [
            "from": "ggxxk",
            "kcmc": keyword,
            "kcxz": "",
            "jxms": "",
            "kcgs": "",
            "teacher": "",
            "kkxq": "",
            "kclb": "",
            "kclx": "",
        ]
        if let batch {
            form["pcid"] = batch.pcid
            form["pcenc"] = batch.pcenc
        }
        return try await post("/admin/xsd/xk/listjxbDataV2", form: form)
    }

    /// 课表页骨架（HTML）。真正数据在 sdpkkbList，这个只用来取 xhid
    func scheduleHTML(xnxq: String? = nil) async throws -> String {
        var q: [URLQueryItem] = []
        if let xnxq { q.append(URLQueryItem(name: "xnxq", value: xnxq)) }
        return try await html("/admin/xsd/pkgl/xskb/queryKbForXsd", query: q)
    }

    /// 从课表页里挖出 xhid（一个长串，服务端校验用）
    func scheduleXhid(xnxq: String? = nil) async throws -> String {
        let page = try await scheduleHTML(xnxq: xnxq)
        let patterns = [
            #"id=["']xhid["'][^>]*?value=["']([^"']+)"#,
            #"name=["']xhid["'][^>]*?value=["']([^"']+)"#,
            #"value=["']([A-Za-z0-9]{40,})["'][^>]*?id=["']xhid["']"#,
        ]
        for p in patterns {
            if let v = page.firstCapture(p), !v.isEmpty { return v }
        }
        throw APIError.decoding("课表页里找不到 xhid")
    }

    /// 原始响应（诊断用）：不做解码，直接返回服务端说了什么
    func teachingClassesRaw(batch: (pcid: String, pcenc: String)?) async throws -> String {
        var form: [String: String] = [
            "from": "ggxxk", "kcmc": "", "kcxz": "", "jxms": "",
            "kcgs": "", "teacher": "", "kkxq": "", "kclb": "", "kclx": "",
        ]
        if let batch {
            form["pcid"] = batch.pcid
            form["pcenc"] = batch.pcenc
        }
        let req = makeRequest("/admin/xsd/xk/listjxbDataV2", method: "POST", form: form)
        let body = req.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<无body>"
        let (data, _) = try await send(req)
        let resp = String(data: data, encoding: .utf8) ?? "<二进制>"
        return "BODY[\(body.count)]: \(body.prefix(220))\nRESP: \(resp.prefix(260))"
    }

    /// 原始 listV2 响应（诊断用）
    func electiveInitRaw() async throws -> String {
        let req = makeRequest("/admin/xsd/xk/listV2", method: "POST", form: [:])
        let (data, _) = try await send(req)
        return String(data: data, encoding: .utf8) ?? "<二进制>"
    }

    /// 真实课表数据（JSON，实测 98 条专业课）
    func scheduleItems(xnxq: String, xhid: String) async throws -> [ScheduleItem] {
        let q: [URLQueryItem] = [
            URLQueryItem(name: "xnxq", value: xnxq),
            URLQueryItem(name: "xhid", value: xhid),
            URLQueryItem(name: "xqdm", value: "01"),
            URLQueryItem(name: "zdzc", value: ""),
            URLQueryItem(name: "zxzc", value: ""),
            URLQueryItem(name: "xskbxslx", value: "0"),
        ]
        let req = makeRequest("/admin/xsd/pkgl/xskb/sdpkkbList", method: "POST", query: q, form: [:])
        return try await decode(send(req))
    }

    /// 全部成绩（xnxq=111 是服务端约定的「全部学期」，实测 61 门跨 5 学期）
    ///
    /// 注意：这不是 /admin/xsd/xsdzgcjcx/xscjdy（那条是 JSP 报表，学校缺 .rpx 文件），
    /// 而是移动端页面 /admin/ydd/inf/showScore 背后用的 JSON 接口。
    func scoreList() async throws -> [ScoreItem] {
        struct Payload: Decodable { let xscjList: [ScoreItem]? }
        let payload: Payload = try await get(
            "/admin/ydd/inf/getXscjJson",
            query: [URLQueryItem(name: "xnxq", value: "111")]
        )
        return payload.xscjList ?? []
    }

    /// 选课
    ///
    /// POST /admin/xsd/xk/xsdXkV2  { jxbid, pcid, sfqc }
    /// 实测：ret=0 "选课成功"；超限时 ret=-1 "当前批次已选门数超过【4门】"
    @discardableResult
    func enroll(jxbid: String, pcid: String) async throws -> String {
        struct Resp: Decodable { let ret: Int; let msg: String? }
        let (data, _) = try await send(makeRequest(
            "/admin/xsd/xk/xsdXkV2",
            method: "POST",
            form: ["jxbid": jxbid, "pcid": pcid, "sfqc": ""]
        ))
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard r.ret == 0 else { throw APIError.business(r.ret, r.msg ?? "选课失败") }
        return r.msg ?? "选课成功"
    }

    /// 退课
    ///
    /// POST /admin/xsd/xk/xsdTkV2  { jxbid, pcid }
    @discardableResult
    func dropClass(jxbid: String, pcid: String) async throws -> String {
        struct Resp: Decodable { let ret: Int; let msg: String? }
        let (data, _) = try await send(makeRequest(
            "/admin/xsd/xk/xsdTkV2",
            method: "POST",
            form: ["jxbid": jxbid, "pcid": pcid]
        ))
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard r.ret == 0 else { throw APIError.business(r.ret, r.msg ?? "退课失败") }
        return r.msg ?? "退课成功"
    }

    /// 考试安排
    ///
    /// POST /admin/xsd/kwglXsdKscx/getXsKsxx  { xnxq }
    /// 实测 2025-2026-2 有 8 场，含考场、座位号、考试批次
    func examList(xnxq: String) async throws -> [ExamItem] {
        let page: ExamPage = try await post(
            "/admin/xsd/kwglXsdKscx/getXsKsxx",
            form: ["xnxq": xnxq]
        )
        return page.list ?? []
    }

    /// 当前教学周（校历接口，实测返回 {"xlzc":"7"}）
    func currentTeachingWeek() async throws -> Int {
        struct WeekInfo: Decodable { let xlzc: String? }
        let info: WeekInfo = try await get("/admin/api/getXlzc")
        return Int(info.xlzc ?? "") ?? 1
    }

    /// 校历周次
    func calendarWeeks() async throws -> [String] {
        let data = try await getRaw("/admin/api/getZclistByXnxq", query: [])
        return data
    }

    private func getRaw(_ path: String, query: [URLQueryItem]) async throws -> [String] {
        let (data, _) = try await send(makeRequest(path, method: "GET", query: query))
        if let arr = try? JSONDecoder().decode([String].self, from: data) { return arr }
        if let env = try? JSONDecoder().decode(APIEnvelope<[String]>.self, from: data), let d = env.data {
            return d
        }
        return []
    }
}

// MARK: - 编码工具

extension String {
    var urlEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        // 斜杠也要编码：pcenc 是 base64，未编码的 / 会被服务端当成路径分隔符
        allowed.remove(charactersIn: "+&=%?#/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - 课表 HTML 解析

enum ScheduleParser {
    /// 解析 queryKbForXsd 返回的表格
    ///
    /// 结构：
    /// ```
    /// <thead><tr><th>节次</th><th>星期日</th><th>星期一</th>…</tr></thead>
    /// <tbody>
    ///   <tr><td rowspan="4">上午</td><td>1</td><td>…</td><td>课程</td>…</tr>
    /// </tbody>
    /// ```
    /// rowspan 会导致列错位，用占位网格处理
    static func parse(_ html: String) -> ScheduleBundle {
        var bundle = ScheduleBundle()

        guard let tableRange = html.range(of: "<table"),
              let tableEnd = html.range(of: "</table>", range: tableRange.lowerBound..<html.endIndex)
        else { return bundle }

        let table = String(html[tableRange.lowerBound..<tableEnd.upperBound])

        // 1. 表头 → 星期列顺序
        let weekdays = parseHeader(table)
        // 2. 数据行
        let rows = parseRows(table, weekdayColumns: weekdays)

        bundle.slots = rows
        bundle.periods = Array(1...max(12, (rows.map(\.endPeriod).max() ?? 12)))
        return bundle
    }

    // 星期日/一/… 的列顺序（有的学校周日排第一列）
    private static func parseHeader(_ table: String) -> [(weekday: Int, col: Int)] {
        guard let theadRange = table.range(of: "<thead"),
              let theadEnd = table.range(of: "</thead>", range: theadRange.lowerBound..<table.endIndex)
        else { return [] }
        let thead = String(table[theadRange.upperBound..<theadEnd.lowerBound])

        let names: [(String, Int)] = [
            ("星期日", 7), ("星期天", 7),
            ("星期一", 1), ("星期二", 2), ("星期三", 3),
            ("星期四", 4), ("星期五", 5), ("星期六", 6),
        ]

        var result: [(Int, Int)] = []
        var col = 0
        for cell in matches(in: thead, pattern: "<th[^>]*>([\\s\\S]*?)</th>") {
            let text = stripTags(cell)
            if let hit = names.first(where: { text.contains($0.0) }) {
                result.append((hit.1, col))
            }
            col += 1
        }
        return result
    }

    private static func parseRows(_ table: String, weekdayColumns: [(weekday: Int, col: Int)]) -> [ScheduleSlot] {
        guard let tbodyRange = table.range(of: "<tbody") else { return [] }
        let tbody = String(table[tbodyRange.lowerBound...])

        // 列 → 当前占用到的行号
        var occupied: [Int: Int] = [:]
        var slots: [ScheduleSlot] = []
        var rowIndex = 0

        for rowHTML in matches(in: tbody, pattern: "<tr[^>]*>([\\s\\S]*?)</tr>") {
            // 节次：这一行第一个纯数字单元格
            var period = 0
            var col = 0

            for (attrs, inner) in cells(in: rowHTML) {
                // 跳过被 rowspan 占掉的列（加保护，防止越界）
                var guardCount = 0
                while let until = occupied[col], until >= rowIndex, guardCount < 32 {
                    col += 1
                    guardCount += 1
                }
                if col > 31 { break }

                let rowspan = Int(attr(attrs, "rowspan") ?? "1") ?? 1
                let colspan = Int(attr(attrs, "colspan") ?? "1") ?? 1
                let text = stripTags(inner)
                let lines = splitLines(inner)

                if period == 0, let p = Int(text.trimmingCharacters(in: .whitespaces)), (1...20).contains(p) {
                    period = p
                }

                if let hit = weekdayColumns.first(where: { $0.col == col }), period > 0, !lines.isEmpty {
                    // 第一行是课程名，后面依次是教师、教室
                    let course = lines.first ?? ""
                    let teacher = lines.count > 1 ? lines[1] : ""
                    let room = lines.count > 2 ? lines[2] : ""

                    slots.append(
                        ScheduleSlot(
                            course: course,
                            teacher: teacher,
                            room: room,
                            weekday: hit.weekday,
                            startPeriod: period,
                            endPeriod: period + rowspan - 1,
                            weeks: []
                        )
                    )
                    // 记录 rowspan 占用
                    for r in 0..<rowspan {
                        occupied[col] = rowIndex + r
                    }
                }

                col += colspan
            }
            rowIndex += 1
        }
        return slots
    }

    // MARK: 正则小工具

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            ns.substring(with: $0.range)
        }
    }

    private static func cells(in row: String) -> [(attrs: String, inner: String)] {
        guard let re = try? NSRegularExpression(pattern: "<td([^>]*)>([\\s\\S]*?)</td>", options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = row as NSString
        return re.matches(in: row, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2)))
        }
    }

    private static func attr(_ attrs: String, _ name: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*[\"']?([\\d]+)", options: .caseInsensitive) else { return nil }
        let ns = attrs as NSString
        guard let m = re.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// 把单元格里的 <br> / </div> / </p> 当换行，去标签，去空行
    private static func splitLines(_ html: String) -> [String] {
        var s = html
        for tag in ["<br>", "<br/>", "<br />", "</div>", "</p>", "</span>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        return s
            .components(separatedBy: "\n")
            .map { stripTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "&nbsp;" }
    }

    private static func stripTags(_ html: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "<[^>]+>") else { return html }
        let ns = html as NSString
        let plain = re.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return plain
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// MARK: - 正则取值

extension String {
    /// 返回第一个捕获组
    func firstCapture(_ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
