import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol CampusSessionCredentials: Sendable {
    var generation: UInt64 { get }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String?
    func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie]
    func accept(_ cookies: [HTTPCookie], generation: UInt64)
}

protocol CampusTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// An official browser has its own store. Never import a different CAS identity.
struct CampusOfficialCookieHandoff: Sendable {
    private struct Identity: Decodable { let errcode: Int; let account: String }
    let account: String
    let credentials: any CampusSessionCredentials
    private let generation: UInt64

    init(account: String, credentials: any CampusSessionCredentials) {
        self.account = account
        self.credentials = credentials
        generation = credentials.generation
    }

    func accept(identity data: Data, cookies: [HTTPCookie]) throws {
        guard credentials.generation == generation else { throw CancellationError() }
        guard let identity = try? JSONDecoder().decode(Identity.self, from: data), identity.errcode == 2000 else {
            throw CampusError.authentication
        }
        guard !account.isEmpty, identity.account == account else { throw CampusError.identityMismatch }
        // Keep the App's CAS identity authoritative, even if an official login changes its own TGC.
        credentials.accept(cookies.filter { ["ehall.ccsut.cn", ".ehall.ccsut.cn"].contains($0.domain) }, generation: generation)
    }
}

enum CampusOfficialNavigationDecision: Equatable {
    case allow
    case upgrade(URL)
    case blocked(reportFailure: Bool)
}

/// The browser is restricted to the school's official portal and CAS host.
/// Kept Foundation-only so the boundary can be checked without WebKit.
enum CampusOfficialNavigationPolicy {
    static func decision(for url: URL?, targetIsMainFrame: Bool?) -> CampusOfficialNavigationDecision {
        guard let targetIsMainFrame else { return .blocked(reportFailure: false) }
        guard let url else { return .blocked(reportFailure: false) }
        if url.absoluteString == "about:blank" { return .allow }
        guard ["ehall.ccsut.cn", "auth.ccsut.cn"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return .blocked(reportFailure: targetIsMainFrame) }
        if url.scheme == "http" {
            guard targetIsMainFrame, url.port == nil || url.port == 80 else {
                return .blocked(reportFailure: targetIsMainFrame)
            }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.port = nil
            guard let upgraded = components?.url else { return .blocked(reportFailure: targetIsMainFrame) }
            return .upgrade(upgraded)
        }
        guard url.port == nil || url.port == 443 else { return .blocked(reportFailure: targetIsMainFrame) }
        return url.scheme == "https" ? .allow : .blocked(reportFailure: targetIsMainFrame)
    }
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

enum CampusAuthenticationDiagnosticStage: String, Sendable {
    case idle, initialValidation, casRedirect, renewedValidation, authenticated
}

enum CampusAuthenticationDiagnosticOutcome: String, Sendable {
    case none, inProgress, accepted, rejected, failed
}

/// Fixed, in-memory state for diagnosing the native CAS flow. It contains no
/// account, URL, response, token, or cookie material.
struct CampusAuthenticationDiagnostic: Equatable, Sendable {
    let stage: CampusAuthenticationDiagnosticStage
    let outcome: CampusAuthenticationDiagnosticOutcome
    let casCookiesChangedDuringAttempt: Bool
}

protocol CampusReading: Sendable {
    func leaveRecords(page: Int, size: Int) async throws -> CampusLeavePage
    func travelRecords(kind: CampusTravelKind) async throws -> [CampusTravelRecord]
}

actor CampusClient: CampusReading {
    enum Subsystem: Hashable { case leave, travel }
    enum Failure: Error { case unauthorized }
    struct Identity: Decodable, Sendable {
        struct Token: Decodable, Sendable {
            let access_token: String
            let token_type: String
        }
        let errcode: Int
        let account: String
        let userId: String
        let realName: String?
        let data: Token?

        // Kept only in this generation-bound client; never persisted or logged.
        var authorization: String? {
            guard let data, data.token_type.lowercased() == "bearer", !data.access_token.isEmpty,
                  data.access_token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { return nil }
            return "Bearer " + data.access_token
        }
    }

    static let leavePage = URL(string: "https://ehall.ccsut.cn/backstage/leaveadmin/page/mobile/#/leaveList")!
    static let leaveForm = URL(string: "https://ehall.ccsut.cn/backstage/leaveadmin/page/mobile/#/leaveForm")!
    let account: String
    let credentials: any CampusSessionCredentials
    let transport: any CampusTransport
    let generation: UInt64
    private(set) var authenticationDiagnostic = CampusAuthenticationDiagnostic(
        stage: .idle, outcome: .none, casCookiesChangedDuringAttempt: false
    )
    private var observedCASCookieRotation = false
    var formAttemptIDs: Set<UUID> = []
    private var identities: [Subsystem: Identity] = [:]

    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
        init(_ cookie: HTTPCookie) {
            name = cookie.name
            let domain = cookie.domain.lowercased()
            self.domain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            path = cookie.path
        }
    }

