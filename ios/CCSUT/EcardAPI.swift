// Synjones charge-app transport and payment protocol.
// Requests use the application Basic header and the account-specific synjones-auth token.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 错误

enum EcardError: LocalizedError {
    /// 后端返回 {code:xxx,msg:"..."} 的业务错误
    case business(Int, String)
    case http(Int)
    case decoding(String)
    /// 网络层错误（断网、超时、TLS 等），统一收口成这一种
    case transport(String)
    case noToken
    case authenticationRequired
    case authenticationTimeout(EcardAuthenticationStage)
    case sessionSynchronization
    case canceled
    /// 建单被拒（code 非 200 或 success=false）
    case orderRejected(String)
    /// 建单返回里没有可用的余额支付通道
    case paymentChannelUnavailable
    /// 通道要求支付密码，本层不处理
    case passwordRequired
    /// 房间明细缺少关键字段
    case incompleteRoomDetail([String])
    /// 支付已提交但订单状态未确认
    case paymentUnconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .business(let code, let msg): return "缴费接口返回错误 [\(code)] \(msg)"
        case .http(let code):              return "网络错误 HTTP \(code)"
        case .decoding(let what):          return "数据解析失败：\(what)"
        case .transport(let what):         return "网络异常：\(what)"
        case .noToken:                     return "未获取到缴费凭证，请重新登录"
        case .authenticationRequired:      return "一卡通或学校访问网关登录已失效，请重新认证"
        case .authenticationTimeout(let stage): return "\(stage.label)超时，请重新加载；如需验证可打开认证页面"
        case .sessionSynchronization:      return "同步校园网页认证失败，请重新加载后再试"
        case .canceled:                    return "操作已取消"
        case .orderRejected(let msg):      return "建单失败：\(msg)"
        case .paymentChannelUnavailable:   return "当前没有可用的余额支付方式"
        case .passwordRequired:            return "该支付方式需要支付密码，请到一卡通页面完成"
        case .incompleteRoomDetail(let ks):return "房间信息不完整，缺少：\(ks.joined(separator: "、"))"
        case .paymentUnconfirmed(let oid): return "支付已提交，结果待确认（订单 \(oid)）"
        }
    }
}

// MARK: - 缴费项目

struct FeeItemEnvelope: Decodable {
    let code: Int
    let msg: String?
    let view: String?
    let feeitem: FeeItem?
}

struct FeeItem: Decodable {
    let feeitemid: String
    let name: String
    /// 10 位开关位，逐位控制前端形态
    let flag: String
    /// choose = 三级联选；enter = 直接输入
    let view: String?
    /// 金额单位，实测「元」
    let billingUnit: String?
    /// 单笔上限，实测 "400"
    let maxmoney: String?
    /// 单日上限，实测 "1000"
    let daymaxmoney: String?
    /// 快捷金额，实测 "10,50,100"
    let dayout: String?
    let implInterface: String?
    let feeitemImplBean: FeeItemImpl?

    enum CodingKeys: String, CodingKey {
        case feeitemid, name, flag, view
        case billingUnit   = "billing_unit"
        case maxmoney, daymaxmoney, dayout
        case implInterface = "impl_interface"
        case feeitemImplBean
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feeitemid = try c.ecardText(forKey: .feeitemid)
        name = try c.decode(String.self, forKey: .name)
        flag = try c.decode(String.self, forKey: .flag)
        view = try c.decodeIfPresent(String.self, forKey: .view)
        billingUnit = try c.decodeIfPresent(String.self, forKey: .billingUnit)
        maxmoney = try c.ecardTextIfPresent(forKey: .maxmoney, allowsDecimal: true)
        daymaxmoney = try c.ecardTextIfPresent(forKey: .daymaxmoney, allowsDecimal: true)
        dayout = try c.decodeIfPresent(String.self, forKey: .dayout)
        implInterface = try c.decodeIfPresent(String.self, forKey: .implInterface)
        feeitemImplBean = try c.decodeIfPresent(FeeItemImpl.self, forKey: .feeitemImplBean)
    }

    // flag[4] → 0 选择模式 / 1 输入模式 / 4 IEC 电表模式
    // flag[7] → 是否需要输入金额
    // flag[9] → "2" 表示需要先改密码
    var isSelectMode: Bool { bit(4) == "0" }
    var needsAmount:  Bool { bit(7) == "1" }
    var requiresPasswordChange: Bool { bit(9) == "2" }

