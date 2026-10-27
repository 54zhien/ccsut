"""Run LoginView's production actions with only WebKit/session boundaries replaced."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "ios/CCSUT/LoginView.swift").read_text(encoding="utf-8-sig")

def method(name):
    start = source.index("private func " + name + "(")
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    # A reference host instead of a SwiftUI value view requires explicit captures.
    return source[start:end].replace("private func", "func", 1).replace("Task {", "Task { [self] in").replace("MainActor.run {", "MainActor.run { [self] in")

harness = '''
import Foundation
@MainActor final class WebBoundary {
    var url: URL? = URL(string: "https://tls.ccsut.cn/frontend/views/student/xkPage/index.html")!
    var calls = 0
    func callAsync(_ body: String, arguments: [String: Any]) async throws -> Any? {
        calls += 1
        return "no-tab"
    }
}
@MainActor final class SessionBoundary {
    enum Phase { case loggedOut, loggedIn }
    var phase = Phase.loggedOut
    var lastError: String? = "verification unavailable"
    var accepts = true
    var adoptions = 0
    func adoptCookies() async -> Bool {
        adoptions += 1
        if accepts { phase = .loggedIn }
        return accepts
    }
    func cancelLogin() {}
}
enum InterfacePreview { static let enabled = false }
@MainActor final class Host {
    enum Busy { case idle, sending, logging, done }
    enum Field { case account, code }
    let webView = WebBoundary()
    let session = SessionBoundary()
    var busy = Busy.idle
    var focused: Field?
    var hint = ""
    var operationID = UUID()
    var pendingFinish = false
    var isFinishing = false
    var loginTimeout: Task<Void, Never>?
    var timer: Task<Void, Never>?
    var cooldown = 0
    var isPreparingWebSheet = false
    var webViewIsInSheet = false
    var showWebSheet = false
    var trimmed = "fixture-student"
    var canSend: Bool { busy == .idle && cooldown == 0 }
    static let script = ""
    // PRODUCTION_METHODS
}
@main struct Tests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("\\(ok ? "PASS" : "FAIL") \\(label)")
            if !ok { failures += 1 }
        }
        func settle() async { for _ in 0..<100 { await Task.yield() } }
        let ready = Host()
        ready.sendCode()
        await settle()
        check(ready.webView.calls == 0, "already-authenticated page never receives another SMS action")
        check(ready.session.adoptions == 1 && ready.busy == .done,
              "sending from an existing portal session adopts it instead of waiting for CAS tabs")
        let rejected = Host()
        rejected.session.accepts = false
        rejected.sendCode()
        await settle()
        check(rejected.hint == "verification unavailable" && rejected.busy == .idle,
              "failed adoption preserves the real verification error instead of a missing-form hint")
        let sheet = Host()
        sheet.showWebLogin()
        await settle()
        check(sheet.session.adoptions == 1 && !sheet.isPreparingWebSheet,
              "opening the web fallback first adopts an already-completed login")
        let cas = Host()
        cas.webView.url = URL(string: "https://auth.ccsut.cn/backstage/cas/login")!
        cas.sendCode()
        await settle()
        check(cas.webView.calls == 1 && cas.session.adoptions == 0,
              "interactive CAS still receives exactly one user-requested SMS action")
        print("Login state failures: \\(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
methods = [method(name) for name in ("sendCode", "finish", "beginTimeout", "startCooldown", "showWebLogin", "openWebSheet", "hasAcademicPage")]
harness = harness.replace("// PRODUCTION_METHODS", "\n".join(methods))
with tempfile.TemporaryDirectory(prefix="ccsut-login-state-") as folder:
    path = pathlib.Path(folder)
    swift = path / "LoginState.swift"
    swift.write_text(harness, encoding="utf-8")
    binary = path / ("tests.exe" if sys.platform == "win32" else "tests")
    compiler = ["swiftc"] if sys.platform == "win32" else ["xcrun", "swiftc"]
    subprocess.run(compiler + ["-parse-as-library", str(swift), "-o", str(binary)], check=True)
    sys.exit(subprocess.run([str(binary)], timeout=30).returncode)
