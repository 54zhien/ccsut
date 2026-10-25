// Windows-only boundary double. macOS tests use the real WebKit module below.
#if ECARD_WEBKIT_DOUBLE
import Foundation
import FoundationNetworking

class WKWebsiteDataStore { static func `default`() -> WKWebsiteDataStore { WKWebsiteDataStore() } }
class WKWebViewConfiguration { var websiteDataStore = WKWebsiteDataStore.default() }
protocol WKNavigationDelegate: AnyObject {}
class WKNavigation: NSObject {}
class WKNavigationAction { var request = URLRequest(url: URL(string: "about:blank")!) }
enum WKNavigationActionPolicy { case allow, cancel }
class WKWebView: NSObject {
    var allowsBackForwardNavigationGestures = false
    weak var navigationDelegate: (any WKNavigationDelegate)?
    var url: URL?
    var navigations: [WKNavigation] = []
    var storageScriptCompletion: ((Any?, Error?) -> Void)?
    var stopped = false
    init(frame: CGRect, configuration: WKWebViewConfiguration) {}
    func load(_ request: URLRequest) -> WKNavigation? {
        let nav = WKNavigation()
        navigations.append(nav)
        return nav
    }
    func stopLoading() { stopped = true }
    func evaluateJavaScript(_ script: String) async throws -> Any? {
        guard script.contains("sessionStorage.getItem"), script.contains("access_token_pay") else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            storageScriptCompletion = { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }
}
typealias OfflineEcardWebView = WKWebView
#else
import Foundation
import WebKit

@MainActor final class OfflineEcardWebView: WKWebView {
    // WKNavigation must come from a real load. The factory has no delegate and
    // loads only a local empty document; school URLs never reach WebKit.
    private static let navigationFactory = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    var navigations: [WKNavigation] = []
    var pageURL: URL?
    var storageScriptCompletion: (@MainActor @Sendable (Any?, Error?) -> Void)?
    var stopped = false
    override var url: URL? { pageURL }
    override func load(_ request: URLRequest) -> WKNavigation? {
        Self.navigationFactory.stopLoading()
        guard let nav = Self.navigationFactory.loadHTMLString("<html></html>", baseURL: nil) else {
            // The test's bounded navigation wait reports an explicit failure.
            return nil
        }
        navigations.append(nav)
        return nav
    }
    override func stopLoading() { stopped = true }
    override func evaluateJavaScript(_ javaScriptString: String,
                                    completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil) {
        guard javaScriptString.contains("sessionStorage.getItem"),
              javaScriptString.contains("access_token_pay") else {
            completionHandler?(nil, nil)
            return
        }
        storageScriptCompletion = completionHandler
    }
}
#endif