    private func bit(_ index: Int) -> Character? {
        let chars = Array(flag)
        return index < chars.count ? chars[index] : nil
    }

    var unit: String { billingUnit ?? "元" }
    var quickAmounts: [Decimal] {
        (dayout ?? "").split(separator: ",").compactMap { Decimal(string: String($0)) }
    }
    var maxAmount: Decimal? { maxmoney.flatMap { Decimal(string: $0) } }
    var dayMaxAmount: Decimal? { daymaxmoney.flatMap { Decimal(string: $0) } }
    var vendorName: String? { feeitemImplBean?.implname }

    /// 金额是否落在服务端给出的范围内
    func accepts(amount: Decimal) -> Bool {
        guard amount > 0 else { return false }
        if let max = maxAmount, amount > max { return false }
        if let dayMax = dayMaxAmount, amount > dayMax { return false }
        return true
    }
}

struct FeeItemImpl: Decodable {
    let implname: String?
    let code: String?
}

// MARK: - 级联字典

struct ThirdDataEnvelope: Decodable {
    let code: Int
    let msg: String?
    let map: ThirdDataMap?
}

struct ThirdDataMap: Decodable {
    /// 级别定义：campus(1) → building(2) → room(3)
    let total: [ThirdLevel]?
    /// 当前层可选项
    let data: [ThirdOption]?
    /// 第三级 data 是对象，保留原始字典
    let detail: [String: JSONValue]?
    /// 展示文案，实测 {"房间信息":"…","表类型":"电表","剩余金额":"-1150.093"}
    let showData: [String: String]?
    let dataType: String?

    enum CodingKeys: String, CodingKey { case total, data, showData, dataType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total     = try c.decodeIfPresent([ThirdLevel].self, forKey: .total)
        showData  = try c.decodeIfPresent([String: String].self, forKey: .showData)
        dataType  = try c.decodeIfPresent(String.self, forKey: .dataType)

        // 明确区分「字段缺失」与「类型不对」：后者直接报错，不再静默当成空列表
        if c.contains(.data), try !c.decodeNil(forKey: .data) {
            if let list = try? c.decode([ThirdOption].self, forKey: .data) {
                data = list
                detail = nil
            } else if let obj = try? c.decode([String: JSONValue].self, forKey: .data) {
                data = nil
                detail = obj
            } else {
                throw DecodingError.typeMismatch(
                    Any.self,
                    DecodingError.Context(
                        codingPath: c.codingPath + [CodingKeys.data],
                        debugDescription: "map.data 既不是数组也不是对象"
                    )
                )
            }
        } else {
            data = nil
            detail = nil
        }
    }

    /// 房间明细缺少的必填字段（空数组表示齐了）
    var missingMeterKeys: [String] {
        let required = ["house_id", "house_no", "meter_id", "meter_no", "customer_name", "sno"]
        guard let detail else { return required }
        return required.filter { key in
            guard let value = detail[key]?.stringValue, !value.isEmpty else { return true }
            return value == "null"
        }
    }

    var meterContext: MeterContext? {
        guard let d = detail else { return nil }
        // 实测服务端要求这些字段原样回传 —— 包括字符串 "null"（如 sysId），
        // 所以这里只把「空串」当缺失，不再把 "null" 转成 nil。
        func v(_ k: String) -> String? {
            guard let s = d[k]?.stringValue, !s.isEmpty else { return nil }
            return s
        }
        return MeterContext(
            avgPrice: v("avgPrice"),
            buyTime: v("buy_time"),
            ctpt: v("ctpt"),
            customerName: v("customer_name"),
            customerNo: v("customer_no"),
            freeBalance: v("free_balance"),
            houseAddr: v("house_addr"),
            houseID: v("house_id"),
            houseNo: v("house_no"),
            meterBalance: v("meter_balance"),
            meterBalanceTime: v("meter_balance_time"),
            meterID: v("meter_id"),
            meterNo: v("meter_no"),
            meterStatus: v("meter_status"),
            meterType: v("meter_type"),
            payType: v("pay_type"),
            payid: v("payid"),
            sysId: v("sysId"),
            walletBalance: v("wallet_balance"),
            sno: v("sno"),
            userName: v("userName"),
            myCustomInfo: v("myCustomInfo")
        )
    }
}

struct ThirdLevel: Decodable {
    let code: String
    let level: String
    let name: String

