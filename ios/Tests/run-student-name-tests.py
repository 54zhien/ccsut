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
struct FakeCookie: Sendable { let name: String; let domain: String }
enum CookieJar {
    enum PersistenceState { case persisted, failed(Error) }
    static var persistenceState: PersistenceState { .persisted }
    nonisolated(unsafe) static var generation: UInt64 = 1
    nonisolated(unsafe) static var shared = [FakeCookie(name: "jw_uf", domain: "tls.ccsut.cn")]
    static func isSchoolCookie(_ cookie: FakeCookie) -> Bool { true }
}
final class FakeHTTPCookieStorage {
    static let shared = FakeHTTPCookieStorage()
    var cookies: [FakeCookie]? = [FakeCookie(name: "jw_uf", domain: "tls.ccsut.cn")]
    func deleteCookie(_ cookie: FakeCookie) { cookies?.removeAll { $0.name == cookie.name && $0.domain == cookie.domain } }
}
final class FakeCookieStore {
    func cookieSnapshot() async throws -> [FakeCookie] { [] }
    func remove(_ cookie: FakeCookie) async throws {}
}
final class FakeDataStore {
    let httpCookieStore = FakeCookieStore()
    static func nonPersistent() -> FakeDataStore { FakeDataStore() }
}
enum WebStore { static var dataStore = FakeDataStore() }
enum Keychain { static func delete(_ key: String) {} }
enum EcardTokenBridge { static func clearCachedToken() {} }
struct Identity { let studentNumber: String }
struct SessionStudentName: Equatable {
    let account: String
    let generation: UInt64
    let value: String
}
typealias StudentNameResolver = @MainActor (String, UInt64) async -> SessionStudentName?
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
    var refreshTask: Task<Void, Never>?
    var adoptionTask: Task<Bool, Never>?
    var studentId: String? = "fixture"
    var studentName: String?
    var lastError: String?
    var lastCookieCount = 1
    let api = Boundary()
    var studentNameResolver: StudentNameResolver?
    let cookieKey = "ccsut.tests.cookies.\(UUID().uuidString)"
    let sidKey = "ccsut.tests.name.id.\(UUID().uuidString)"
    let nameKey = "ccsut.tests.name.value.\(UUID().uuidString)"
    func verifySession() async throws { verifiedIdentity = (.init(studentNumber: "fixture"), CookieJar.generation) }
    func prepareEcardSession(_ id: String, _ store: FakeDataStore) {}
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
        var electiveResolverCalls = 0
        matching.studentNameResolver = { _, _ in
            electiveResolverCalls += 1
            return .init(account: "fixture", generation: CookieJar.generation, value: "不应替换")
        }
        await matching.loadProfile()
        check(matching.studentName == "示例姓名", "matching account name is trimmed before avatar publication")
        check(electiveResolverCalls == 0, "a usable elective name skips the campus lookup")
        let mismatch = Host()
        mismatch.studentName = "当前学生"
        mismatch.api.data = .init(xsxh: "another", xsxm: "其他学生")
        var mismatchResolverCalls = 0
        mismatch.studentNameResolver = { _, generation in
            mismatchResolverCalls += 1
            return .init(account: "fixture", generation: generation, value: "不应替换")
        }
        await mismatch.loadProfile()
        check(mismatch.studentName == "当前学生", "explicit account mismatch never replaces current name")
        check(mismatchResolverCalls == 0, "an explicit elective account mismatch blocks all name enrichment")
        let empty = Host()
        empty.studentName = "保留姓名"
        empty.api.data = .init(xsxh: nil, xsxm: " \n ")
        await empty.loadProfile()
        check(empty.studentName == "保留姓名", "blank optional data does not erase an existing name")
        let closed = Host()
        closed.studentName = "缓存姓名"
        closed.api.closed = true
        var cachedNameResolverCalls = 0
        closed.studentNameResolver = { _, _ in
            cachedNameResolverCalls += 1
            return .init(account: "fixture", generation: CookieJar.generation, value: "不应替换")
        }
        await closed.loadProfile()
        check(closed.studentName == "缓存姓名" && closed.phase == .loggedIn && closed.lastError == nil,
              "closed selection preserves cached identity and login state")
        check(cachedNameResolverCalls == 0, "a same-account cached name skips the campus lookup")
        let fallback = Host()
        fallback.api.closed = true
        var fallbackAccount: String?
        var fallbackGeneration: UInt64?
        fallback.studentNameResolver = { account, generation in
            fallbackAccount = account
            fallbackGeneration = generation
            return .init(account: account, generation: generation, value: "校园认证姓名")
        }
        await fallback.loadProfile()
        check(fallback.studentName == "校园认证姓名" &&
              UserDefaults.standard.string(forKey: fallback.nameKey) == "校园认证姓名",
              "closed elective channel falls back to the verified campus identity name")
        check(fallbackAccount == "fixture" && fallbackGeneration == 1,
              "campus name lookup is bound to the published account and cookie generation")
        let missingOptionalName = Host()
        missingOptionalName.api.closed = true
        var missingNameResolverCalls = 0
        missingOptionalName.studentNameResolver = { _, _ in
            missingNameResolverCalls += 1
            return nil
        }
        await missingOptionalName.loadProfile()
        check(missingNameResolverCalls == 1 && missingOptionalName.studentName == nil &&
              missingOptionalName.phase == .loggedIn && missingOptionalName.lastError == nil,
              "missing optional names never turn a verified login into a failure")
        let wrongCampusAccount = Host()
        wrongCampusAccount.api.closed = true
        wrongCampusAccount.studentNameResolver = { _, generation in
            .init(account: "another-account", generation: generation, value: "其他姓名")
        }
        await wrongCampusAccount.loadProfile()
        check(wrongCampusAccount.studentName == nil,
              "campus name from another account is rejected")
        let staleCampusName = Host()
        staleCampusName.api.closed = true
        staleCampusName.studentNameResolver = { account, generation in
            CookieJar.generation += 1
            return .init(account: account, generation: generation, value: "迟到姓名")
        }
        await staleCampusName.loadProfile()
        check(staleCampusName.studentName == nil,
              "campus name cannot publish after the cookie generation changes")
        let stale = Host()
        stale.api.replaceAccount = true
        await stale.loadProfile()
        check(stale.studentName == nil, "late name cannot cross an account generation")

        let teachingWeekCacheKey = "ccsut.teachingWeek.v1"
        let previousTeachingWeekCache = UserDefaults.standard.object(forKey: teachingWeekCacheKey)
        UserDefaults.standard.set(Data("fixture-account-cache".utf8), forKey: teachingWeekCacheKey)
        let logout = Host()
        await logout.logout()
        check(UserDefaults.standard.object(forKey: teachingWeekCacheKey) == nil,
              "logout removes the prior account teaching-week snapshot")
        if let previousTeachingWeekCache {
            UserDefaults.standard.set(previousTeachingWeekCache, forKey: teachingWeekCacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: teachingWeekCacheKey)
        }
        for host in [same, matching, mismatch, empty, closed, fallback, missingOptionalName, wrongCampusAccount, staleCampusName, stale] {
            UserDefaults.standard.removeObject(forKey: host.sidKey)
            UserDefaults.standard.removeObject(forKey: host.nameKey)
        }
        print("Student name failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
'''
production_methods = "\n".join(method(s) for s in [
    "private func publishVerifiedIdentity(", "func loadProfile() async"])
logout = method("func logout() async").replace("HTTPCookieStorage.shared", "FakeHTTPCookieStorage.shared")
harness = harness.replace("// PRODUCTION", production_methods + "\n" + logout)
with tempfile.TemporaryDirectory(prefix="ccsut-student-name-") as folder:
    path = pathlib.Path(folder)
    swift = path / "StudentName.swift"
    swift.write_text(harness, encoding="utf-8")
    binary = path / ("tests.exe" if sys.platform == "win32" else "tests")
    compiler = ["swiftc"] if sys.platform == "win32" else ["xcrun", "swiftc"]
    subprocess.run(compiler + ["-parse-as-library", str(swift), "-o", str(binary)], check=True)
    sys.exit(subprocess.run([str(binary)], timeout=30).returncode)
