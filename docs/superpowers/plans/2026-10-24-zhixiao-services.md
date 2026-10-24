# 智校 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 App 新增「智校」导航，提供校园只读查询和官方办理入口。

**Architecture:** 独立 ehall 查询客户端与一卡通平台认证/查询客户端复用当前 TGC；SwiftUI 模块承载记录、余额、分页和官方 WebView。对新增业务数据采用最小展示模型与内存生命周期，复用 CookieJar 的账号代数约束。

**Tech Stack:** Swift 6、SwiftUI、WebKit、URLSession、iOS 26，无新增第三方依赖。

**Spec:** `docs/superpowers/specs/2026-10-24-zhixiao-design.md`

## Global Constraints

- 原生网络层只实现已验证的查询接口。请假申请、充值、挂失、电表缴费的办理均打开官方 WebView。
- `reference/out/` 是敏感输入，只允许本地解析字段和类型。禁止复制进工作树、打印原始内容、入库或上传。
- 新增响应不持久化、不写 URLCache、不进入日志或错误正文。
- 退出、换号、取消后丢弃迟到结果；新模块的会话凭证不得恢复旧账号数据。
- 不调整现有页面业务、布局、动画或底栏滚动策略。

## Review Focus

- 401 连续返回时只重试一次，不能无限认证。
- 换号或退出时旧请求不能重新填充记录或 token。
- 缺失字段、不同 envelope、错误数据不得变成余额零或空列表。
- 银行卡、身份证和手机号混入自由文本时不得显示原文。
- 流水分页失败不能跳页或丢失已加载数据；金额不根据正负猜收支。

---

### Task 1: 查询模型与隐私边界

**Files:** Create `ios/CCSUT/CampusModels.swift`; create `ios/Tests/CampusRegressionTests.swift`.

**Interfaces:** 产生请假分页、离返校记录、卡片总览和流水分页的 Decodable 展示模型，以及脱敏和整数分格式化工具。只声明需要读取的字段，忽略原始敏感字段；错误不携带响应。

- [ ] 编写合成数据断言：`data.list`、两种 returnschool envelope、`data.card[]`、`data.records`、缺失余额报错、0/1/101 分精确显示、自由文本号码脱敏。
- [ ] 在可用 Swift 工具链运行测试并保留真实失败；平台不可用时明确记为未运行，不伪造 RED。
- [ ] 实现模型与工具，使同一组断言通过。

### Task 2: ehall 子系统认证与只读客户端

**Files:** Create `ios/CCSUT/CampusAPI.swift`; extend `ios/Tests/CampusRegressionTests.swift`.

**Interfaces:** `leaveRecords(page:size:)`、`returnRecords()`、`departureRecords()`；内部缓存仅为当前 CookieJar 代数的 validate_full 身份，业务 body 使用该 userId。

- [ ] 编写 URLProtocol 合成响应测试：先 validate、身份参数、401 重新 validate 后重试一次、第二次 401 结束、403/业务错误/解码失败独立报错、退出后拒绝迟到响应。
- [ ] 实现限定官方学校域的逐跳认证，HTTP 学校跳转提升 HTTPS，Cookie 按域/路径发送；设置 ephemeral session 与无缓存。
- [ ] 实现三个查询白名单和独立 envelope 校验，不添加任意业务写入方法；运行对应回归。

### Task 3: berserker 认证与卡片/流水查询

**Files:** Create `ios/CCSUT/CampusEcardBridge.swift`, `ios/CCSUT/CampusEcardAPI.swift`; extend regression tests.

**Interfaces:** 主线程 bridge 提供需要挂载的 `webView`，按当前账号取得平台认证；客户端提供 `cards()`、`turnover(page:size:)`。具体 token 存储/请求头先核实官方前端，仅固定可信 origin 可提供 token。

- [ ] 核实官方平台认证实现，避免 charge-app token、账号加密算法或支付协议重写。
- [ ] 编写并验证：账号不符拒绝 token、过期 token 不复用、取消/换号丢弃迟到结果、HTTP/业务认证错误、卡片内层 retcode、流水分页失败保持页码和既有数据。
- [ ] 实现官方 WebView 引导、当前会话 Cookie 同步、必要平台凭证的内存生命周期与两个 GET 查询；不记录 token/请求正文/响应正文。

### Task 4: 智校页面与官方 WebView

**Files:** Create `ios/CCSUT/CampusView.swift`, `ios/CCSUT/CampusRecordViews.swift`, `ios/CCSUT/CampusEcardView.swift`, `ios/CCSUT/CampusWebView.swift`; modify `ios/CCSUT/CCSUTApp.swift` and `ios/CCSUT.xcodeproj/project.pbxproj`.

**Interfaces:** 新增 `.campus` 页签，标签「智校」；四个入口。每个记录页面单独管理加载/刷新/错误，WebView 复用 WebStore。

- [ ] 按现有风格实现页面、空状态、错误重试、请假及流水分页，登录引导 WebView 保持实际挂载。
- [ ] 将请假申请、充值、挂失、电表缴费按钮指向已核实的官方页面；电表使用 `/charge/feeitem/toAppitem?feeitemid=408`。
- [ ] 将新 Swift 文件注册到 Xcode Sources；不调用现有 EcardClient 建单/支付方法。
- [ ] 检查账号切换、取消、刷新与分页交错、Dynamic Type、六页签在 iPhone 上的系统呈现；后两项需 Xcode/设备验证并单列状态。

### Task 5: 验证与交付

**Files:** Modify `.github/workflows/session-tests.yml` if required for standalone campus regressions; update `ios/README.md` with module and privacy behavior.

- [ ] 运行现有 6 项 JS 登录回归和 Swift 会话回归；执行新增合成数据测试。
- [ ] 在 macOS/Xcode 编译 App，记录确切提交对应结果；本地无 Xcode 时不称为构建通过。
- [ ] 检查 `git diff --check`、变更白名单、敏感样本未入库、新增代码不输出正文或实现提交协议。
- [ ] 做整支分支审查，修复实质问题，报告代码、测试、构建和真机验证的各自状态。
