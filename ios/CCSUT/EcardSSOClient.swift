import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol EcardSSOCredentials: Sendable {
    var generation: UInt64 { get }
    func cookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie]
    func accept(_ cookies: [HTTPCookie], generation: UInt64)
}

protocol EcardSSOTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum EcardSSOError: LocalizedError, Sendable, Equatable {
    case requiresInteraction
    case identityMismatch
    case invalidResponse
    case serviceUnavailable
    case untrustedRedirect

    var errorDescription: String? {
        switch self {
        case .requiresInteraction:
            return "学校统一认证需要人工完成，请继续使用学校认证页面。"
        case .identityMismatch:
            return "当前一卡通账号已切换，认证结果已丢弃。"
        case .invalidResponse:
            return "学校认证返回的数据无效。"
        case .serviceUnavailable:
            return "学校认证服务暂时不可用。"
        case .untrustedRedirect:
            return "学校认证跳转目标未获允许。"
        }
    }
}

/// Memory-only diagnostics. Never retain a request URL or the underlying error text.
struct EcardSSODiagnostic: Error, Sendable, Equatable {
    enum Stage: String, Sendable {
        case starting, portal, cas, gatewayConfiguration, gatewayAuthentication, gatewayVerification
        case ticketExchange, paymentToken
    }
    let stage: Stage
    let reason: EcardSSOError
}

private final class EcardSSONoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class EcardSSOURLTransport: EcardSSOTransport, @unchecked Sendable {
    private let session: URLSession

    init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = max(1, timeout)
        configuration.timeoutIntervalForResource = max(1, timeout)
        session = URLSession(configuration: configuration,
                             delegate: EcardSSONoRedirectDelegate(),
                             delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw EcardSSOError.serviceUnavailable }
        return (data, response)
    }
}

