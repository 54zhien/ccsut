import Foundation

/// Use the existing account-generation and encrypted credential lifecycle.
struct CampusCookieCredentials: CampusSessionCredentials {
    var generation: UInt64 { CookieJar.generation }
    func header(for url: URL) -> String? { CookieJar.header(for: url) }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        CookieJar.upsert(cookies, generation: generation)
    }
}