    /// Local to one identity attempt, including its initial validation and CAS
    /// hops. Never actor-wide: other subsystems may authenticate while we await.
    private final class AuthenticationCookies {
        var updates: [CookieKey: HTTPCookie] = [:]

        func stage(_ incoming: [HTTPCookie]) {
            for cookie in incoming {
                var staged = cookie
                // Foundation implementations may retain Max-Age without deriving
                // expiresDate for version-0 cookies. Preserve deletion/expiry for
                // both the overlay and CookieJar's eventual expiresDate upsert.
                if var properties = cookie.properties, let rawAge = properties[.maximumAge],
                   let age = TimeInterval(String(describing: rawAge)), age.isFinite {
                    properties.removeValue(forKey: .maximumAge)
                    properties[.expires] = age <= 0 ? Date.distantPast : Date().addingTimeInterval(age)
                    staged = HTTPCookie(properties: properties) ?? cookie
                }
                updates[CookieKey(staged)] = staged
            }
        }

        func header(for url: URL, base: [HTTPCookie]) -> String? {
            var merged: [CookieKey: HTTPCookie] = [:]
            for cookie in base { merged[CookieKey(cookie)] = cookie }
            // Keep expired replacements as tombstones until the final commit.
            for (key, cookie) in updates { merged[key] = cookie }
            let host = url.host?.lowercased() ?? ""
            let path = url.path.isEmpty ? "/" : url.path
            let matched = merged.values.filter { cookie in
                let domain = CookieKey(cookie).domain
                let domainMatches = host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("." + domain))
                let pathMatches = path == cookie.path || path.hasPrefix(cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/")
                return domainMatches && pathMatches && (!cookie.isSecure || url.scheme == "https") &&
                    (cookie.expiresDate ?? .distantFuture) > Date()
            }.sorted {
                if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.domain < $1.domain
            }
            return matched.isEmpty ? nil : matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

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

    /// Return the name attached to this campus identity without loading a form
    /// or issuing a business request. The result is bound to the validated
    /// account and the Cookie generation that authenticated it.
    func authenticatedDisplayName(expectedAccount: String,
                                  expectedGeneration: UInt64) async throws -> CampusStudentDisplayName? {
        try checkState()
        guard account == expectedAccount, generation == expectedGeneration else {
            throw CampusError.identityMismatch
        }
        let identity = try await identity(for: .leave, callback: Self.leavePage, force: false)
        try checkState()
        guard identity.account == expectedAccount, generation == expectedGeneration else {
            throw CampusError.identityMismatch
        }
        guard let rawName = identity.realName else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return CampusStudentDisplayName(account: identity.account, generation: generation, value: name)
    }

    private func query(_ subsystem: Subsystem, callback: URL, path: String,
                       body: (String) -> [String: Any]) async throws -> Data {
        for attempt in 0...1 {
            let identity = try await identity(for: subsystem, callback: callback, force: attempt == 1)
            var request = request(path)
            request.httpMethod = "POST"
            request.setValue(identity.authorization, forHTTPHeaderField: "Authorization")
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(callback.absoluteString, forHTTPHeaderField: "Referer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body(identity.userId))
            do { return try await sendRead(request) }
            catch Failure.unauthorized {
                identities[subsystem] = nil
                if attempt == 1 { throw CampusError.authentication }
            }
        }
        throw CampusError.authentication
    }

    func identity(for subsystem: Subsystem, callback: URL, force: Bool) async throws -> Identity {
        try checkState()
        guard !account.isEmpty else { throw CampusError.authentication }
        if !force, let cached = identities[subsystem] { return cached }
        // A business 401 has already rejected this session's bearer. The proxy
        // can still return that same token from validate_full, so bypassing only
        // our dictionary is insufficient: renew CAS before validating again.
        let initialCASCookieFingerprint = try casCookieFingerprint()
        observedCASCookieRotation = false
        if force { identities[subsystem] = nil }
        for transactionAttempt in 0...1 {
            try checkState()
            let cookies = AuthenticationCookies()
            var result: Identity?
            if !force {
                recordAuthentication(stage: .initialValidation, outcome: .inProgress)
                do {
                    result = try await validate(callback: callback, cookies: cookies)
                    recordAuthentication(stage: .initialValidation, outcome: result == nil ? .rejected : .accepted)
                } catch {
                    recordAuthentication(stage: .initialValidation, outcome: .failed)
                    throw error
                }
            }
            if result == nil {
                recordAuthentication(stage: .casRedirect, outcome: .inProgress)
                let redirect = request("/backstage/cas-proxy/app/redirect", query: [
                    URLQueryItem(name: "serverName", value: "https://ehall.ccsut.cn")
                ])
                do {
                    _ = try await send(redirect, authenticationCookies: cookies)
                    recordAuthentication(stage: .casRedirect, outcome: .accepted)
                } catch Failure.unauthorized {
                    recordAuthentication(stage: .casRedirect, outcome: .rejected)
                    throw CampusError.authentication
                } catch {
                    recordAuthentication(stage: .casRedirect, outcome: .failed)
                    throw error
                }
                recordAuthentication(stage: .renewedValidation, outcome: .inProgress)
                do {
                    result = try await validate(callback: callback, cookies: cookies)
                    recordAuthentication(stage: .renewedValidation, outcome: result == nil ? .rejected : .accepted)
                } catch {
                    recordAuthentication(stage: .renewedValidation, outcome: .failed)
                    throw error
                }
            }
            if let result {
                try checkState()
                credentials.accept(Array(cookies.updates.values), generation: generation)
                try checkState()
                identities[subsystem] = result
                recordAuthentication(stage: .authenticated, outcome: .accepted)
                return result
            }
            guard transactionAttempt == 0 else { throw CampusError.authentication }
            try checkState()
            guard try casCookieFingerprint() != initialCASCookieFingerprint else { throw CampusError.authentication }
            observedCASCookieRotation = true
            recordAuthentication(stage: .renewedValidation, outcome: .rejected)
        }
        throw CampusError.authentication
    }

    private func recordAuthentication(stage: CampusAuthenticationDiagnosticStage,
                                       outcome: CampusAuthenticationDiagnosticOutcome) {
        authenticationDiagnostic = CampusAuthenticationDiagnostic(
            stage: stage, outcome: outcome,
            casCookiesChangedDuringAttempt: observedCASCookieRotation
        )
    }

    private func casCookieFingerprint() throws -> Int {
        let url = URL(string: "https://auth.ccsut.cn/backstage/cas/login")!
        let cookies = try credentials.scopedCookies(for: url, expectedGeneration: generation).sorted {
            let left = CookieKey($0)
            let right = CookieKey($1)
            if left.domain != right.domain { return left.domain < right.domain }
            if left.name != right.name { return left.name < right.name }
            return left.path < right.path
        }
        var hasher = Hasher()
        for cookie in cookies {
            let key = CookieKey(cookie)
            hasher.combine(key.name)
            hasher.combine(key.domain)
            hasher.combine(key.path)
            hasher.combine(cookie.value)
            hasher.combine(cookie.expiresDate?.timeIntervalSince1970 ?? -1)
            hasher.combine(cookie.isSecure)
            hasher.combine(cookie.isHTTPOnly)
        }
        return hasher.finalize()
    }

    private func validate(callback: URL, cookies: AuthenticationCookies) async throws -> Identity? {
        let req = request("/backstage/cas-proxy/app/validate_full", query: [
            URLQueryItem(name: "callback", value: callback.absoluteString),
            URLQueryItem(name: "timestamp", value: String(Int64(Date().timeIntervalSince1970 * 1000)))
        ])
        let data: Data
        do { data = try await send(req, authenticationCookies: cookies).0 }
        catch Failure.unauthorized { return nil }
        guard let identity = try? JSONDecoder().decode(Identity.self, from: data),
              identity.errcode == 2000, !identity.userId.isEmpty else { return nil }
        guard identity.account == account else { throw CampusError.identityMismatch }
        guard identity.authorization != nil else { throw CampusError.invalidResponse }
        return identity
    }

    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(string: "https://ehall.ccsut.cn" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct ReadStatus: Decodable {
        let code: String?
        private enum CodingKeys: String, CodingKey { case code }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? c.decode(String.self, forKey: .code) { code = text }
            else { code = try c.decodeIfPresent(Int.self, forKey: .code).map(String.init) }
        }
    }

    /// Only read callers consume this signal with a bounded CAS recovery loop.
    /// Mutation responses must retain their existing uncertain-outcome handling.
    func sendRead(_ request: URLRequest) async throws -> Data {
        let data = try await send(request).0
        switch (try? JSONDecoder().decode(ReadStatus.self, from: data))?.code {
        case "401": throw Failure.unauthorized
        case "403": throw CampusError.forbidden
        default: return data
        }
    }

    /// Follow only the official CAS/ehall chain, with fresh Cookie matching per hop.
    func send(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(original, authenticationCookies: nil)
    }

    private func send(_ original: URLRequest, authenticationCookies: AuthenticationCookies?) async throws -> (Data, HTTPURLResponse) {
        let authentication = authenticationCookies != nil
        var request = original
        let deadline = Date().addingTimeInterval(30)
        for _ in 0..<12 {
            try checkState()
            guard let rawURL = request.url, let url = Self.trustedURL(rawURL),
                  authentication || url.host == "ehall.ccsut.cn" else { throw CampusError.authentication }
            request.url = url
            request.httpShouldHandleCookies = false
            let header: String?
            if let authenticationCookies {
                header = authenticationCookies.header(for: url, base: try credentials.scopedCookies(for: url, expectedGeneration: generation))
            } else {
                header = try credentials.header(for: url, expectedGeneration: generation)
            }
            request.setValue(header, forHTTPHeaderField: "Cookie")
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
                let incoming = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                if let authenticationCookies {
                    authenticationCookies.stage(incoming)
                } else {
                    credentials.accept(incoming, generation: generation)
                }
            }
            if response.statusCode == 401 { throw Failure.unauthorized }
            if response.statusCode == 403 { throw CampusError.forbidden }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL,
                      let trusted = Self.trustedURL(next) else { throw CampusError.authentication }
                if !authentication {
                    // Signal the read's bounded recovery loop, without following
                    // this redirect or forwarding its POST/body/bearer to CAS.
                    let casLogin = trusted.host == "auth.ccsut.cn" && trusted.path == "/backstage/cas/login"
                    let campusLogin = trusted.host == "ehall.ccsut.cn" && trusted.path == "/backstage/cas-proxy/app/redirect"
                    guard casLogin || campusLogin else { throw CampusError.authentication }
                    throw Failure.unauthorized
                }
                guard request.httpMethod == "GET" || request.httpMethod == nil else { throw CampusError.authentication }
                request.url = trusted
                continue
            }
            guard (200..<300).contains(response.statusCode) else { throw CampusError.http(response.statusCode) }
            return (data, response)
        }
        throw CampusError.authentication
    }

    func checkState() throws {
        try Task.checkCancellation()
        guard credentials.generation == generation else { throw CancellationError() }
    }

    private static func trustedURL(_ url: URL) -> URL? {
        guard ["ehall.ccsut.cn", "auth.ccsut.cn"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let isHTTP = url.scheme?.lowercased() == "http"
        guard url.port == nil || url.port == (isHTTP ? 80 : 443) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = url.host?.lowercased()
        // Official CAS completes with a redirect to a SPA route (#/leaveList,
        // #/stu-leave-list, etc.). Fragments are client-side only: validate the
        // host/authority above, then omit the fragment from the HTTP request.
        components?.fragment = nil
        if isHTTP { components?.port = nil }
        return components?.url
    }
}
