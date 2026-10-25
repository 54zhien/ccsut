import Foundation

@main
struct APIResponseTests {
    private struct OptionalList: Decodable {
        let items: [Int]?
    }

    private struct RequiredList: Decodable {
        let items: [Int]
    }

    private struct BareAcknowledgement: Decodable {
        let ret: Int
        let msg: String?
    }

    private struct Profile: Decodable {
        let xsxh: String?
    }

    static func main() {
        var failures = 0

        func check(_ condition: Bool, _ name: String) {
            let line = "\(condition ? "PASS" : "FAIL") \(name)\n"
            try? FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
            if !condition { failures += 1 }
        }

        func isNotLoggedIn(_ error: APIError) -> Bool {
            if case .notLoggedIn = error { return true }
            return false
        }

        func expectAPIError<T: Decodable>(
            _ type: T.Type,
            json: String,
            named name: String,
            checkError: (APIError) -> Bool
        ) {
            do {
                _ = try APIResponseDecoder.decode(type, from: Data(json.utf8))
                check(false, name)
            } catch let error as APIError {
                check(checkError(error), name)
            } catch {
                check(false, "\(name) uses APIError")
            }
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":-7,"msg":"当前批次已选门数超过【4门】","data":{"items":"malformed"}}"#,
            named: "nonzero ret wins over a malformed data payload"
        ) { error in
            guard case .business(let code, let message) = error else { return false }
            return code == -7
                && message == "当前批次已选门数超过【4门】"
                && error.localizedDescription.contains(message)
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":-1,"msg":"session expired","data":{"items":[]}}"#,
            named: "nonzero ret with valid data and expired session is still rejected"
        ) { isNotLoggedIn($0) }

        for message in [
            "未登录", "请先登录", "请重新登录", "登录已失效", "登录过期", "登录超时",
            "会话失效", "会话过期", "session expired", "authentication required", "unauthorized"
        ] {
            check(isNotLoggedIn(APIResponseDecoder.businessError(-1, message: message)),
                  "authentication message maps to not logged in: \(message)")
        }

        let permissionError = APIResponseDecoder.businessError(-1, message: "当前用户权限不足")
        if case .business(_, let message) = permissionError {
            check(message == "当前用户权限不足", "ordinary permission rejection remains a business error")
        } else {
            check(false, "ordinary permission rejection remains a business error")
        }

        do {
            let acknowledgement = try APIResponseDecoder.decodeBare(
                BareAcknowledgement.self,
                from: Data(#"{"ret":-1,"msg":"当前批次已选门数超过【4门】"}"#.utf8)
            )
            let error = APIResponseDecoder.businessError(acknowledgement.ret, message: acknowledgement.msg)
            if case .business(let code, let message) = error {
                check(code == -1 && message == "当前批次已选门数超过【4门】",
                      "bare enrollment error retains its readable business message")
            } else {
                check(false, "bare enrollment error retains its readable business message")
            }
        } catch {
            check(false, "bare enrollment error retains its readable business message")
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":-1,"msg":"<html><body>登录页</body></html>","data":{"items":[]}}"#,
            named: "HTML business response is not exposed"
        ) { error in
            guard case .business(_, let message) = error else { return false }
            return !message.contains("<html") && !error.localizedDescription.contains("登录页")
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":-1,"msg":"请访问 https://auth.ccsut.cn/login?ticket=secret","data":{"items":[]}}"#,
            named: "URL business response is not exposed"
        ) { error in
            guard case .business(_, let message) = error else { return false }
            return !message.contains("auth.ccsut.cn") && !error.localizedDescription.contains("ticket=secret")
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":-1,"msg":"TGC=secret-cookie; token=abc123","data":{"items":[]}}"#,
            named: "credential-bearing business message is not exposed"
        ) { error in
            guard case .business(_, let message) = error else { return false }
            return !message.contains("secret-cookie") && !message.contains("abc123")
        }

        let longMessage = String(repeating: "业务限制 ", count: 30)
        let longBusinessError = APIResponseDecoder.businessError(-2, message: longMessage)
        if case .business(_, let safeMessage) = longBusinessError {
            check(!safeMessage.contains("业务限制") && !longBusinessError.localizedDescription.contains("业务限制"),
                  "overlong business message is not exposed")
        } else {
            check(false, "overlong business message is not exposed")
        }

        do {
            let profile = try APIResponseDecoder.decodeEnvelope(
                Profile.self,
                from: Data(#"{"ret":0,"data":{"xsxh":"fixture-student"}}"#.utf8)
            )
            check(profile.xsxh == "fixture-student", "required-envelope profile accepts valid wrapped identity")
        } catch {
            check(false, "required-envelope profile accepts valid wrapped identity")
        }

        do {
            _ = try APIResponseDecoder.decodeEnvelope(
                Profile.self,
                from: Data(#"{"xsxh":"fixture-student"}"#.utf8)
            )
            check(false, "bare profile cannot satisfy authentication probe")
        } catch let error as APIError {
            if case .decoding = error {
                check(true, "bare profile cannot satisfy authentication probe")
            } else {
                check(false, "bare profile cannot satisfy authentication probe")
            }
        } catch {
            check(false, "bare profile cannot satisfy authentication probe")
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":0,"data":{"items":"not-an-array"}}"#,
            named: "malformed wrapped payload never falls back to the bare object"
        ) { error in
            guard case .decoding = error else { return false }
            return !error.localizedDescription.contains("not-an-array")
        }

        do {
            let result = try APIResponseDecoder.decode(
                RequiredList.self,
                from: Data(#"{"ret":0,"data":{"items":[1,2]}}"#.utf8)
            )
            check(result.items == [1, 2], "valid wrapped payload decodes")
        } catch {
            check(false, "valid wrapped payload decodes")
        }

        do {
            let result = try APIResponseDecoder.decode(
                RequiredList.self,
                from: Data(#"{"items":[3]}"#.utf8)
            )
            check(result.items == [3], "supported bare payload decodes")
        } catch {
            check(false, "supported bare payload decodes")
        }

        do {
            let wrapped = try APIResponseDecoder.decode(
                RequiredList.self,
                from: Data(#"{"ret":0,"data":{"items":[]}}"#.utf8)
            )
            let bare = try APIResponseDecoder.decode(
                RequiredList.self,
                from: Data(#"{"items":[]}"#.utf8)
            )
            check(wrapped.items.isEmpty && bare.items.isEmpty, "explicitly empty list stays empty")
        } catch {
            check(false, "explicitly empty list stays empty")
        }

        expectAPIError(
            RequiredList.self,
            json: #"{"ret":0,"data":{}}"#,
            named: "missing required list container is an error"
        ) { error in
            if case .empty = error { return true }
            if case .decoding = error { return true }
            return false
        }

        expectAPIError(
            OptionalList.self,
            json: #"{"ret":0}"#,
            named: "recognized wrapper without data is an error"
        ) { error in
            if case .empty = error { return true }
            if case .decoding = error { return true }
            return false
        }

        do {
            let ack = try APIResponseDecoder.decodeBare(
                BareAcknowledgement.self,
                from: Data(#"{"ret":0,"msg":"accepted"}"#.utf8)
            )
            check(ack.ret == 0 && ack.msg == "accepted", "known bare status response remains supported")
        } catch {
            check(false, "known bare status response remains supported")
        }

        try? FileHandle.standardOutput.write(contentsOf: Data("API response failures: \(failures)\n".utf8))
        if failures > 0 { fatalError("API response tests failed") }
    }
}
