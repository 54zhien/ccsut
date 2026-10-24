# 校园 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 用户已明确范围，在当前聊天直接执行，不重复请求批准。

**Goal:** 新增校园页，查询请假与节假日离返校记录，迁移既有电表缴费入口。

**Architecture:** Foundation 只读客户端通过 CookieJar 适配器复用 TGC；SwiftUI 沿用既有页面 chrome，直接复用 EcardPaymentView。

**Tech Stack:** Swift 6、SwiftUI、WebKit、Foundation、iOS 26，无新增依赖。

**Spec:** docs/superpowers/specs/2026-10-24-zhixiao-design.md

## Global Constraints

- 首版只有请假、节假日离返校、电表缴费，一卡通余额/流水延期。
- 新接口只读，申请进入官方 WebView。电表只迁移入口，既有页面/认证/支付不变。
- reference/out 原始敏感信息禁止输出、入库和上传。
- 新业务数据仅在内存，号码脱敏，错误不含正文。
- 换号、退出和取消后拒绝迟到结果，不修改已有页面效果。

## Review Focus

- 连续401仅重试一次；403/业务错误不误判为成功或空数据。
- 三个查询使用 validate_full.userId，account 匹配当前账号。
- 退出、换号、取消后不保存旧凭证或展示旧数据。
- 自由文本中的手机号、身份证、银行卡不得明文显示。
- 刷新/分页失败保留旧数据，重试不跳页。

### Task 1: 模型与隐私

**Files:** 新增 CampusModels.swift、CampusModelTests.swift。

**Interfaces:** CampusDecoder.leavePage(_:)、travelRecords(_:)；CampusPrivacy.redact(_:)；CampusPageState.apply(_:reset:)。

- [ ] 合成数据先测 envelope、缺失数据、脱敏、分页，观察 RED。
- [ ] 实现最小展示模型、固定错误、原子分页，运行同组测试 GREEN。
- [ ] 验证命令：swiftc -parse-as-library ios/CCSUT/CampusModels.swift ios/Tests/CampusModelTests.swift -o <scratch>/campus-model-tests；运行产物，预期全部 PASS。

### Task 2: 子系统会话与查询

**Files:** 新增 CampusAPI.swift、CampusSession.swift、CampusAPITests.swift。

**Interfaces:** CampusClient.leaveRecords(page:size:)、travelRecords(kind:)；CampusSessionCredentials 适配 CookieJar；注入 HTTP boundary。

- [ ] 先测认证、userId、401一次重试、403、无效响应、HTTPS升级、Cookie、账号不符、迟到响应，观察 RED。
- [ ] 实现 ephemeral 传输、逐跳认证、身份缓存、三个查询，观察 GREEN。
- [ ] 新建真实 CookieJar 适配器，不修改已有网络层。
- [ ] 验证命令：swiftc -parse-as-library ios/CCSUT/CampusModels.swift ios/CCSUT/CampusAPI.swift ios/Tests/CampusAPITests.swift -o <scratch>/campus-api-tests；运行产物，预期全部 PASS。

### Task 3: 页面与入口迁移

**Files:** 新增 CampusView.swift、CampusRecordViews.swift、CampusWebView.swift、CampusRecordsModel.swift；修改 CCSUTApp.swift、AcademicView.swift、project.pbxproj；新增必要的模型测试。

**Interfaces:** 第三个页签 .campus；三个服务目的地，缴费直接 EcardPaymentView()。

- [ ] 先覆盖刷新、取消和部分失败，观察 RED，再实现记录模型 GREEN。
- [ ] 沿用服务卡片和 Nagi chrome，实现记录页与官方申请 WebView。
- [ ] 从教务移除缴费入口，既有缴费四个 Swift 文件与2483a48保持一致。
- [ ] 注册 Xcode Sources，增加 DEBUG 合成预览，验证导航与布局。

### Task 4: 验证与审查

**Files:** 修改 .github/workflows/session-tests.yml、ios/README.md，必要的预览配置。

- [ ] 接入新增 Foundation 回归，运行本地 Swift 和既有 JS 测试，检查本次增量 diff。
- [ ] 在任务分支执行 macOS/Xcode 编译，记录确切提交；不修改其他任务分支，不合并 main。
- [ ] fresh context 全分支审查，修复实质问题并验证。
- [ ] 分别报告测试、编译与真机验收状态。