    enum CodingKeys: String, CodingKey { case code, level, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.ecardText(forKey: .code)
        level = try c.ecardText(forKey: .level)
        name = try c.decode(String.self, forKey: .name)
    }
}

struct ThirdOption: Decodable {
    let name: String
    let value: String

    enum CodingKeys: String, CodingKey { case name, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        value = try c.ecardText(forKey: .value)
    }
}

// The backend can encode numeric IDs/limits as JSON numbers or strings.
// Preserve strings (including leading zeroes); never pass IDs through Double,
// or coerce booleans/objects/missing values into usable room selections.
private extension KeyedDecodingContainer {
    func ecardText(forKey key: Key, allowsDecimal: Bool = false) throws -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(UInt64.self, forKey: key) { return String(value) }
        if allowsDecimal, let value = try? decode(Decimal.self, forKey: key) {
            return NSDecimalNumber(decimal: value).stringValue
        }
        // Retain the decoder's precise missing/null/type error and coding path.
        return try decode(String.self, forKey: key)
    }

    func ecardTextIfPresent(forKey key: Key, allowsDecimal: Bool = false) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try ecardText(forKey: key, allowsDecimal: allowsDecimal)
    }
}

// MARK: - 房间 / 电表上下文

/// 建单时服务端要求把房间与电表信息原样回传（实测字段）。
///
/// 注意：实测请求里每个值都是 **JSON 编码后的字符串**（带外层双引号），
/// 例如 `house_no="208"`，所以 `formFields` 统一做 JSON 编码。
struct MeterContext {
    var avgPrice: String?
    var buyTime: String?
    var ctpt: String?
    var customerName: String?
    var customerNo: String?
    var freeBalance: String?
    var houseAddr: String?
    var houseID: String?
    var houseNo: String?
    var meterBalance: String?
    var meterBalanceTime: String?
    var meterID: String?
    var meterNo: String?
    var meterStatus: String?
    var meterType: String?
    var payType: String?
    var payid: String?
    var sysId: String?
    var walletBalance: String?
    var sno: String?
    var userName: String?
    var myCustomInfo: String?

    var pricePerKWh: Decimal? { avgPrice.flatMap { Decimal(string: $0) } }
    var walletAmount: Decimal? { walletBalance.flatMap { Decimal(string: $0) } }
    var cardAmount: Decimal? { freeBalance.flatMap { Decimal(string: $0) } }

    var formFields: [String: String] {
        var out: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            out[key] = Self.jsonQuoted(value)
        }
        put("avgPrice", avgPrice)
        put("buy_time", buyTime)
        put("ctpt", ctpt)
        put("customer_name", customerName)
        put("customer_no", customerNo)
        put("free_balance", freeBalance)
        put("house_addr", houseAddr)
        put("house_id", houseID)
        put("house_no", houseNo)
        put("meter_balance", meterBalance)
        put("meter_balance_time", meterBalanceTime)
        put("meter_id", meterID)
        put("meter_no", meterNo)
        put("meter_status", meterStatus)
        put("meter_type", meterType)
        put("pay_type", payType)
        put("payid", payid)
        put("sysId", sysId)
        put("wallet_balance", walletBalance)
        put("sno", sno)
        put("userName", userName)
        put("myCustomInfo", myCustomInfo)
        return out
    }

    static func jsonQuoted(_ s: String) -> String {
        // A String is always JSON-encodable; let the encoder escape control
        // characters as well as quotes/backslashes without changing its value.
        String(decoding: try! JSONEncoder().encode(s), as: UTF8.self)
    }
}

/// 第三级返回的完整明细
struct MeterDetail {
    let context: MeterContext
    let show: [String: String]
    let dataType: String?

    var roomDescription: String? { show["房间信息"] }
    var meterTypeName:   String? { show["表类型"] }
    /// 剩余金额（元），负数表示欠费
    var remainingAmount: Decimal? {
        show["剩余金额"].flatMap { Decimal(string: $0) }
    }
}

// MARK: - 建单 / 支付

struct CreateOrderEnvelope: Decodable {
    let code: Int
    let msg: String?
    let success: Bool?
    let data: CreatedOrder?
}

struct CreatedOrder: Decodable {
    let orderid: String?
    let paystep: Int?
    let payExpDate: String?
    let payList: [OrderPayChannel]?
}

