import Foundation

enum CampusError: Error, LocalizedError, Equatable, Sendable {
    case authentication, forbidden, invalidResponse, serviceUnavailable, identityMismatch
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .authentication: return "校园会话已失效，请打开官方页面完成认证后重试"
        case .forbidden: return "当前账号暂时无法访问这项服务"
        case .invalidResponse: return "校园服务返回的数据格式有误，请稍后重试"
        case .serviceUnavailable: return "校园服务暂时不可用，请稍后重试"
        case .identityMismatch: return "校园服务账号与当前登录账号不一致，请重新登录"
        case .http(let status): return "校园服务连接失败（\(status)），请稍后重试"
        }
    }
}

enum CampusPrivacy {
    /// Apply at the decoding boundary, including unstructured user-entered text.
    static func redact(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<![0-9])[0-9](?:[ \t-]?[0-9]){10,24}[Xx]?(?![0-9])"#,
            with: "••••", options: .regularExpression
        )
    }
}

struct CampusLeaveRecord: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let typeName: String?
    let beginTime: String?
    let endTime: String?
    let days: Decimal?
    let status: Int?
    let reason: String?
    let applyTime: String?

    var statusText: String {
        guard let status else { return "状态未知" }
        return status == 0 ? "待审核" : "状态 \(status)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, leaveTypeName, beginTime, endTime, leaveDay, status, reason, applyTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        guard !id.isEmpty else { throw CampusError.invalidResponse }
        typeName = try c.safeText(.leaveTypeName)
        beginTime = try c.safeText(.beginTime)
        endTime = try c.safeText(.endTime)
        days = try c.decodeIfPresent(Decimal.self, forKey: .leaveDay)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        reason = try c.safeText(.reason)
        applyTime = try c.safeText(.applyTime)
    }
}

struct CampusTravelRecord: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let statusText: String
    let destination: String?
    let transport: String?
    let reason: String?
    let applyDate: String?
    let startDate: String?
    let endDate: String?

    private enum CodingKeys: String, CodingKey {
        case openid, batchName, typeName, status, txdz, jtgj, reason, applyDate, startDate, endDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .openid)
        guard !id.isEmpty else { throw CampusError.invalidResponse }
        title = try c.safeText(.batchName) ?? c.safeText(.typeName) ?? "节假日记录"
        statusText = try c.safeText(.status) ?? "状态未知"
        destination = try c.safeText(.txdz)
        transport = try c.safeText(.jtgj)
        reason = try c.safeText(.reason)
        applyDate = try c.safeText(.applyDate)
        startDate = try c.safeText(.startDate)
        endDate = try c.safeText(.endDate)
    }
}

private extension KeyedDecodingContainer {
    func safeText(_ key: Key) throws -> String? {
        guard let text = try decodeIfPresent(String.self, forKey: key), !text.isEmpty else { return nil }
        return CampusPrivacy.redact(text)
    }
}

struct CampusLeavePage: Decodable, Sendable {
    let items: [CampusLeaveRecord]
    let page: Int
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey { case list, pageNum, pageSize, total, hasNextPage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([CampusLeaveRecord].self, forKey: .list)
        page = try c.decode(Int.self, forKey: .pageNum)
        let size = try c.decode(Int.self, forKey: .pageSize)
        let total = try c.decode(Int.self, forKey: .total)
        guard page > 0, size > 0, total >= items.count else { throw CampusError.invalidResponse }
        let consumed = page.multipliedReportingOverflow(by: size)
        guard !consumed.overflow else { throw CampusError.invalidResponse }
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasNextPage) ?? (consumed.partialValue < total)
    }
}

/// Mutations happen only after a fully successful read; failure never advances a page.
struct CampusPageState: Sendable {
    private(set) var items: [CampusLeaveRecord] = []
    private(set) var page = 0
    private(set) var hasMore = false

    mutating func apply(_ result: CampusLeavePage, reset: Bool) throws {
        guard result.page == (reset ? 1 : page + 1) else { throw CampusError.invalidResponse }
        var updated = reset ? [] : items
        var seen = Set(updated.map(\.id))
        for item in result.items where seen.insert(item.id).inserted { updated.append(item) }
        items = updated
        page = result.page
        hasMore = result.hasMore
    }
}

private struct CampusEnvelope<Payload: Decodable>: Decodable {
    let data: Payload
    private enum CodingKeys: String, CodingKey { case data, code, success, errorMessage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let error = try c.decodeIfPresent(String.self, forKey: .errorMessage), !error.isEmpty {
            throw CampusError.serviceUnavailable
        }
        if try c.decodeIfPresent(Bool.self, forKey: .success) == false { throw CampusError.serviceUnavailable }
        if c.contains(.code), try !c.decodeNil(forKey: .code) {
            let code: String
            if let text = try? c.decode(String.self, forKey: .code) { code = text }
            else { code = String(try c.decode(Int.self, forKey: .code)) }
            switch code {
            case "200", "2000": break
            case "401": throw CampusError.authentication
            case "403": throw CampusError.forbidden
            default: throw CampusError.serviceUnavailable
            }
        }
        data = try c.decode(Payload.self, forKey: .data)
    }
}

enum CampusDecoder {
    static func leavePage(_ data: Data) throws -> CampusLeavePage { try decode(data) }
    static func travelRecords(_ data: Data) throws -> [CampusTravelRecord] { try decode(data) }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(CampusEnvelope<T>.self, from: data).data }
        catch let error as CampusError { throw error }
        catch { throw CampusError.invalidResponse }
    }
}
