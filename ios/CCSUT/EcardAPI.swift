//
//  EcardAPI.swift
//  CCSUT
//
//  一卡通缴费（新中新 Synjones 缴费大厅 charge-app 4.0.107 / BladeX 后端）
//
//  与教务系统完全不同的一套：
//    - 鉴权不是 Cookie，而是两个固定 Header + bearer token
//    - 没有签名、没有加密请求体
//    - 业务接口在 /charge/**，建单与支付在 /blade-pay/pay
//    - 校外被 aTrust 零信任网关挡住，校内直连可达
//
//  token 来源：GET /charge/feeitem/toAppitem?feeitemid=408 → 302 的 Location 里带 ?token=
//  （见 EcardTokenBridge.swift，用 WKWebView 在跳转瞬间截获）
//
//  已实测：建单 → payList 直接返回「卡账户 CARDTSM」→ 支付 POST paystep=2 完成
//

import Foundation

// MARK: - 错误

enum EcardError: LocalizedError {
    case business(Int, String)
    case http(Int)
    case decoding(String)
    case noToken
    case canceled

    var errorDescription: String? {
        switch self {
        case .business(let code, let msg): return "缴费接口返回错误 [\(code)] \(msg)"
        case .http(let code):              return "网络错误 HTTP \(code)"
        case .decoding(let what):          return "数据解析失败：\(what)"
        case .noToken:                     return "未获取到缴费凭证，请重新登录"
        case .canceled:                    return "已取消"
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
    /// 电控实现类，实测 IECWServiceImpl
    let implInterface: String?
    let feeitemImplBean: FeeItemImpl?

    enum CodingKeys: String, CodingKey {
        case feeitemid, name, flag, view
        case billingUnit   = "billing_unit"
        case maxmoney, daymaxmoney, dayout
        case implInterface = "impl_interface"
        case feeitemImplBean
    }

    // flag[4] → 0 选择模式 / 1 输入模式 / 4 IEC 电表模式
    // flag[7] → 是否需要输入金额
    // flag[9] → 是否展示「信息」区块（"2" 表示需要先改密码）
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
    /// 电控厂商，实测「威胜电控」
    var vendorName: String? { feeitemImplBean?.implname }
}

struct FeeItemImpl: Decodable {
    let implname: String?
    let code: String?
}

// MARK: - 级联字典（校区 → 楼栋 → 房间）

struct ThirdDataEnvelope: Decodable {
    let code: Int
    let msg: String?
    let map: ThirdDataMap?
}

struct ThirdDataMap: Decodable {
    /// 级别定义：campus(1) → building(2) → room(3)
    let total: [ThirdLevel]?
    /// 当前层可选项；value 是 32 位 hash，不是明文房号
    let data: [ThirdOption]?
    /// 第三级（选中房间后）data 是对象，这里保留原始字典
    let detail: [String: JSONValue]?
    /// 展示用文案，实测 {"房间信息":"…","表类型":"电表","剩余金额":"-1150.093"}
    let showData: [String: String]?
    /// 实测 "IEC"
    let dataType: String?

    enum CodingKeys: String, CodingKey { case total, data, showData, dataType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent([ThirdLevel].self, forKey: .total)
        showData = try c.decodeIfPresent([String: String].self, forKey: .showData)
        dataType = try c.decodeIfPresent(String.self, forKey: .dataType)

        if let list = try? c.decodeIfPresent([ThirdOption].self, forKey: .data) {
            data = list
            detail = nil
        } else if let obj = try? c.decodeIfPresent([String: JSONValue].self, forKey: .data) {
            data = nil
            detail = obj
        } else {
            data = nil
            detail = nil
        }
    }

    /// 从 detail 里提取 MeterContext（字段名与建单请求一致）
    var meterContext: MeterContext? {
        guard let d = detail else { return nil }
        func v(_ k: String) -> String? { d[k]?.stringValue }
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
}

struct ThirdOption: Decodable {
    let name: String
    let value: String
}

// MARK: - 房间 / 电表上下文

/// 建单时服务端要求把房间与电表信息原样回传（实测字段）。
///
/// 注意：实测请求里每个值都是 **JSON 编码后的字符串**（带外层双引号），
/// 例如 `house_no="208"`，所以 `formFields` 会统一做 JSON 编码。
struct MeterContext {
    var avgPrice: String?          // 电价，实测 "0.619" 元/度
    var buyTime: String?
    var ctpt: String?
    var customerName: String?      // "17栋南-208"
    var customerNo: String?        // "17栋南-208"
    var freeBalance: String?       // 卡余额，实测 "59.06"
    var houseAddr: String?         // "长沙工业学院17栋南208"
    var houseID: String?           // "0182AE9EAE78619594D5A9038B1D54"
    var houseNo: String?           // "208"
    var meterBalance: String?
    var meterBalanceTime: String?
    var meterID: String?           // "318031214406D2F8A0D715541F081F7D"
    var meterNo: String?           // "59910060428"
    var meterStatus: String?
    var meterType: String?         // "1"
    var payType: String?           // "0"
    var payid: String?
    var sysId: String?             // 实测 "null"，原样回传
    var walletBalance: String?     // 电表钱包余额，实测 "343.43028"
    var sno: String?               // 学号
    var userName: String?
    var myCustomInfo: String?      // "房间:长沙工业学院 17栋南 208"

    /// 电价（元/度），用于把金额换算成电量给用户看
    var pricePerKWh: Decimal? { avgPrice.flatMap { Decimal(string: $0) } }
    /// 电表余额（元）
    var walletAmount: Decimal? { walletBalance.flatMap { Decimal(string: $0) } }
    /// 卡余额（元）
    var cardAmount: Decimal? { freeBalance.flatMap { Decimal(string: $0) } }

    /// 建单 form 里的上下文字段（每个值做 JSON 编码，带外层引号）
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
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// 第三级返回的完整明细：上下文 + 展示文案
struct MeterDetail {
    let context: MeterContext
    /// {"房间信息":"长沙工业学院17栋南101","表类型":"电表","剩余金额":"-1150.093"}
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
    /// 建单后服务端直接给到下一步：实测 2
    let paystep: Int?
    /// 支付截止时间，实测 "2026-10-24 01:48:49"
    let payExpDate: String?
    /// 建单响应里的可用支付方式（snake_case 一套）
    let payList: [OrderPayChannel]?
}

struct OrderPayChannel: Decodable {
    let id: String?
    let name: String?
    let code: String?          // 实测 "CARDTSM"
    let icon: String?
    let nopassword: String?    // "0"
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
        // 建单响应是 snake_case（pay_type_name / pay_type_code），
        // getpayinfo 是 camelCase（name / code），这里两套都认
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decodeIfPresent(String.self, forKey: .nameSnake)
        code = try c.decodeIfPresent(String.self, forKey: .code)
            ?? c.decodeIfPresent(String.self, forKey: .codeSnake)
    }

    /// 卡余额 / 账户余额类通道：可在 App 内直接完成
    var isInternalBalance: Bool {
        let c = (code ?? "").uppercased()
        return c.hasPrefix("ACCOUNT") || c.hasPrefix("CARD")
    }
    /// 免密
    var isPasswordFree: Bool { nopassword == "0" }
}

/// GET /charge/pay/getpayinfo 的返回（camelCase 一套）
struct PayInfoEnvelope: Decodable {
    let code: Int?
    let msg: String?
    let payList: [PayChannel]?
}

struct PayChannel: Decodable {
    let payid: Int?
    let name: String?
    let code: String?          // 实测 "CARDTSM"
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

/// 支付那一步的返回
struct PayResultEnvelope: Decodable {
    let code: Int
    let msg: String?
    let success: Bool?
    let data: PayStep?

    struct PayStep: Decodable {
        let paystep: Int?
        let orderid: String?
        let accountno: String?
        /// 需要输入支付密码时服务端会回一个映射，用于后续校验
        let passwordMap: String?

        enum CodingKeys: String, CodingKey {
            case paystep, orderid, accountno
            case passwordMap = "passWordMp"
        }
    }
}

// MARK: - 客户端

/// 一个 token 对应一个实例；token 有效期以 JWT exp 为准（实测约 2 个月）
final class EcardClient {

    static let base = URL(string: "https://ecard.ccsut.cn")!

    /// 前端硬编码的客户端凭证（bundle 原文，不是用户凭证）
    private static let basicAuth = "Basic Y2hhcmdlOmNoYXJnZV9zZWNyZXQ="

    /// 电表缴费的固定项目号
    static let electricityFeeItemID = "408"

    private let token: String
    private let session: URLSession

    init(token: String, configuration: URLSessionConfiguration = .default) {
        self.token = token

        let cfg = configuration
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: 基础请求

    /// `path` 要带 `/charge` 前缀：app.js 里 axios 的 baseURL 就是
    /// `https://ecard.ccsut.cn/charge`；只有 `/blade-pay/**`、`/blade-auth/**` 在根。
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
        let (data, resp) = try await session.data(for: req)

        // 业务异常时后端仍返回 200，错误在 body 的 code 里
        if let probe = try? JSONDecoder().decode(CodeProbe.self, from: data),
           let code = probe.code, code != 200, code != 0 {
            throw EcardError.business(code, probe.msg ?? "未知错误")
        }
        guard let http = resp as? HTTPURLResponse else { throw EcardError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw EcardError.http(http.statusCode) }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EcardError.decoding(String(describing: error))
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

    /// level 1 → 楼栋；level 2 + building → 房间；level 3 + building + room → 房间/电表明细
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

    /// 校区列表（level=0）
    /// 实测返回 `[{"name":"长沙工业学院","value":"64245573A76997B39B273F05932AE43D"}]`，
    /// 这个 value 后面每一级都要带上。
    func campuses(feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID, level: 0)
        return map.data ?? []
    }

    /// 楼栋（level=1 + campus）
    func buildings(campus: String,
                   feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID,
                                      level: 1,
                                      selection: ["campus": campus])
        return map.data ?? []
    }

    /// 房间（level=2 + campus + building）
    func rooms(campus: String,
               building: String,
               feeitemID: String = EcardClient.electricityFeeItemID) async throws -> [ThirdOption] {
        let map = try await thirdData(feeitemID: feeitemID,
                                      level: 2,
                                      selection: ["campus": campus, "building": building])
        return map.data ?? []
    }

    /// 房间/电表明细（level=3 + type=IEC + campus + building + room）
    ///
    /// 实测请求：`type=IEC&level=3&campus=<hash>&building=<hash>&room=<hash>`
    /// 返回 `map.data` 是对象（→ MeterContext），`map.showData` 是可直接渲染的文案。
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
        guard let context = map.meterContext else {
            throw EcardError.business(-1, "没有返回房间明细")
        }
        return MeterDetail(context: context,
                           show: map.showData ?? [:],
                           dataType: map.dataType)
    }

    // MARK: 建单

    /// 建单。实测请求：
    /// `feeitemid=408&tranamt=10&flag=choose&source=app&paystep=0&abstract=&third_party=…`
    /// 再叠加 `MeterContext.formFields`（房间与电表明细，值做 JSON 编码）。
    ///
    /// - Parameters:
    ///   - amount: 金额（元），上限见 `FeeItem.maxAmount` / `dayMaxAmount`
    ///   - context: 第三级 getThirdData 带回的房间/电表上下文
    ///   - thirdParty: 实测里有一个未解出的 `third_party` 值，先留空
    func createOrder(amount: Decimal,
                     context: MeterContext,
                     thirdParty: String? = nil,
                     feeitemID: String = EcardClient.electricityFeeItemID) async throws -> CreatedOrder {
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
        guard let created = env.data, let orderID = created.orderid, !orderID.isEmpty else {
            throw EcardError.business(env.code, env.msg ?? "建单失败")
        }
        _ = orderID
        return created    }

    /// 订单 + 可用支付方式（getpayinfo）
    func payInfo(orderID: String) async throws -> PayInfoEnvelope {
        let req = makeRequest("/charge/pay/getpayinfo",
                              query: [URLQueryItem(name: "orderid", value: orderID)])
        return try await send(req)
    }

    // MARK: 支付

    /// 走「卡账户 / 卡余额」通道付掉。
    /// 实测请求：`paytypeid=69&payType=CARDTSM&paystep=2&orderid=…`
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
        return try await send(req)
    }

    /// 便捷：建单 → 自动挑「卡余额」通道 → 支付
    ///
    /// 通道优先取建单响应里的 `payList`（实测返回 `CARDTSM` 卡账户），
    /// 取不到才退回 `69 / CARDTSM`（实测值）。
    func rechargeElectricity(amount: Decimal,
                             context: MeterContext) async throws -> PayResultEnvelope {
        let order = try await createOrder(amount: amount, context: context)
        guard let orderID = order.orderid else {
            throw EcardError.business(-1, "没有拿到订单号")
        }

        let channel = order.payList?.first(where: { $0.isInternalBalance })
        let payTypeID = channel?.id ?? "69"
        let payTypeCode = channel?.code ?? "CARDTSM"

        return try await pay(orderID: orderID,
                             payTypeID: payTypeID,
                             payTypeCode: payTypeCode)
    }
}

// MARK: - 金额工具

extension Decimal {
    /// 接口要的两位小数文本
    var ecardAmountText: String {
        let n = NSDecimalNumber(decimal: self)
        return n.rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .plain, scale: 2,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )).stringValue
    }

    /// 按电价换算电量（度），用于「充 10 元 ≈ 16.2 度」这类提示
    func kWh(pricePerKWh: Decimal?) -> Decimal? {
        guard let price = pricePerKWh, price > 0 else { return nil }
        return self / price
    }
}

// MARK: - 松散 JSON（第三级返回结构未完全定型时兜底）

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