struct OrderPayChannel: Decodable {
    let id: String?
    let name: String?
    let code: String?
    let icon: String?
    let nopassword: String?
    let partnerKey: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, code, nopassword
        case nameSnake = "pay_type_name"
        case codeSnake = "pay_type_code"
        case partnerKey = "partner_key"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id)
        icon       = try c.decodeIfPresent(String.self, forKey: .icon)
        nopassword = try c.decodeIfPresent(String.self, forKey: .nopassword)
        partnerKey = try c.decodeIfPresent(String.self, forKey: .partnerKey)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .nameSnake)
        code = try c.decodeIfPresent(String.self, forKey: .code)
            ?? c.decodeIfPresent(String.self, forKey: .codeSnake)
    }

    var isInternalBalance: Bool {
        let c = (code ?? "").uppercased()
        return c.hasPrefix("ACCOUNT") || c.hasPrefix("CARD")
    }
    /// 只有明确 `"0"` 才认为免密；缺失或其它值都按「需要密码」处理
    var isPasswordFree: Bool { nopassword == "0" }
}

struct PayInfoEnvelope: Decodable {
    let code: Int?
    let msg: String?
    let order: PayOrder?
    let payList: [PayChannel]?
}

struct PayOrder: Decodable {
    let orderid: String?
    /// 1 = 订单已完成（付费成功）
    let status: Int?
    let payexpdate: String?
}

struct PayChannel: Decodable {
    let payid: Int?
    let name: String?
    let code: String?
    let icon: String?
    let noticurl: String?
    let nopassword: Int?
    let partnerKey: String?
    let flag: String?

    enum CodingKeys: String, CodingKey {
        case payid, name, code, icon, noticurl, nopassword, flag
        case partnerKey = "partner_key"
    }

    var isInternalBalance: Bool {
        let c = (code ?? "").uppercased()
        return c.hasPrefix("ACCOUNT") || c.hasPrefix("CARD")
    }
    var isPasswordFree: Bool { nopassword == 0 }
}

struct PayResultEnvelope: Decodable {
    let code: Int
    let msg: String?
    let success: Bool?
    let data: PayStep?

    struct PayStep: Decodable {
        let paystep: Int?
        let orderid: String?
        let accountno: String?
        let passwordMap: String?

        enum CodingKeys: String, CodingKey {
            case paystep, orderid, accountno
            case passwordMap = "passWordMp"
        }
    }
}

/// 缴费结果：**不要把「没抛错」当成成功**
enum RechargeOutcome {
    /// 订单状态已明确为已完成
    case completed(orderID: String)
    /// 支付结果未确认：可能已受理、也可能超时未处理。
    /// UI 必须显示「结果待确认（订单 xxx）」，禁止引导用户重复缴费。
    case pending(orderID: String)

    var orderID: String {
        switch self {
        case .completed(let id), .pending(let id): return id
        }
    }
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - 客户端

final class EcardClient {

    static let base = URL(string: "https://ecard.ccsut.cn")!
    static let basicAuth = "Basic Y2hhcmdlOmNoYXJnZV9zZWNyZXQ="
    static let electricityFeeItemID = "408"

    private let token: String
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    init(token: String, configuration: URLSessionConfiguration = .default,
         transport: Transport? = nil) {
        self.token = token
        if let transport { self.transport = transport }
        else {
            let cfg = configuration
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            cfg.timeoutIntervalForRequest = 20
            cfg.timeoutIntervalForResource = 30
            let session = URLSession(configuration: cfg)
            self.transport = { try await session.data(for: $0) }
        }
    }

    // MARK: 基础请求

    /// `path` 要带 `/charge` 前缀（app.js 里 axios 的 baseURL 就是 `/charge`）；
    /// 只有 `/blade-pay/**`、`/blade-auth/**` 在根。
    private func makeRequest(_ path: String,
                             method: String = "GET",
                             query: [URLQueryItem] = [],
                             form: [String: String]? = nil) -> URLRequest {
        let url = path.hasPrefix("http")
            ? URL(string: path)!
            : URL(string: path, relativeTo: Self.base)!.absoluteURL

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(Self.basicAuth,     forHTTPHeaderField: "Authorization")
        req.setValue("bearer \(token)",  forHTTPHeaderField: "synjones-auth")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let form {
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = form
                .map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }
                .joined(separator: "&")
                .data(using: .utf8)
        }
        return req
    }

