import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol CampusSessionCredentials: Sendable {
    var generation: UInt64 { get }
    func header(for url: URL) -> String?
    func accept(_ cookies: [HTTPCookie], generation: UInt64)
}

protocol CampusTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class CampusNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class CampusURLTransport: CampusTransport, @unchecked Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: CampusNoRedirect(), delegateQueue: nil)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusError.invalidResponse }
        return (data, response)
    }
}

enum CampusTravelKind: String, CaseIterable, Sendable {
    case departure, returning
    var title: String { self == .departure ? "离校记录" : "返校记录" }
    var page: URL {
        URL(string: "https://ehall.ccsut.cn/backstage/returnschool/page/mobile/#/" +
            (self == .departure ? "stu-leave-list" : "return-list-stu"))!
    }
    fileprivate var path: String {
        self == .departure ? "/backstage/returnschool/studentGqleave/queryStuGqleaveInfo" :
            "/backstage/returnschool/returnApply/queryListByStudentId"
    }
}

protocol CampusReading: Sendable {
    func leaveRecords(page: Int, size: Int) async throws -> CampusLeavePage
    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord]
}

actor CampusClient: CampusReading {
    private enum Subsystem: Hashable { case leave, travel }
    private enum Failure: Error { case unauthorized }
    private struct Identity: Decodable, Sendable {
        let errcode: Int
        let account: String
        let userId: String
    }

    static let leavePage = URL(string: "https://ehall.ccsut.cn/backstage/leaveadmin/page/mobile/#/leaveList")!
    static let leaveForm = URL(string: "https://ehall.ccsut.cn/backstage/leaveadmin/page/mobile/#/leaveForm")!
    private let account: String
    private let credentials: any CampusSessionCredentials
    private let transport: any CampusTransport
    private let generation: UInt64
    private var identities: [Subsystem: Identity] = [:]

    init(account: String, credentials: any CampusSessionCredentials, transport: any CampusTransport = CampusURLTransport()) {
        self.account = account
        self.credentials = credentials
        self.transport = transport
        generation = credentials.generation
    }

    func leaveRecords(page: Int = 1, size: Int = 20) async throws -> CampusLeavePage {
        guard page > 0, (1...100).contains(size) else { throw CampusError.invalidResponse }
        let data = try await query(.leave, callback: Self.leavePage,
                                   path: "/backstage/leaveadmin/leaveApply/queryListForPage") { userId in
            ["pageNum": page, "pageSize": size, "pageParam": ["userId": userId]]
        }
        return try CampusDecoder.leavePage(data)
    }

    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord] {
        let data = try await query(.travel, callback: kind.page, path: kind.path) { ["studentId": $0] }
        return try CampusDecoder.travelRecords(data)
    }

    private func query(_ subsystem: Subsystem, callback: URL, path: String,
                       body: (String) -> [String: Any]) async throws -> Data {
        for attempt in 0...1 {
            let identity = try await identity(for: subsystem, callback: callback, force: attempt == 1)
            var request = request(path)
            request.httpMethod = "POST"
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(callback.absoluteString, forHTTPHeaderField: "Referer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body(identity.userId))
            do { return try await send(request).0 }
            catch Failure.unauthorized {
                identities[subsystem] = nil
                if attempt == 1 { throw CampusError.authentication }
            }
        }
        throw CampusError.authentication
    }

    private func identity(for subsystem: Subsystem, callback: URL, force: Bool) async throws -> Identity {
        try checkState()
        guard !account.isEmpty else { throw CampusError.authentication }
        if !force, let cached = identities[subsystem] { return cached }
        var result = try await validate(callback: callback)
        if result == nil {
            let redirect = request("/backstage/cas-proxy/app/redirect", query: [
                URLQueryItem(name: "serverName", value: "https://ehall.ccsut.cn")
            ])
            do { _ = try await send(redirect, authentication: true) }
            catch Failure.unauthorized { throw CampusError.authentication }
            result = try await validate(callback: callback)
        }
        guard let result else { throw CampusError.authentication }
        try checkState()
        identities[subsystem] = result
        return result
    }

    private func validate(callback: URL) async throws -> Identity? {
        let req = request("/backstage/cas-proxy/app/validate_full", query: [
            URLQueryItem(name: "callback", value: callback.absoluteString),
            URLQueryItem(name: "timestamp", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ])
        let data: Data
        do { data = try await send(req, authentication: true).0 }
        catch Failure.unauthorized { return nil }
        guard let identity = try? JSONDecoder().decode(Identity.self, from: data),
              identity.errcode == 2000, !identity.userId.isEmpty else { return nil }
        guard identity.account == account else { throw CampusError.identityMismatch }
        return identity
    }

    private func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(string: "https://ehall.ccsut.cn" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Follow only the official CAS/ehall chain, with fresh Cookie matching per hop.
    private func send(_ original: URLRequest, authentication: Bool = false) async throws -> (Data, HTTPURLResponse) {
        var request = original
        let deadline = Date().addingTimeInterval(30)
        for _ in 0..<12 {
            try checkState()
            guard let rawURL = request.url, let url = Self.trustedURL(rawURL),
                  authentication || url.host == "ehall.ccsut.cn" else { throw CampusError.authentication }
            request.url = url
            request.httpShouldHandleCookies = false
            request.setValue(credentials.header(for: url), forHTTPHeaderField: "Cookie")
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw CampusError.serviceUnavailable }
            request.timeoutInterval = min(20, remaining)
            let data: Data
            let response: HTTPURLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch { throw CampusError.serviceUnavailable }
            try checkState()
            if let fields = response.allHeaderFields as? [String: String] {
                credentials.accept(HTTPCookie.cookies(withResponseHeaderFields: fields, for: url), generation: generation)
            }
            if response.statusCode == 401 { throw Failure.unauthorized }
            if response.statusCode == 403 { throw CampusError.forbidden }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                // A business POST is never replayed into an authentication route.
                guard authentication, request.httpMethod == "GET" || request.httpMethod == nil,
                      let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL,
                      let trusted = Self.trustedURL(next) else { throw CampusError.authentication }
                request.url = trusted
                continue
            }
            guard (200..<300).contains(response.statusCode) else { throw CampusError.http(response.statusCode) }
            return (data, response)
        }
        throw CampusError.authentication
    }

    private func checkState() throws {
        try Task.checkCancellation()
        guard credentials.generation == generation else { throw CancellationError() }
    }

    private static func trustedURL(_ url: URL) -> URL? {
        guard ["ehall.ccsut.cn", "auth.ccsut.cn"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }
}