actor EcardSSOClient {
    private(set) var lastFailure: EcardSSODiagnostic?
    private var diagnosticStage: EcardSSODiagnostic.Stage = .starting
    private static let ecardHost = "ecard.ccsut.cn"
    private static let ztsHost = "zts.ccsut.cn"
    private static let authHost = "auth.ccsut.cn"
    private static let transitTarget = "https://ecard.ccsut.cn/plat?name=loginTransit"
    // Public deployment identifiers from the observed ecard redirect configuration.
    private static let ecardSDPAppCode = "da7ce743-45f0-46d0-9b9e-a3afa4f9b2bb"
    private static let ecardUnitID = "59f83d72-4fef-48c4-8859-44f786e145e6"

    private let account: String
    private let credentials: any EcardSSOCredentials
    private let transport: any EcardSSOTransport
    private let timeout: TimeInterval
    private let tokenAuthorization: String?
    private let feeItemAuthorization: String?

    init(
        account: String,
        credentials: any EcardSSOCredentials,
        transport: any EcardSSOTransport = EcardSSOURLTransport(),
        timeout: TimeInterval = 30,
        tokenAuthorization: String? = nil,
        feeItemAuthorization: String? = nil
    ) {
        self.account = account
        self.credentials = credentials
        self.transport = transport
        self.timeout = timeout
        self.tokenAuthorization = tokenAuthorization
        self.feeItemAuthorization = feeItemAuthorization
    }

    func fetchPaymentToken() async throws -> String {
        lastFailure = nil
        diagnosticStage = .starting
        do {
            return try await performAuthentication()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastFailure = EcardSSODiagnostic(stage: diagnosticStage,
                                            reason: error as? EcardSSOError ?? .serviceUnavailable)
            throw error
        }
    }

    private func performAuthentication() async throws -> String {
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EcardSSOError.identityMismatch
        }
        let generation = credentials.generation
        let deadline = Date().addingTimeInterval(max(0, timeout))
        let flow = FlowState()
        try check(generation)

        let entry = try Self.makeEntryURL()
        let initial = try await getFollowing(entry, generation: generation, deadline: deadline, flow: flow)
        if let ticket = initial.transitTicket {
            return try await exchangeTransitTicket(ticket, generation: generation, deadline: deadline, flow: flow)
        }

        guard let verifyURL = flow.verificationURL else { throw EcardSSOError.requiresInteraction }
        let configURL = try Self.authConfigURL()
        let configResponse = try await getFollowing(configURL, generation: generation, deadline: deadline, flow: flow)
        guard (200..<300).contains(configResponse.response.statusCode) else {
            throw EcardSSOError.serviceUnavailable
        }
        let authConfig = try Self.parseAuthConfig(configResponse.data)

        for _ in 0..<2 {
            try check(generation)
            let loginResult = try await getFollowing(authConfig.loginURL, generation: generation,
                                                     deadline: deadline, flow: flow)
            guard loginResult.transitTicket == nil,
                  Self.isGatewayPortalResponse(loginResult.response.url),
                  (200..<300).contains(loginResult.response.statusCode) else {
                throw EcardSSOError.serviceUnavailable
            }

            let authCheck = try Self.authCheckURL()
            let checkResult = try await getFollowing(authCheck, generation: generation, deadline: deadline, flow: flow)
            guard (200..<300).contains(checkResult.response.statusCode) else {
                throw EcardSSOError.serviceUnavailable
            }
            try Self.validateAuthCheck(checkResult.data, account: account)

            let continued = try await getFollowing(verifyURL, generation: generation, deadline: deadline, flow: flow)
            if let ticket = continued.transitTicket {
                return try await exchangeTransitTicket(ticket, generation: generation, deadline: deadline, flow: flow)
            }
            if Self.isEcardGatewayAcknowledgement(continued.response.url) {
                // The gateway verify response establishes the ecard deployment, then
                // the original entry URL must be entered again to obtain its CAS ticket.
                let ecardCAS = try await getFollowing(Self.makeEntryURL(), generation: generation,
                                                     deadline: deadline, flow: flow)
                if let ticket = ecardCAS.transitTicket {
                    return try await exchangeTransitTicket(ticket, generation: generation, deadline: deadline, flow: flow)
                }
            }
            if continued.response.url?.host?.lowercased() == Self.authHost,
               continued.response.url?.path == "/backstage/cas/login" {
                throw EcardSSOError.requiresInteraction
            }
        }
        throw EcardSSOError.requiresInteraction
    }

    private func exchangeTransitTicket(
        _ ticket: String,
        generation: UInt64,
        deadline: Date,
        flow: FlowState
    ) async throws -> String {
        try check(generation)
        guard Self.isOpaque(ticket) else { throw EcardSSOError.invalidResponse }

        let tokenURL = URL(string: "https://\(Self.ecardHost)/berserker-auth/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tokenAuthorization {
            guard Self.isSafeHeaderValue(tokenAuthorization) else { throw EcardSSOError.invalidResponse }
            request.setValue(tokenAuthorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Self.formBody([
            ("username", ticket),
            ("password", ticket),
            ("grant_type", "password"),
            ("scope", "all"),
            ("loginFrom", "h5"),
            ("logintype", "sso"),
            ("device_token", "h5"),
            ("synAccessSource", "h5")
        ])
        try await attachCookies(to: &request, generation: generation, flow: flow)
        let (data, response) = try await send(request, generation: generation, deadline: deadline)
        try check(generation)
        try acceptCookies(from: response, requestURL: tokenURL, generation: generation, flow: flow)
        guard response.url == tokenURL else { throw EcardSSOError.untrustedRedirect }
        guard response.statusCode != 401 else { throw EcardSSOError.serviceUnavailable }
        guard (200..<300).contains(response.statusCode) else {
            if (300..<400).contains(response.statusCode) { throw EcardSSOError.untrustedRedirect }
            throw EcardSSOError.serviceUnavailable
        }

        let portalToken = try Self.parsePortalToken(data, account: account)
        try check(generation)

        let feeURL = URL(string: "https://\(Self.ecardHost)/charge/feeitem/toAppitem?feeitemid=408")!
        var feeRequest = URLRequest(url: feeURL)
        feeRequest.httpMethod = "GET"
        feeRequest.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
        feeRequest.setValue("bearer \(portalToken)", forHTTPHeaderField: "synjones-auth")
        if let feeItemAuthorization {
            guard Self.isSafeHeaderValue(feeItemAuthorization) else { throw EcardSSOError.invalidResponse }
            feeRequest.setValue(feeItemAuthorization, forHTTPHeaderField: "Authorization")
        }
        try await attachCookies(to: &feeRequest, generation: generation, flow: flow)
        let (_, feeResponse) = try await send(feeRequest, generation: generation, deadline: deadline)
        try check(generation)
        try acceptCookies(from: feeResponse, requestURL: feeURL, generation: generation, flow: flow)
        guard feeResponse.url == feeURL else { throw EcardSSOError.untrustedRedirect }
        guard feeResponse.statusCode != 401 else { throw EcardSSOError.serviceUnavailable }
        guard (300..<400).contains(feeResponse.statusCode),
              let location = feeResponse.value(forHTTPHeaderField: "Location") else {
            throw EcardSSOError.serviceUnavailable
        }
        let destination = try Self.resolve(location, relativeTo: feeURL)
        guard Self.isAllowedOrigin(destination), destination.host?.lowercased() == Self.ecardHost,
              destination.path == "/charge-app" || destination.path == "/charge-app/" else {
            throw EcardSSOError.untrustedRedirect
        }
        let jwt = try Self.paymentJWT(from: destination, account: account)
        try check(generation)
        try commitCookies(flow, generation: generation)
        return jwt
    }

    private func getFollowing(
        _ startURL: URL,
        generation: UInt64,
        deadline: Date,
        flow: FlowState
    ) async throws -> FollowResult {
        var current = startURL
        var seen = Set<String>()

        for _ in 0..<16 {
            try check(generation)
            guard seen.insert(current.absoluteString).inserted else {
                throw EcardSSOError.serviceUnavailable
            }
            if let ticket = try Self.transitTicket(from: current) {
                return FollowResult(data: Data(), response: Self.syntheticResponse(url: current, status: 302),
                                    transitTicket: ticket)
            }
            try Self.validateURL(current)
            if current.host?.lowercased() == Self.ztsHost, current.path == "/controller/v1/public/verify" {
                flow.verificationURL = current
            }

            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.setValue("application/json, text/html;q=0.9", forHTTPHeaderField: "Accept")
            try await attachCookies(to: &request, generation: generation, flow: flow)
            let (data, response) = try await send(request, generation: generation, deadline: deadline)
            try check(generation)
            guard response.url == current else { throw EcardSSOError.untrustedRedirect }
            try acceptCookies(from: response, requestURL: current, generation: generation, flow: flow)

            if (300..<400).contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location") else {
                    throw EcardSSOError.invalidResponse
                }
                let destination = try Self.resolve(location, relativeTo: current)
                if let ticket = try Self.transitTicket(from: destination) {
                    return FollowResult(data: data, response: response, transitTicket: ticket)
                }
                try Self.validateRedirect(from: current, to: destination)
                current = destination
                continue
            }

            guard response.statusCode != 401 else { throw EcardSSOError.serviceUnavailable }
            guard (200..<300).contains(response.statusCode) else { throw EcardSSOError.serviceUnavailable }
            if current.host?.lowercased() == Self.authHost && current.path == "/backstage/cas/login" {
                throw EcardSSOError.requiresInteraction
            }
            if current.host?.lowercased() == Self.ztsHost && current.path == "/passport/v1/public/casLogin",
               Self.isHTML(data, response: response) {
                throw EcardSSOError.requiresInteraction
            }
            if current.host?.lowercased() == Self.ecardHost,
               (current.path == "/plat" || current.path == "/plat/"
                || current.path == "/berserker-auth/cas/login/wisedu"
                    && !Self.isEcardGatewayAcknowledgement(current)) {
                throw EcardSSOError.requiresInteraction
            }
            return FollowResult(data: data, response: response, transitTicket: nil)
        }
        throw EcardSSOError.serviceUnavailable
    }

    private func send(
        _ request: URLRequest,
        generation: UInt64,
        deadline: Date
    ) async throws -> (Data, HTTPURLResponse) {
        diagnosticStage = Self.diagnosticStage(for: request.url)
        try check(generation)
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw EcardSSOError.serviceUnavailable }
        let transport = self.transport
        do {
            return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                group.addTask { try await transport.data(for: request) }
                group.addTask {
                    try await Task.sleep(for: .seconds(remaining))
                    throw TimeoutSignal()
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw EcardSSOError.serviceUnavailable }
                try Task.checkCancellation()
                return result
            }
        } catch is TimeoutSignal {
            throw EcardSSOError.serviceUnavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as EcardSSOError {
            throw error
        } catch {
            throw EcardSSOError.serviceUnavailable
        }
    }

    private static func diagnosticStage(for url: URL?) -> EcardSSODiagnostic.Stage {
        guard let url else { return .starting }
        switch url.host?.lowercased() {
        case authHost: return .cas
        case ztsHost:
            switch url.path {
            case "/passport/v1/public/authConfig": return .gatewayConfiguration
            case "/controller/v1/public/verify", "/passport/v1/auth/authCheck": return .gatewayVerification
            default: return .gatewayAuthentication
            }
        case ecardHost:
            switch url.path {
            case "/berserker-auth/oauth/token": return .ticketExchange
            case "/charge/feeitem/toAppitem": return .paymentToken
            default: return .portal
            }
        default: return .starting
        }
    }

    private func attachCookies(to request: inout URLRequest, generation: UInt64, flow: FlowState) async throws {
        try check(generation)
        guard let url = request.url else { throw EcardSSOError.invalidResponse }
        let supplied = try credentials.cookies(for: url, expectedGeneration: generation)
        try check(generation)
        // Preserve identity until replacements/deletions have been applied.
        // A Cookie header alone cannot distinguish same-name scopes.
        var merged: [CookieKey: HTTPCookie] = [:]
        for cookie in supplied {
            merged[CookieKey(name: cookie.name, domain: Self.normalizedDomain(cookie.domain), path: cookie.path)] = cookie
        }
        for (key, cookie) in flow.cookies {
            if Self.isExpired(cookie) { merged.removeValue(forKey: key) }
            else { merged[key] = cookie }
        }
        var values: [String: CookieCandidate] = [:]
        for cookie in merged.values where Self.cookieApplies(cookie, to: url) {
            guard Self.isCookieName(cookie.name), Self.isCookieValue(cookie.value) else {
                throw EcardSSOError.invalidResponse
            }
            let candidate = CookieCandidate(value: cookie.value, path: cookie.path, domain: cookie.domain.lowercased())
            if let existing = values[cookie.name], !Self.shouldPrefer(candidate, over: existing) { continue }
            values[cookie.name] = candidate
        }
        if !values.isEmpty {
            request.setValue(values.keys.sorted().map { "\($0)=\(values[$0]!.value)" }.joined(separator: "; "),
                             forHTTPHeaderField: "Cookie")
        }
    }

    private func acceptCookies(
        from response: HTTPURLResponse,
        requestURL: URL,
        generation: UInt64,
        flow: FlowState
    ) throws {
        try check(generation)
        var field: (String, String)?
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            field = (String(describing: key), String(describing: value))
            break
        }
        guard let field else { return }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: [field.0: field.1], for: requestURL)
        let host = requestURL.host?.lowercased() ?? ""
        for cookie in parsed {
            let domain = Self.normalizedDomain(cookie.domain)
            guard Self.isAllowedCookieDomain(domain),
                  host == domain || host.hasSuffix("." + domain) else {
                throw EcardSSOError.untrustedRedirect
            }
        }
        for cookie in parsed {
            let key = CookieKey(name: cookie.name, domain: Self.normalizedDomain(cookie.domain), path: cookie.path)
            // Keep expired cookies as deletion tombstones: they suppress matching identities
            // from persistent cookies during this flow and delete them on commit.
            flow.cookies[key] = cookie
        }
        try check(generation)
    }

    private func commitCookies(_ flow: FlowState, generation: UInt64) throws {
        try check(generation)
        guard !flow.cookies.isEmpty else { return }
        let changes = flow.cookies.values.sorted {
            let lhs = CookieKey(name: $0.name, domain: Self.normalizedDomain($0.domain), path: $0.path)
            let rhs = CookieKey(name: $1.name, domain: Self.normalizedDomain($1.domain), path: $1.path)
            if lhs.domain != rhs.domain { return lhs.domain < rhs.domain }
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.name < rhs.name
        }
        try check(generation)
        credentials.accept(changes, generation: generation)
        try check(generation)
    }

    private func check(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard credentials.generation == generation else { throw EcardSSOError.identityMismatch }
    }

    private struct FollowResult {
        let data: Data
        let response: HTTPURLResponse
        let transitTicket: String?
    }

    private struct AuthConfig {
        let loginURL: URL
    }

    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String
    }

    private struct CookieCandidate {
        let value: String
        let path: String
        let domain: String
    }

    private final class FlowState: @unchecked Sendable {
        var verificationURL: URL?
        var cookies: [CookieKey: HTTPCookie] = [:]
    }

    private struct TimeoutSignal: Error {}

    private static func makeEntryURL() throws -> URL {
        var components = URLComponents(string: "https://\(ecardHost)/berserker-auth/cas/login/wisedu")!
        components.queryItems = [URLQueryItem(name: "targetUrl", value: transitTarget)]
        guard let url = components.url else { throw EcardSSOError.invalidResponse }
        return url
    }

    private static func authConfigURL() throws -> URL {
        var components = URLComponents(string: "https://\(ztsHost)/passport/v1/public/authConfig")!
        components.queryItems = [
            URLQueryItem(name: "clientType", value: "SDPBrowserClient"),
            URLQueryItem(name: "platform", value: "iOS"),
            URLQueryItem(name: "lang", value: "zh-CN"),
            URLQueryItem(name: "needTicket", value: "1")
        ]
        guard let url = components.url else { throw EcardSSOError.invalidResponse }
        return url
    }

    private static func authCheckURL() throws -> URL {
        var components = URLComponents(string: "https://\(ztsHost)/passport/v1/auth/authCheck")!
        components.queryItems = [
            URLQueryItem(name: "clientType", value: "SDPBrowserClient"),
            URLQueryItem(name: "platform", value: "iOS"),
            URLQueryItem(name: "lang", value: "zh-CN")
        ]
        guard let url = components.url else { throw EcardSSOError.invalidResponse }
        return url
    }

    private static func parseAuthConfig(_ data: Data) throws -> AuthConfig {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["code"]) == 0 else {
            throw EcardSSOError.invalidResponse
        }
        let body = root["data"] as? [String: Any] ?? root
        guard let servers = body["authServerInfoList"] as? [[String: Any]],
              let cas = servers.first(where: { ($0["authType"] as? String) == "auth/cas" }),
              let loginDomain = cas["loginDomain"] as? String, isOpaque(loginDomain),
              let loginText = cas["loginUrl"] as? String,
              let loginURL = URL(string: loginText, relativeTo: URL(string: "https://\(ztsHost)")!)?.absoluteURL else {
            throw EcardSSOError.invalidResponse
        }
        try validateURL(loginURL)
        guard loginURL.host?.lowercased() == ztsHost,
              loginURL.path == "/passport/v1/public/casLogin",
              query(loginURL)["sfDomain"] == loginDomain else {
            throw EcardSSOError.untrustedRedirect
        }
        return AuthConfig(loginURL: loginURL)
    }

    private static func validateAuthCheck(_ data: Data, account: String) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["code"]) == 0 else {
            throw EcardSSOError.serviceUnavailable
        }
        guard let body = root["data"] as? [String: Any],
              let sidTicket = body["sidTicket"] as? String, isOpaque(sidTicket),
              let userName = body["userName"] as? String, isOpaque(userName) else {
            throw EcardSSOError.requiresInteraction
        }
        guard userName == account else { throw EcardSSOError.identityMismatch }
    }

    private static func isGatewayPortalResponse(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased() == ztsHost else { return false }
        return url.path == "/passport/v1/auth/cas" || url.path == "/portal/shortcut.html"
            || url.path == "/portal" || url.path == "/portal/" || url.path == "/"
    }

    private static func isEcardGatewayAcknowledgement(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased() == ecardHost,
              url.path == "/berserker-auth/cas/login/wisedu" else { return false }
        let items = query(url)
        return items["sdpAppCode"] == ecardSDPAppCode && items["unitId"] == ecardUnitID
            && items["targetUrl"] == nil && items["ticket"] == nil
    }

    private static func parsePortalToken(_ data: Data, account: String) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EcardSSOError.invalidResponse
        }
        let body = root["data"] as? [String: Any] ?? root
        guard let token = body["access_token"] as? String, !token.isEmpty,
              token.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }),
              (body["token_type"] as? String)?.lowercased() == "bearer",
              let expires = number(body["expires_in"]), expires > 0,
              let sno = body["sno"] as? String else {
            throw EcardSSOError.invalidResponse
        }
        guard sno == account else { throw EcardSSOError.identityMismatch }
        return token
    }

    private static func paymentJWT(from url: URL, account: String) throws -> String {
        guard hasOnlyQueryNames(url, ["name", "id", "token"]) else { throw EcardSSOError.invalidResponse }
        let items = query(url)
        guard items["name"] == "pays", items["id"] == "408",
              let token = items["token"], !token.isEmpty else {
            throw EcardSSOError.invalidResponse
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty,
              let payload = base64URLDecode(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let expiry = number(claims["exp"]) else {
            throw EcardSSOError.invalidResponse
        }
        guard let sno = claims["sno"] as? String else { throw EcardSSOError.invalidResponse }
        guard sno == account else { throw EcardSSOError.identityMismatch }
        guard Date(timeIntervalSince1970: expiry).timeIntervalSinceNow > 60 else {
            throw EcardSSOError.invalidResponse
        }
        return token
    }

    private static func transitTicket(from url: URL) throws -> String? {
        guard isAllowedOrigin(url), url.host?.lowercased() == ecardHost,
              url.path == "/plat" || url.path == "/plat/" else { return nil }
        guard hasOnlyQueryNames(url, ["name", "ticket", "targetUrl"]) else {
            throw EcardSSOError.untrustedRedirect
        }
        let items = query(url)
        guard items["name"] == "loginTransit" else { return nil }
        guard items["targetUrl"] == transitTarget,
              let ticket = items["ticket"], isOpaque(ticket) else {
            throw EcardSSOError.untrustedRedirect
        }
        return ticket
    }

    private static func validateURL(_ url: URL) throws {
        guard isAllowedOrigin(url),
              let host = url.host?.lowercased(),
              allowedPaths(for: host).contains(url.path),
              hasUniqueQueryItems(url) else {
            throw EcardSSOError.untrustedRedirect
        }
        let items = query(url)
        switch (host, url.path) {
        case (ecardHost, "/berserker-auth/cas/login/wisedu"):
            if let target = items["targetUrl"] {
                guard target == transitTarget,
                      (items["ticket"] == nil || isOpaque(items["ticket"]!)),
                      hasOnlyQueryNames(url, ["targetUrl", "ticket"]) else {
                    throw EcardSSOError.untrustedRedirect
                }
            } else if let ticket = items["ticket"] {
                guard isOpaque(ticket),
                      items["sdpAppCode"] == nil && items["unitId"] == nil
                        || items["sdpAppCode"] == ecardSDPAppCode && items["unitId"] == ecardUnitID,
                      hasOnlyQueryNames(url, ["ticket", "sdpAppCode", "unitId"]) else {
                    throw EcardSSOError.untrustedRedirect
                }
            } else {
                guard items["sdpAppCode"] == ecardSDPAppCode, items["unitId"] == ecardUnitID,
                      hasOnlyQueryNames(url, ["sdpAppCode", "unitId"]) else {
                    throw EcardSSOError.untrustedRedirect
                }
            }
        case (ecardHost, "/plat"), (ecardHost, "/plat/"):
            guard items["name"] == "loginTransit", items["targetUrl"] == transitTarget,
                  let ticket = items["ticket"], isOpaque(ticket),
                  hasOnlyQueryNames(url, ["name", "ticket", "targetUrl"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ecardHost, "/charge/feeitem/toAppitem"):
            guard items["feeitemid"] == "408", hasOnlyQueryNames(url, ["feeitemid"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ecardHost, "/charge-app"), (ecardHost, "/charge-app/"):
            guard items["name"] == "pays", items["id"] == "408", items["token"] != nil,
                  hasOnlyQueryNames(url, ["name", "id", "token"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ztsHost, "/controller/v1/public/verify"):
            guard let ticket = items["t"], isOpaque(ticket), hasOnlyQueryNames(url, ["t"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ztsHost, "/passport/v1/public/authConfig"):
            guard items["clientType"] == "SDPBrowserClient", items["platform"] == "iOS",
                  items["lang"] == "zh-CN", items["needTicket"] == "1",
                  hasOnlyQueryNames(url, ["clientType", "platform", "lang", "needTicket"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ztsHost, "/passport/v1/public/casLogin"):
            guard let domain = items["sfDomain"], isOpaque(domain), hasOnlyQueryNames(url, ["sfDomain"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ztsHost, "/passport/v1/auth/cas"):
            guard hasOnlyQueryNames(url, ["ticket"]) else { throw EcardSSOError.untrustedRedirect }
            if let ticket = items["ticket"], !isOpaque(ticket) { throw EcardSSOError.untrustedRedirect }
        case (ztsHost, "/passport/v1/auth/authCheck"):
            guard items["clientType"] == "SDPBrowserClient", items["platform"] == "iOS",
                  items["lang"] == "zh-CN", hasOnlyQueryNames(url, ["clientType", "platform", "lang"]) else {
                throw EcardSSOError.untrustedRedirect
            }
        case (ztsHost, "/portal/shortcut.html"), (ztsHost, "/portal"), (ztsHost, "/portal/"), (ztsHost, "/"):
            guard hasOnlyQueryNames(url, []) else { throw EcardSSOError.untrustedRedirect }
        case (authHost, "/backstage/cas/login"):
            guard hasOnlyQueryNames(url, ["service"]) else { throw EcardSSOError.untrustedRedirect }
        default:
            break
        }
    }

    private static func validateRedirect(
        from source: URL,
        to destination: URL
    ) throws {
        try validateURL(destination)
        let sourceHost = source.host?.lowercased() ?? ""
        let destinationHost = destination.host?.lowercased() ?? ""
        let path = destination.path
        if destinationHost == authHost && path == "/backstage/cas/login" {
            let services = URLComponents(url: destination, resolvingAgainstBaseURL: false)?.queryItems?
                .filter { $0.name == "service" } ?? []
            guard services.count == 1, let serviceText = services[0].value,
                  let service = URL(string: serviceText), isAllowedOrigin(service),
                  let serviceHost = service.host?.lowercased(),
                  (serviceHost == ztsHost && service.path == "/passport/v1/auth/cas"
                   || serviceHost == ecardHost && service.path == "/berserker-auth/cas/login/wisedu") else {
                throw EcardSSOError.untrustedRedirect
            }
            try validateURL(service)
            return
        }
        if sourceHost == ztsHost && source.path == "/passport/v1/public/casLogin" {
            guard destinationHost == authHost && path == "/backstage/cas/login" else {
                throw EcardSSOError.untrustedRedirect
            }
            return
        }
        if sourceHost == authHost && source.path == "/backstage/cas/login" {
            guard destinationHost == ztsHost && destination.path == "/passport/v1/auth/cas"
                    || destinationHost == ecardHost && destination.path == "/berserker-auth/cas/login/wisedu" else {
                throw EcardSSOError.untrustedRedirect
            }
            return
        }
        if sourceHost == ztsHost && source.path == "/controller/v1/public/verify" {
            guard destinationHost == ztsHost && destination.path == "/portal/shortcut.html"
                    || destinationHost == ecardHost && destination.path == "/berserker-auth/cas/login/wisedu" else {
                throw EcardSSOError.untrustedRedirect
            }
            return
        }
        if sourceHost == ecardHost && source.path == "/berserker-auth/cas/login/wisedu" {
            guard destinationHost == ztsHost && destination.path == "/controller/v1/public/verify"
                    || destinationHost == authHost && destination.path == "/backstage/cas/login"
                    || destinationHost == ecardHost && destination.path == source.path
                    || destinationHost == ecardHost && destination.path == "/plat" || destination.path == "/plat/" else {
                throw EcardSSOError.untrustedRedirect
            }
            return
        }
        if sourceHost == ztsHost && source.path == "/passport/v1/auth/cas" {
            guard destinationHost == ecardHost && destination.path == "/berserker-auth/cas/login/wisedu"
                    || destinationHost == ztsHost && ["/portal/shortcut.html", "/portal", "/portal/", "/"].contains(destination.path) else {
                throw EcardSSOError.untrustedRedirect
            }
            return
        }
        if destinationHost == ecardHost && destination.path == "/plat" || destination.path == "/plat/" {
            return
        }
        if sourceHost == ecardHost && source.path == "/berserker-auth/cas/login/wisedu"
            && destinationHost == ecardHost && destination.path == "/berserker-auth/cas/login/wisedu" {
            return
        }
        throw EcardSSOError.untrustedRedirect
    }

    private static func allowedPaths(for host: String) -> Set<String> {
        switch host {
        case ecardHost:
            return ["/berserker-auth/cas/login/wisedu", "/berserker-auth/oauth/token", "/plat", "/plat/",
                    "/charge/feeitem/toAppitem", "/charge-app", "/charge-app/"]
        case ztsHost:
            return ["/", "/portal", "/portal/", "/controller/v1/public/verify", "/portal/shortcut.html", "/passport/v1/public/authConfig",
                    "/passport/v1/public/casLogin", "/passport/v1/auth/cas", "/passport/v1/auth/authCheck"]
        case authHost:
            return ["/backstage/cas/login"]
        default:
            return []
        }
    }

    private static func isAllowedOrigin(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              [ecardHost, ztsHost, authHost].contains(host),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              url.fragment == nil else { return false }
        return true
    }

    private static func resolve(_ location: String, relativeTo base: URL) throws -> URL {
        guard !location.contains("\r"), !location.contains("\n"),
              let destination = URL(string: location, relativeTo: base)?.absoluteURL,
              isAllowedOrigin(destination) else {
            throw EcardSSOError.untrustedRedirect
        }
        return destination
    }

    private static func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private static func hasUniqueQueryItems(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Set(items.map(\.name)).count == items.count
    }

    private static func hasOnlyQueryNames(_ url: URL, _ allowed: Set<String>) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Set(items.map(\.name)).count == items.count && items.allSatisfy { allowed.contains($0.name) }
    }

    private static func isHTML(_ data: Data, response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") == true {
            return true
        }
        let prefix = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html")
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func isOpaque(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4_096
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func formBody(_ fields: [(String, String)]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        // A literal '+' decodes as a space in x-www-form-urlencoded bodies.
        return components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 { base64 += String(repeating: "=", count: padding) }
        return Data(base64Encoded: base64)
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain.hasPrefix(".") ? String(domain.dropFirst()).lowercased() : domain.lowercased()
    }

    private static func isAllowedCookieDomain(_ domain: String) -> Bool {
        domain == "ccsut.cn" || domain.hasSuffix(".ccsut.cn")
    }

    private static func cookieDomainPathApplies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), url.scheme?.lowercased() == "https" else { return false }
        let domain = normalizedDomain(cookie.domain)
        guard isAllowedCookieDomain(domain), host == domain || host.hasSuffix("." + domain) else { return false }
        let path = cookie.path.isEmpty ? "/" : cookie.path
        guard url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/") else { return false }
        return !cookie.isSecure || url.scheme?.lowercased() == "https"
    }

    private static func cookieApplies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        cookieDomainPathApplies(cookie, to: url) && !isExpired(cookie)
    }

    private static func isExpired(_ cookie: HTTPCookie) -> Bool {
        if let expires = cookie.expiresDate { return expires <= Date() }
        return false
    }

    private static func shouldPrefer(_ candidate: CookieCandidate, over existing: CookieCandidate) -> Bool {
        let candidatePath = candidate.path.isEmpty ? "/" : candidate.path
        let existingPath = existing.path.isEmpty ? "/" : existing.path
        if candidatePath.count != existingPath.count { return candidatePath.count > existingPath.count }
        let candidateDomain = normalizedDomain(candidate.domain)
        let existingDomain = normalizedDomain(existing.domain)
        if candidateDomain == existingDomain,
           candidate.domain.hasPrefix(".") != existing.domain.hasPrefix(".") {
            return !candidate.domain.hasPrefix(".")
        }
        if candidateDomain.count != existingDomain.count { return candidateDomain.count > existingDomain.count }
        if candidateDomain != existingDomain { return candidateDomain < existingDomain }
        if candidatePath != existingPath { return candidatePath < existingPath }
        return candidate.value < existing.value
    }

    private static func isCookieName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A) || "!#$%&'*+-.^_`|~".utf8.contains(byte)
        }
    }

    private static func isCookieValue(_ value: String) -> Bool {
        value.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7e && $0 != 0x3b && $0 != 0x2c }
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7e }
    }

    private static func syntheticResponse(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
    }
}