    private struct CodeProbe: Decodable {
        let code: Int?
        let msg: String?
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await transport(req)
        } catch let error as EcardError {
            throw error
        } catch is CancellationError {
            throw EcardError.canceled
        } catch let error as URLError {
            if error.code == .cancelled { throw EcardError.canceled }
            throw EcardError.transport(error.localizedDescription)
        } catch {
            throw EcardError.transport(error.localizedDescription)
        }

        // A gateway may return JSON with code=500 after forwarding a payment.
        // Preserve its HTTP failure so recharge can reconcile the existing order.
        guard let http = resp as? HTTPURLResponse else { throw EcardError.http(-1) }
        if http.statusCode == 401 ||
            ([301, 302, 303, 307, 308].contains(http.statusCode) && Self.isLoginRedirect(http, from: req.url)) {
            throw EcardError.authenticationRequired
        }
        guard (200..<300).contains(http.statusCode) else { throw EcardError.http(http.statusCode) }

        // 业务异常时后端仍返回 200，错误在 body 的 code 里
        if let probe = try? JSONDecoder().decode(CodeProbe.self, from: data),
           let code = probe.code, code != 200, code != 0 {
            throw EcardError.business(code, probe.msg ?? "未知错误")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            throw EcardError.decoding(Self.responseDescription(req, http: http, data: data, error: error))
        } catch {
            throw EcardError.decoding("\(Self.operationName(req))：无法读取接口响应")
        }
    }

    /// Classify a login redirect without following it or forwarding credentials.
    /// Other redirects and forbidden responses retain their original HTTP error.
    private static func isLoginRedirect(_ response: HTTPURLResponse, from source: URL?) -> Bool {
        guard let source, let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: source)?.absoluteURL,
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        switch url.scheme?.lowercased() {
        case "https": guard url.port == nil || url.port == 443 else { return false }
        case "http": guard url.port == nil || url.port == 80 else { return false }
        default: return false
        }
        switch (url.host?.lowercased(), url.path) {
        case ("ecard.ccsut.cn", "/plat/login"),
             ("auth.ccsut.cn", "/backstage/cas/login"),
             ("zts.ccsut.cn", "/passport/v1/public/casLogin"): return true
        default: return false
        }
    }

    /// Only report fixed classifications. Never include the response body, URL
    /// query, cookies or headers: these can contain credentials and student data.
    private static func responseDescription(_ request: URLRequest, http: HTTPURLResponse,
                                            data: Data, error: DecodingError) -> String {
        let prefix = String(decoding: data.prefix(128), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            .lowercased()
        let content: String
        if data.isEmpty { content = "响应为空" }
        else if http.mimeType?.lowercased() == "text/html" || prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
            content = "接口返回了网页，未收到 JSON 数据"
        } else { content = describe(error) }

        let destination: String
        switch http.url?.host?.lowercased() {
        case "ecard.ccsut.cn":
            if http.url?.path == request.url?.path { destination = "一卡通接口" }
            else if http.url?.path.hasPrefix("/plat") == true { destination = "一卡通门户" }
            else { destination = "一卡通其他页面" }
        case "auth.ccsut.cn": destination = "CAS 登录页"
        case "zts.ccsut.cn": destination = "学校访问网关"
        default: destination = "其他地址"
        }
        let format: String
        switch http.mimeType?.lowercased() {
        case "application/json", "text/json": format = "JSON"
        case "text/html": format = "HTML"
        case "text/plain": format = "纯文本"
        case nil: format = "未声明类型"
        default: format = "其他类型"
        }
        return "\(operationName(request))：\(content)（HTTP \(http.statusCode)，\(format)，\(destination)）"
    }

    private static func operationName(_ request: URLRequest) -> String {
        switch request.url?.path {
        case "/charge/feeitem/singleFeeitem": return "加载缴费项目"
        case "/charge/feeitem/getThirdData":
            var form = URLComponents()
            form.percentEncodedQuery = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            switch form.queryItems?.first(where: { $0.name == "level" })?.value {
            case "0": return "加载校区"
            case "1": return "加载楼栋"
            case "2": return "加载房间"
            case "3": return "查询电表"
            default: return "加载房间选项"
            }
        case "/blade-pay/pay": return "提交缴费订单"
        case "/charge/pay/getpayinfo": return "查询支付结果"
        default: return "请求一卡通"
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let ctx):
            return "类型不匹配 @\(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .keyNotFound(let key, let ctx):
            return "缺少字段 \(key.stringValue) @\(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let ctx):
            return "值为空 @\(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx):
            return ctx.codingPath.isEmpty ? "响应不是有效的 JSON 数据" :
                "字段内容无法解析 @\(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return "未知解析错误"
        }
    }

    // MARK: 查询

    func feeItem(id: String = EcardClient.electricityFeeItemID) async throws -> FeeItem {
        let req = makeRequest("/charge/feeitem/singleFeeitem",
                              query: [URLQueryItem(name: "feeitemid", value: id)])
        let env: FeeItemEnvelope = try await send(req)
        guard let item = env.feeitem else {
            throw EcardError.business(env.code, env.msg ?? "没有返回 feeitem")
        }
        return item
    }

    func thirdData(feeitemID: String = EcardClient.electricityFeeItemID,
                   type: String = "select",
                   level: Int,
                   selection: [String: String] = [:]) async throws -> ThirdDataMap {
        var form = selection
        form["feeitemid"] = feeitemID
        form["type"] = type
        form["level"] = String(level)

        let req = makeRequest("/charge/feeitem/getThirdData", method: "POST", form: form)
        let env: ThirdDataEnvelope = try await send(req)
        guard let map = env.map else {
            throw EcardError.business(env.code, env.msg ?? "没有返回 map")
        }
        return map
    }

    /// level=0 → 校区
    func campuses(feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID, level: 0)
        return map.data ?? []
    }

    /// level=1 → 楼栋
    func buildings(campus: String,
                   feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID,
                                      level: 1,
                                      selection: ["campus": campus])
        return map.data ?? []
    }

    /// level=2 → 房间
    func rooms(campus: String,
               building: String,
               feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID,
                                      level: 2,
                                      selection: ["campus": campus, "building": building])
        return map.data ?? []
    }

    /// level=3 + type=IEC → 房间/电表明细
    func meterDetail(campus: String,
                     building: String,
                     room: String,
                     feeitemID: String = EcardClient.electricityFeeItemID) async throws -> MeterDetail {
        let selection: [String: String] = [
            "campus": campus, "building": building, "room": room
        ]
        let map = try await thirdData(feeitemID: feeitemID,
                                      type: "IEC",
                                      level: 3,
                                      selection: selection)

        let missing = map.missingMeterKeys
        guard missing.isEmpty else { throw EcardError.incompleteRoomDetail(missing) }
        guard let context = map.meterContext else {
            throw EcardError.incompleteRoomDetail(["map.data"])
        }
        return MeterDetail(context: context, show: map.showData ?? [:], dataType: map.dataType)
    }

    // MARK: 建单

    /// 建单。实测请求：
    /// `feeitemid=408&tranamt=10&flag=choose&source=app&paystep=0&abstract=`
    /// 再叠加 `MeterContext.formFields`（值做 JSON 编码）。
    ///
    /// - Parameters:
    ///   - thirdParty: 实测请求里有一个未解出的 `third_party` 值，先留空。
    ///   - expectedRoom: 传了就会校验 `context.houseID` 与它一致，
    ///     防止"切换房间后仍用上一间房的上下文"造成充错房间。
    func createOrder(amount: Decimal,
                     context: MeterContext,
                     thirdParty: String? = nil,
                     expectedRoom: String? = nil,
                     feeitemID: String = EcardClient.electricityFeeItemID) async throws -> CreatedOrder {
        guard amount > 0 else { throw EcardError.orderRejected("金额必须大于 0") }
        if let expectedRoom, context.houseID != expectedRoom {
            throw EcardError.orderRejected("房间上下文与所选房间不一致")
        }

        var form: [String: String] = [
            "feeitemid": feeitemID,
            "tranamt":   NSDecimalNumber(decimal: amount).stringValue,
            "flag":      "choose",
            "source":    "app",
            "paystep":   "0",
            "abstract":  ""
        ]
        if let thirdParty { form["third_party"] = thirdParty }
        context.formFields.forEach { form[$0.key] = $0.value }

        let req = makeRequest("\(Self.base.absoluteString)/blade-pay/pay",
                              method: "POST", form: form)
        let env: CreateOrderEnvelope = try await send(req)

        // 明确要求 success=true 且拿到订单号，不能只看有没有 orderid
        guard env.code == 200, env.success == true else {
            throw EcardError.orderRejected(env.msg ?? "success 不为 true")
        }
        guard let created = env.data,
              let orderID = created.orderid,
              !orderID.isEmpty
        else {
            throw EcardError.orderRejected("响应里没有订单号")
        }
        return created
    }

    func payInfo(orderID: String) async throws -> PayInfoEnvelope {
        let req = makeRequest("/charge/pay/getpayinfo",
                              query: [URLQueryItem(name: "orderid", value: orderID)])
        return try await send(req)
    }

    /// 订单状态。1 = 已完成
    func orderStatus(orderID: String) async throws -> Int? {
        try await payInfo(orderID: orderID).order?.status
    }

    // MARK: 支付

    /// 支付（paystep=2）。实测请求：`paytypeid=69&payType=CARDTSM&paystep=2&orderid=…`
    func pay(orderID: String,
             payTypeID: String,
             payTypeCode: String) async throws -> PayResultEnvelope {
        let form: [String: String] = [
            "paytypeid": payTypeID,
            "payType":   payTypeCode,
            "paystep":   "2",
            "orderid":   orderID
        ]
        let req = makeRequest("\(Self.base.absoluteString)/blade-pay/pay",
                              method: "POST", form: form)
        let env: PayResultEnvelope = try await send(req)
        guard env.code == 200, env.success != false else {
            throw EcardError.business(env.code, env.msg ?? "支付失败")
        }
        return env
    }

    /// 建单 → 挑余额通道 → 支付 → **再确认订单状态**
    ///
    /// 通道必须同时满足：
    ///   1. 是 ACCOUNT / CARD 类余额通道
    ///   2. 明确免密（`nopassword == "0"`）
    /// 不满足就抛错，绝不回退到硬编码通道。
    func rechargeElectricity(amount: Decimal,
                             context: MeterContext,
                             expectedRoom: String? = nil,
                             feeitemID: String = EcardClient.electricityFeeItemID,
                             beforePayment: (@MainActor (String) throws -> Void)? = nil) async throws -> RechargeOutcome {
        let order = try await createOrder(amount: amount,
                                          context: context,
                                          expectedRoom: expectedRoom,
                                          feeitemID: feeitemID)
        guard let orderID = order.orderid else {
            throw EcardError.orderRejected("响应里没有订单号")
        }

        let balanceChannels = order.payList?.filter { $0.isInternalBalance } ?? []
        guard !balanceChannels.isEmpty else { throw EcardError.paymentChannelUnavailable }

        // 一次筛出「余额 + 免密 + id/code 完整」，
        // 不能先取第一个再判免密 —— 第一个要密码、第二个免密时会误拒。
        let completeChannels = balanceChannels.filter {
            $0.id?.isEmpty == false && $0.code?.isEmpty == false
        }
        guard !completeChannels.isEmpty else { throw EcardError.paymentChannelUnavailable }
        guard let channel = completeChannels.first(where: { $0.isPasswordFree }) else {
            throw EcardError.passwordRequired
        }
        guard let payTypeID = channel.id, let payTypeCode = channel.code else {
            throw EcardError.paymentChannelUnavailable
        }

        guard !Task.isCancelled else { throw EcardError.canceled }
        // The caller must finish its durable recovery checkpoint before debit.
        // A checkpoint failure is outside the uncertain-payment catch below.
        if let beforePayment { try await beforePayment(orderID) }
        do {
            _ = try await pay(orderID: orderID, payTypeID: payTypeID, payTypeCode: payTypeCode)
        } catch {
            // Neither HTTP nor business failure proves the debit had no effect.
            // Retain the known order and reconcile; never create/pay another one.
            if let status = try? await orderStatus(orderID: orderID), status == 1 {
                return .completed(orderID: orderID)
            }
            return .pending(orderID: orderID)
        }

        // 只有订单状态明确为「已完成」才算成功
        if let status = try? await orderStatus(orderID: orderID), status == 1 {
            return .completed(orderID: orderID)
        }
        return .pending(orderID: orderID)
    }
}

// MARK: - 金额工具

extension Decimal {
    var ecardAmountText: String {
        let n = NSDecimalNumber(decimal: self)
        return n.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 2,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )).stringValue
    }

    func kWh(pricePerKWh: Decimal?) -> Decimal? {
        guard let price = pricePerKWh, price > 0 else { return nil }
        return self / price
    }
}

// MARK: - 松散 JSON

enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool)
    case object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let d): return NSDecimalNumber(value: d).stringValue
        case .bool(let b):   return b ? "true" : "false"
        default:             return nil
        }
    }
}
