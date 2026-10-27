import Foundation

@main struct StudentIdentityTests {
    static func main() throws {
        let root = URL(string: "https://tls.ccsut.cn/admin/")!
        let good = "https://tls.ccsut.cn/frontend/views/student/xkPage/index.html?username=fixture-student&enc=fixture%2Bproof&dbname=fixture"
        var checks = 0
        func reject(_ name: String, status: Int = 303, response: URL? = root, location: String?) {
            do {
                _ = try StudentIdentity.portalRedirect(status: status, responseURL: response, location: location)
                fatalError("FAIL \(name)")
            } catch APIError.notLoggedIn { checks += 1 }
            catch { fatalError("FAIL unexpected error for \(name)") }
        }
        let identity = try StudentIdentity.portalRedirect(status: 303, responseURL: root, location: good)
        precondition(identity.studentNumber == "fixture-student"); checks += 1
        let relative = good.replacingOccurrences(of: "https://tls.ccsut.cn", with: "")
        let relativeIdentity = try StudentIdentity.portalRedirect(status: 302, responseURL: root, location: relative)
        precondition(relativeIdentity == identity); checks += 1
        reject("plain 200 is not authentication", status: 200, location: good)
        reject("401 is not authentication", status: 401, location: good)
        reject("missing response URL", response: nil, location: good)
        reject("public initial resource", response: URL(string: "https://tls.ccsut.cn/frontend/public.html"), location: good)
        reject("client-influenced initial query", response: URL(string: "https://tls.ccsut.cn/admin/?username=fixture-student"), location: good)
        reject("login redirect", location: "/admin/login")
        reject("missing location", location: nil)
        reject("foreign target", location: good.replacingOccurrences(of: "tls.ccsut.cn", with: "attacker.invalid"))
        reject("lookalike target", location: good.replacingOccurrences(of: "tls.ccsut.cn", with: "tls.ccsut.cn.attacker.invalid"))
        reject("HTTP identity target", location: good.replacingOccurrences(of: "https:", with: "http:"))
        reject("nondefault port", location: good.replacingOccurrences(of: "tls.ccsut.cn", with: "tls.ccsut.cn:8443"))
        reject("userinfo", location: good.replacingOccurrences(of: "//tls", with: "//user@tls"))
        reject("unrecognized landing", location: good.replacingOccurrences(of: "/xkPage/", with: "/other/"))
        reject("fragment", location: good + "#identity")
        reject("duplicate identity", location: good + "&username=other")
        reject("duplicate proof", location: good + "&enc=other")
        reject("missing proof", location: good.replacingOccurrences(of: "&enc=fixture%2Bproof", with: ""))
        reject("empty proof", location: good.replacingOccurrences(of: "enc=fixture%2Bproof", with: "enc="))
        reject("empty identity", location: good.replacingOccurrences(of: "username=fixture-student", with: "username="))
        reject("identity control characters", location: good.replacingOccurrences(of: "fixture-student", with: "fixture%0Ast") )
        reject("trailing identity newline", location: good.replacingOccurrences(of: "fixture-student", with: "fixture%0A"))
        reject("overlong identity", location: good.replacingOccurrences(of: "fixture-student", with: String(repeating: "a", count: 65)))
        reject("proof control characters", location: good.replacingOccurrences(of: "fixture%2Bproof", with: "fixture%0Ast"))
        print("PASS: \(checks) independent student identity boundaries")
    }
}
