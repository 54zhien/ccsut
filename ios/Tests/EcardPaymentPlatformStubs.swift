// Windows-only platform boundaries. macOS regressions compile real WebKit,
// CookieJar, bridge and URL encoding; the payment API/model are real on both.
#if !canImport(WebKit)
import Foundation
import FoundationNetworking

enum PaymentPlatformUnavailable: Error { case unexpectedPlatformCall }
final class WKHTTPCookieStore {
    func cookieSnapshot() async throws -> [HTTPCookie] { throw PaymentPlatformUnavailable.unexpectedPlatformCall }
    func set(_ cookie: HTTPCookie) async throws { throw PaymentPlatformUnavailable.unexpectedPlatformCall }
}
final class WKWebsiteDataStore { let httpCookieStore = WKHTTPCookieStore() }
final class PaymentWebConfiguration { let websiteDataStore = WKWebsiteDataStore() }
final class PaymentWebView { let configuration = PaymentWebConfiguration() }
@MainActor final class EcardTokenBridge {
    var onNeedsInteraction: (() -> Void)?
    let usesNativeCookies = true
    let webView = PaymentWebView()
    init(dataStore: WKWebsiteDataStore) {}
    static func cachedToken(forAccount: String) -> String? { nil }
    static func cachedTokenUsesNativeCookies(forAccount: String) -> Bool { true }
    static func cancelPreparation() {}
    static func clearCachedToken() {}
    func fetchToken(forAccount: String) async throws -> String { throw PaymentPlatformUnavailable.unexpectedPlatformCall }
}
enum WebStore { static let dataStore = WKWebsiteDataStore() }
enum CookieJar {
    static var generation: UInt64 { 1 }
    static func header(for: URL, expectedGeneration: UInt64) throws -> String? { throw PaymentPlatformUnavailable.unexpectedPlatformCall }
    static func upsert(_ cookies: [HTTPCookie], generation: UInt64) {}
    static func isSchoolCookie(_ cookie: HTTPCookie) -> Bool { false }
}
enum UserAgent { static let mobile = "offline-payment-tests" }
final class NoRedirect: NSObject, URLSessionTaskDelegate {}
extension String {
    var urlEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=%?#/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
#endif
