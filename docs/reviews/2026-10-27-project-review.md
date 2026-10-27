# 项目审查 · 2026-10-27

基线：`main` 的 `e54ba96398323aba110cf7595ded95c54bfe7ced`。本次检查原生 iOS 的认证、网络、教务、校园表单、电费、共享界面、工程与 CI，并检查历史 Flutter 原型和协议脚本。没有连接学校写接口，没有提交真实申请、选退课或付款。

本报告是源码审查和离线验证记录，不是“没有其他问题”的保证。下列行为问题尚未修复；本分支只清理已确认不可达的代码、无用注释及过期文档。

## 优先处理

### 1. P1：关闭表单会丢失未知提交的核对状态

位置：`ios/CCSUT/CampusFormView.swift` 的初始化、关闭与 `onDisappear`；`CampusFormModel.swift` 的 `submit`、`stop`；`CampusFormsAPI.swift` 的提交去重。

请求超时后，模型进入 `.unknown` 并保留 `pending`，供“查询提交结果”使用。但关闭仅在 `.submitting` 时被限制，离开页面会调用 `stop()` 清掉 `pending`；再次进入又创建新的 `CampusClient`，原来的 `formAttemptIDs` 也随之失效。因此用户在不知道第一次是否成功时，可重新提交同一申请。这不是自动重试，但会失去现有界面的防重复保护。

建议把未决提交的最小核对信息提升到账号／会话级别，跨页面保留；在解决前阻止同一意图再次发送。不要为了恢复状态持久化整份敏感表单。增加“超时 → 关闭 → 重开 → 再提交”的回归，确认先查结果且不出现第二次 POST。**代码路径已确认，未在生产环境制造超时。**

### 2. P2：电费调用没有启用已有的房间一致性校验

位置：`EcardPaymentModel.submit` 调用 `rechargeElectricity`；`EcardAPI.createOrder` 的 `expectedRoom`。

模型校验了当前选择与确认快照一致，但没有传 `expectedRoom`，所以底层用于核对 `MeterContext.houseID` 的保护未启用。如果服务端电表上下文与选择的房间不一致，建单会采用上下文中的房间。

建议先用协议样本确认房间选项值与 `house_id` 的同一性，再传入确认快照的房间 ID，并加入不一致时零建单、零扣款测试。**参数遗漏已确认；没有证据表明目前发生过充错房间，不把条件性风险当作已发生事故。**

### 3. P2：Cookie 删除未同步到复用的 WebKit store

位置：`SessionStore.performRefresh`、`CookieJar.upsert`、`WebSessionCookies.restore(.replaceExisting)`。

原生 jar 会移除过期 Cookie，但 `replaceExisting` 只写入目标集合、检查其存在，不删除 WebKit 中已不在集合里的学校 Cookie。同账号刷新复用 store；服务端撤销 Cookie 后，后续 WebKit 认证回退仍可能携带旧值。

建议在明确的学校域范围内同步删除缺失身份，保留取消与账号代数检查，测试服务端 tombstone 后原生和 WebKit 均不存在该 Cookie。**同步缺口已确认，实际影响依赖服务端撤销行为。**

### 4. P2：Keychain 写入失败被吞掉

位置：`Session.swift` 的 `Keychain.save`、`CookieJar.persist`。

`SecItemUpdate` 和 `SecItemAdd` 的失败状态没有向上传递。当前内存会话可正常使用，但持久化失败后，下次启动可能恢复旧会话或丢失登录状态，调用方无法判断保存是否成功。

建议返回明确的持久化结果，区分“本次可用”和“已可靠保存”，并通过可注入的 Keychain 操作测试失败分支。**错误处理缺口已确认，未在真机模拟 Keychain 故障。**

### 5. P2：加载下一页时的下拉刷新会被合并掉

位置：`CampusRecordsModel.loadLeave(reset:)` 开头的 `leaveCompletion` 分支。

加载更多尚未结束时，刷新只等待旧请求完成就返回，不会重新请求第一页。现有重叠测试验证等待，没有验证刷新意图最终执行。

建议记录待处理的 reset，在分页结束后执行一次；测试请求页码和最终列表，而不是只检查没有并发请求。**代码路径已确认。**

### 6. P2：考试日期展示使用设备时区

位置：`ExamView.dateText`、`ExamRow` 的 `visibleDateText`。

`ExamItem.startDate` **已经指定上海时区**，不能把解析说成完全依赖设备时区。但这两个日期格式化器仅设置 `zh_CN` locale，未指定时区；在美洲等时区，上海上午考试可能显示成前一天，而原始考试时间文字仍保留学校时间。

建议统一学校日期的 Gregorian calendar 与上海时区，并增加跨时区日期展示测试。**格式化缺口已确认，未做模拟器跨时区验收。**

## 需要明确边界的风险

