import Foundation

enum APIError: LocalizedError {
    case notLoggedIn
    case http(Int)
    case business(Int, String)
    case empty
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "登录已失效，请重新登录"
        case .http(let code):
            return "网络错误 HTTP \(code)"
        case .business(let ret, let message):
            return "接口返回错误 [\(ret)] \(message)"
        case .empty:
            return "接口返回空数据"
        case .decoding(let context):
            return "数据解析失败：\(context)"
        }
    }
}

enum APIResponseDecoder {
    private struct ResponseStatus: Decodable {
        let ret: Int
    }

    private struct ResponsePayload<T: Decodable>: Decodable {
        let data: T?
    }

    private static let safeBusinessMessage = "教务系统暂时无法处理此请求"

    static func businessError(_ ret: Int, message: String?) -> APIError {
        if indicatesExpiredSession(message) { return .notLoggedIn }
        return .business(ret, userFacingBusinessMessage(message))
    }

    /// Decodes either a known `{ret, data}` response envelope or a supported bare payload.
    /// Once an object contains an envelope marker, it is never retried as a bare payload.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else { throw APIError.empty }

        let root = try jsonRoot(from: data)

        if let object = root as? [String: Any],
           isEnvelope(object) {
            return try decodeEnvelopePayload(type, from: data, object: object)
        }

        return try decodeBare(type, from: data)
    }

    /// Decodes only responses that carry the shared status/data envelope.
    /// Authentication probes use this to reject a bare profile object.
    static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else { throw APIError.empty }
        let root = try jsonRoot(from: data)
        guard let object = root as? [String: Any], isEnvelope(object) else {
            throw APIError.decoding("响应包装缺失")
        }
        return try decodeEnvelopePayload(type, from: data, object: object)
    }

    /// Used only for endpoints whose documented response is a bare status object,
    /// such as enrollment and withdrawal acknowledgements.
    static func decodeBare<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty else { throw APIError.empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding("响应格式无效")
        }
    }

    private static func jsonRoot(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw APIError.decoding("响应格式无效")
        }
    }

    private static func isEnvelope(_ object: [String: Any]) -> Bool {
        object.keys.contains("ret") || object.keys.contains("data")
    }

    private static func decodeEnvelopePayload<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        object: [String: Any]
    ) throws -> T {
        let status: ResponseStatus
        do {
            status = try JSONDecoder().decode(ResponseStatus.self, from: data)
        } catch {
            throw APIError.decoding("响应包装缺少有效状态码")
        }

        guard status.ret == 0 else {
            throw businessError(status.ret, message: object["msg"] as? String)
        }

        let envelope: ResponsePayload<T>
        do {
            envelope = try JSONDecoder().decode(ResponsePayload<T>.self, from: data)
        } catch {
            throw APIError.decoding("响应数据格式无效")
        }
        guard let payload = envelope.data else { throw APIError.empty }
        return payload
    }

    private static func userFacingBusinessMessage(_ message: String?) -> String {
        guard let candidate = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty,
              candidate.count <= 120,
              !candidate.hasPrefix("{"),
              !candidate.hasPrefix("["),
              !candidate.lowercased().hasPrefix("<?xml"),
              !contains(candidate, pattern: #"(?is)<\s*(?:!doctype\b|/?[a-z][a-z0-9:-]*(?:\s[^>]*)?\s*/?)>"#),
              !contains(candidate, pattern: #"(?i)(?:https?://|ftp://|www\.)\S+"#),
              !contains(candidate, pattern: #"(?i)\b(?:cookie|set-cookie|authorization|bearer|token|access[_-]?token|refresh[_-]?token|password|passwd|credential|secret|session(?:id|_id)?|sid|jw_uf|tgc|ticket|jsessionid)\b"#)
        else {
            return safeBusinessMessage
        }
        return candidate
    }

    private static func indicatesExpiredSession(_ message: String?) -> Bool {
        guard let message else { return false }
        let normalized = message.lowercased()
        let chineseSignals = [
            "未登录", "请先登录", "请重新登录", "登录已失效", "登录过期", "登录超时", "会话失效", "会话过期",
        ]
        let englishSignals = ["session expired", "authentication required", "unauthorized"]
        return chineseSignals.contains(where: normalized.contains)
            || englishSignals.contains(where: normalized.contains)
    }

    private static func contains(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
