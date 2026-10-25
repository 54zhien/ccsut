import Foundation

/// Use the existing account-generation and encrypted credential lifecycle.
struct CampusCookieCredentials: CampusSessionCredentials {
    var generation: UInt64 { CookieJar.generation }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        try CookieJar.header(for: url, expectedGeneration: expectedGeneration)
    }
    func scopedCookies(for url: URL, expectedGeneration: UInt64) throws -> [HTTPCookie] {
        try CookieJar.scopedCookies(for: url, expectedGeneration: expectedGeneration)
    }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        CookieJar.upsert(cookies, generation: generation)
    }
}
