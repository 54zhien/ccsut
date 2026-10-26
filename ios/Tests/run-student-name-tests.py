"""Exercise production SessionStore identity/name publication with local boundaries."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "ios/CCSUT/Session.swift").read_text(encoding="utf-8-sig")

def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

harness = r'''
import Foundation
enum CookieJar { nonisolated(unsafe) static var generation: UInt64 = 1; static let shared = [1] }
enum WebStore { static let dataStore = 0 }
struct Identity { let studentNumber: String }
struct NameData { let xsxh: String?; let xsxm: String? }
enum TestFailure: Error { case closed }
@MainActor final class Boundary {
    var data = NameData(xsxh: nil, xsxm: "示例学生")
    var closed = false
    var replaceAccount = false
    func electiveInit() async throws -> NameData {
        if replaceAccount { CookieJar.generation += 1 }
        if closed { throw TestFailure.closed }
        return data
    }
}
@MainActor final class Host {
    enum Phase { case loggedIn, refreshing, loggedOut }
    var phase = Phase.loggedIn
    var isLoggingOut = false
    var verifiedIdentity: (value: Identity, generation: UInt64)? = (.init(studentNumber: "fixture"), 1)
    var studentId: String? = "fixture"
    var studentName: String?
    var lastError: String?
    let api = Boundary()
    let sidKey = "ccsut.tests.name.id.\(UUID().uuidString)"
    let nameKey = "ccsut.tests.name.value.\(UUID().uuidString)"
    func verifySession() async throws { verifiedIdentity = (.init(studentNumber: "fixture"), CookieJar.generation) }
    func prepareEcardSession(_ id: String, _ store: Int) {}
    // PRODUCTION
}
@main struct Tests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL") \(label)")
            if !value { failures += 1 }
        }
        let same = Host()
        await same.loadProfile()
        check(same.studentName == "示例学生", "verified account accepts optional display name without repeated account field")
        check(UserDefaults.standard.string(forKey: same.nameKey) == "示例学生", "accepted name is persisted for the verified account")
        let matching = Host()
        matching.api.data = .init(xsxh: "fixture", xsxm: "  示例姓名  ")
        await matching.loadProfile()
        check(matching.studentName == "示例姓名", "matching account name is trimmed before avatar publication")
        let mismatch = Host()
        mismatch.studentName = "当前学生"
        mismatch.api.data = .init(xsxh: "another", xsxm: "其他学生")
        await mismatch.loadProfile()
        check(mismatch.studentName == "当前学生", "explicit account mismatch never replaces current name")
        let empty = Host()
        empty.studentName = "保留姓名"
        empty.api.data = .init(xsxh: nil, xsxm: " \n ")
        await empty.loadProfile()
        check(empty.studentName == "保留姓名", "blank optional data does not erase an existing name")
        let closed = Host()
        closed.studentName = "缓存姓名"
        closed.api.closed = true
        await closed.loadProfile()
        check(closed.studentName == "缓存姓名" && closed.phase == .loggedIn && closed.lastError == nil,
              "closed selection preserves cached identity and login state")
        let stale = Host()
        stale.api.replaceAccount = true
        await stale.loadProfile()
        check(stale.studentName == nil, "late name cannot cross an account generation")
        for host in [same, matching, mismatch, empty, closed, stale] {
            UserDefaults.standard.removeObject(forKey: host.sidKey)
            UserDefaults.standard.removeObject(forKey: host.nameKey)
        }
        print("Student name failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
harness = harness.replace("// PRODUCTION", "\n".join(method(s) for s in [
    "private func publishVerifiedIdentity(", "func loadProfile() async"]))
with tempfile.TemporaryDirectory(prefix="ccsut-student-name-") as folder:
    path = pathlib.Path(folder)
    swift = path / "StudentName.swift"
    swift.write_text(harness, encoding="utf-8")
    binary = path / ("tests.exe" if sys.platform == "win32" else "tests")
    compiler = ["swiftc"] if sys.platform == "win32" else ["xcrun", "swiftc"]
    subprocess.run(compiler + ["-parse-as-library", str(swift), "-o", str(binary)], check=True)
    sys.exit(subprocess.run([str(binary)], timeout=30).returncode)
