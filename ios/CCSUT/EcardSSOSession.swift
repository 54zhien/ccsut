import Foundation

/// Reuse the App's verified account and Keychain lifecycle, never a browser profile.
struct EcardCookieCredentials: EcardSSOCredentials {
    var generation: UInt64 { CookieJar.generation }
    func header(for url: URL, expectedGeneration: UInt64) throws -> String? {
        try CookieJar.header(for: url, expectedGeneration: expectedGeneration)
    }
    func accept(_ cookies: [HTTPCookie], generation: UInt64) {
        CookieJar.upsert(cookies, generation: generation)
    }
}