| 范围 | 证据与影响 | 建议 |
| --- | --- | --- |
| 教务重定向 | `APIClient.transportURL` 接受任意 HTTPS `*.ccsut.cn`。异常跳转到兄弟子域时，宽域 Cookie 也可能被发送。不是已证明的凭证外泄。 | 把允许的认证链收敛到实际需要的 host，并测试未知 HTTPS 子域在发请求前被拒绝。 |
| 请假结果核对 | `CampusFormsAPI.formRecords` 只读第一页 100 条。目标记录在后页时，核对可能一直无法确定。现有行为不会因此自动重发。 | 有界分页，覆盖匹配项在后页的测试；结合服务端排序约定评估优先级。 |
| Flutter 原型 | `shell/lib/main.dart:283` 对服务端证书挑战无条件 `PROCEED`；导航回调忽略 `_onOverride` 结果并始终 `ALLOW`。 | 不应作为可用客户端发布；恢复系统证书验证，并实现真实的导航策略。原生 iOS 不走此代码。 |
| 历史请求脚本 | `tools/keepalive.mjs`、`tools/probe-score.mjs` 按 `domain.includes('ccsut.cn')` 拼接 Cookie，不按请求 host/path/过期时间匹配。 | 使用正确的 cookie jar，避免把其他学校子系统凭证发给教务 host。 |
| 历史写脚本 | `_e2e.mjs` 包含真实 `xsdXkV2`／`xsdTkV2`，不是隔离测试。 | 移入明确的实验区并设置默认拒绝写入的开关；当前不运行，也不把它纳入 CI。 |
| 仓库使用许可 | 未找到 LICENSE。公开仓库本身不代表他人拥有任意再分发许可。 | 由维护者选择许可，并核实品牌素材权限；本次不代为决定。 |

## 已完成的清理

- 删除回退后不可达的 `LeaveTicketWalletView`、`LeaveTicketPrinter`、`LeaveTicketReceipt`、`VintageAmountDrum`，同步移除工程注册和仅服务旧收据的测试步骤。
- 删除未使用的机械电表图片，原文件 2,522,435 字节；当前 `MeterAmount` 和缴费页面保留。
- 删除旧 `ScheduleParser`、重复的 `scheduleXhid` 提取、未使用的选课原始响应诊断接口及只写不读的 `lastTrace`。当前课表转换及 `ScheduleCodec` 保留。
- 删除文件名复述、逐步翻译代码、旧账号实测数量等注释；保留账号代数、提交不重试、付款前落盘、UIKit／WebKit 限制及 Apple 文档引用。
- 重写首页和 iOS 开发指南，纠正“永久免登录”、固定真实账号数据量及工具链／语言模式混淆。截图来自 `60f1714` 的合成数据模拟器验证，与合并基线界面一致。

## 结构优化顺序

1. **先收拢业务状态。** 未决申请应有独立于页面生命周期的归属。电费现有持久化与恢复边界可作为参照，但不要把两个系统硬合成同一个客户端。
2. **再拆大文件。** `ElectiveView` 混合视图、加载状态与 DEBUG fixture；可先移出 fixture，再提取可离线测试的加载模型。`EcardAPI` 可按传输、响应模型、订单流程分文件，保留现有明确的扣款关口。
3. **删除未消费的状态。** `cookieSummary`、`cookieNames`、`lastCookieCount`、`CookieJar.names/fingerprint` 和部分 `FeeItem` 便捷属性暂无调用方。`quickAmounts` 被计算但界面使用固定金额，先确定是否应遵循服务端配置，再决定接线或删除，不能把产品选择藏在“清理”里。
4. **收拾实验目录。** 根目录大量 `_*.mjs` 混淆测试与真实请求。按只读调查、写入实验、可重复 fixture 工具分开，给写入设置硬性 opt-in；不建议直接删掉仍有调查价值的历史代码。
5. **整理 CI 命名。** `leave-wallet-preview.yml` 实际验证普通校园记录页，仍绑定旧票夹分支名。保留有效覆盖，后续统一命名和触发范围；不要因票夹删除而把记录页测试也删掉。

本次不重写共享导航、下拉刷新动画或已确认的页面布局。此类代码中的平台解释可能较长，但有实际维护价值，不能仅因篇幅而视为“AI 味”。

## 验证记录

- 本地 Node：登录脚本、CAS、校园隐私、仓库隐私共 24 项通过。
- 本地 Swift：电费离线测试 runner 通过；Windows 的平台替身验证不等于真实 WebKit 验证。
- 清理涉及的 Swift 文件执行语法检查；删除符号检查覆盖应用、测试、工程文件与工作流。
- 最终源码提交 `eb828a0` 的 [macOS 回归与模拟器编译](https://github.com/54zhien/ccsut/actions/runs/40446409568)、[Release 编译与 IPA 打包](https://github.com/54zhien/ccsut/actions/runs/40446410858) 均通过。之后仅更新 Markdown 文档，应用源码与工作流保持一致。
- 中间提交 `2d82b91` 的构建也通过；`e7fdcda` 的打包被工作流并发规则取消，不计作通过。最终结果使用上面的 `eb828a0` 两次运行。
- README 截图为已有基线验证产物，不冒充本次新跑的界面验收。
- 未做本次真机验收，未验证真实申请或付款；报告中的行为问题仍然开放。
