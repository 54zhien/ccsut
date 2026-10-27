# iOS 开发指南

用户功能与安装方式见[项目首页](../README.md)。此目录包含当前的 SwiftUI 客户端及其测试。

## 工程与环境

- 工程：`CCSUT.xcodeproj`，scheme：`CCSUT`。
- 最低系统：iOS 26.0；CI 使用 `macos-26` 和已安装的 Xcode。
- 工程的 Swift language mode 为 **5.0**；部分独立测试明确以 Swift 6 模式编译。
- 工程文件手动维护。增删源文件时，需要同步检查 `.pbxproj` 与独立测试工作流的源文件列表。

从仓库根目录执行模拟器编译：

```bash
xcodebuild -project ios/CCSUT.xcodeproj -scheme CCSUT \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

真机调试需要配置自己的开发者签名。CI 的 Release 打包流程见 [`ios.yml`](../.github/workflows/ios.yml)，产物为未签名 IPA。

## 模块边界

| 模块 | 主要文件 | 职责 |
| --- | --- | --- |
| 会话 | `Session.swift`、`WebSessionCookies.swift` | Cookie、Keychain、账号代数与 WebKit 同步 |
| 教务传输与模型 | `API.swift`、`AcademicAPI.swift`、`Models.swift` | 请求、响应校验、课程／成绩／考试数据 |
| 课表 | `AcademicCalendar.swift`、`SchedulePresentation.swift`、`ScheduleView.swift` | 周次、课表转换与展示 |
| 选课 | `ElectiveState.swift`、`EnrolledCourses.swift`、`ElectiveView.swift` | 批次、列表、选退课及结果状态 |
| 校园记录 | `CampusAPI.swift`、`CampusRecordsModel.swift` | 智慧校园认证及分页读取 |
| 校园表单 | `CampusFormsAPI.swift`、`CampusFormModel.swift`、`CampusFormRules.swift` | 配置、字段校验、确认与提交结果核对 |
| 电费 | `EcardSSOClient.swift`、`EcardAPI.swift`、`EcardPaymentModel.swift`、`EcardPaymentPersistence.swift` | 一卡通认证、房间、电表、订单及未决付款恢复 |
| 共享界面 | `PageSurface.swift`、`NavigationBridge.swift` 等 | 页面表面、原生导航与交互适配 |

教务、智慧校园与电费服务并不共用一种认证协议。业务读取的恢复和写入的提交策略也不同，不能把通用重试逻辑直接套在申请、上传或付款上。

## 需要保留的约束

- 异步请求绑定账号代数，换号后不能把旧请求的数据写回当前页面。
- Cookie 按目标域、路径和安全属性匹配；认证跳转不能把业务 Bearer token 带到其他服务。
- 写入超时不能按普通读取重试。电费在扣款前保存待核对订单，遇到未知结果优先查单。
- 校园表单和附件使用内存状态；日志与错误提示不得输出原始个人数据或认证响应。
- DEBUG 预览使用合成数据。模拟器测试不能连接学校生产写接口。

这些是维护约束，不代表所有边界已覆盖；当前已知缺口见[项目审查记录](../docs/reviews/2026-10-27-project-review.md)。

## 测试

跨平台的脚本与仓库隐私检查（Node.js）：

```bash
node --test ios/Tests/repository-privacy.test.mjs \
  ios/Tests/login-script.test.mjs ios/Tests/cas-script.test.mjs \
  ios/Tests/campus-web-privacy.test.mjs
```

电费离线回归（Python 3、Swift 编译器）：

```bash
python3 ios/Tests/run-ecard-tests.py
```

Windows runner 对不可用的平台接口使用测试替身，不能替代 macOS 上真实 WebKit／Security 框架的验证。完整会话、教务、校园表单和付款测试命令维护在 [`session-tests.yml`](../.github/workflows/session-tests.yml)。

模拟器界面测试位于 `CCSUTUITests/`，对应工作流位于 `.github/workflows/`。运行时应记录提交 SHA、测试范围及截图来源，分别报告：离线逻辑与源码检查、Xcode 编译、模拟器交互与外观、真机及真实学校业务验收。

## 改动界面前

遵循仓库的 [`AGENTS.md`](../AGENTS.md)：查询相关 Apple 官方 API 文档，优先使用适用的系统控件和 Liquid Glass 样式，保留已确认的布局与动效。解释平台限制、竞态和业务约束的注释应保留；文件名复述、过期实测数字和逐行翻译代码的注释应删除。
