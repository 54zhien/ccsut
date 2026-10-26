import Foundation

@main struct StudentHomeIdentityTests {
    static func main() throws {
        let root = URL(string: "https://tls.ccsut.cn/admin/")!
        let good = """
        <!doctype html><html><body>
        <input type="hidden" id="roleId" value="xs">
        <input type="hidden" id="xhid" value="fixture-internal-id">
        <input type="hidden" id="encodeId" value="fixture-server-proof">
        <div class="userInfo"><p><span class="admin_name">fixture-student</span></p></div>
        <div class="school-notice">????</div>
        </body></html>
        """
        var checks = 0
        let identity = try StudentIdentity.portalPage(status: 200, responseURL: root, html: good)
        precondition(identity.studentNumber == "fixture-student"); checks += 1
        let reordered = good.replacingOccurrences(of: "type=\"hidden\" id=\"roleId\" value=\"xs\"", with: "value='xs' id='roleId' type='hidden'")
        let reorderedIdentity = try StudentIdentity.portalPage(status: 200, responseURL: root, html: reordered)
        precondition(reorderedIdentity == identity); checks += 1
        let nestedIdentity = try StudentIdentity.portalPage(status: 200, responseURL: root, html: "<div class='outer'>" + good + "</div>")
        precondition(nestedIdentity == identity); checks += 1
        func reject(_ name: String, status: Int = 200, response: URL? = root, html: String = good) {
            do {
                _ = try StudentIdentity.portalPage(status: status, responseURL: response, html: html)
                fatalError("FAIL \(name)")
            } catch APIError.notLoggedIn { checks += 1 }
            catch { fatalError("FAIL unexpected error for \(name)") }
        }
        reject("missing response", response: nil)
        reject("static public home", response: URL(string: "https://tls.ccsut.cn/frontend/home.html"))
        reject("foreign origin", response: URL(string: "https://attacker.invalid/admin/"))
        reject("HTTP origin", response: URL(string: "http://tls.ccsut.cn/admin/"))
        reject("nondefault port", response: URL(string: "https://tls.ccsut.cn:8443/admin/"))
        reject("userinfo", response: URL(string: "https://user@tls.ccsut.cn/admin/"))
        reject("client influenced account", response: URL(string: "https://tls.ccsut.cn/admin/?username=fixture-student"))
        reject("fragment", response: URL(string: "https://tls.ccsut.cn/admin/#home"))
        reject("login HTML", html: "<input name='username' value='fixture-student'><input type='password'>")
        reject("anonymous HTTP 200", html: "<html>public page</html>")
        reject("error status", status: 500)
        reject("nonstudent role", html: good.replacingOccurrences(of: "value=\"xs\"", with: "value=\"teacher\""))
        reject("missing role", html: good.replacingOccurrences(of: "id=\"roleId\"", with: "id=\"other\""))
        reject("missing student context", html: good.replacingOccurrences(of: "id=\"xhid\"", with: "id=\"other\""))
        reject("empty proof", html: good.replacingOccurrences(of: "fixture-server-proof", with: ""))
        reject("account outside user header", html: good.replacingOccurrences(of: "class=\"userInfo\"", with: "class=\"public\""))
        reject("invalid account", html: good.replacingOccurrences(of: "fixture-student", with: "bad account"))
        reject("ambiguous account", html: good.replacingOccurrences(of: "</p>", with: "<span class='admin_name'>other</span></p>"))
        reject("duplicate role", html: good + "<input type='hidden' id='roleId' value='xs'>")
        reject("duplicate proof", html: good + "<input type='hidden' id='encodeId' value='other'>")
        print("PASS: \(checks) protected student home identity boundaries")
    }
}
