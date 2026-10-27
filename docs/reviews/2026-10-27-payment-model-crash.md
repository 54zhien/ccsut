# 付款模型测试崩溃调查

## 当前结论

已复现 SIGSEGV，并定位到 Cookie 异步回调包装丢失主线程隔离。修复后的完整回归和压力验证状态见下方；早期未复现的记录保留作调查过程。

原失败：[Session regression tests 40453171719](https://github.com/54zhien/ccsut/actions/runs/40453171719)，提交 `538a32a`。付款 API 测试通过；付款模型进程收到 SIGSEGV，退出码 139。原测试使用缓冲输出，崩溃前没有模型断言日志，工作流也没有保存原进程崩溃报告。该运行的 artifact 列表为空。

## 根因与修复

[压力验证 40462247666](https://github.com/54zhien/ccsut/actions/runs/40462247666) 的原始程序组在第 85 个进程发生 SIGSEGV。`payment-crash-reports-original` 附件保存了系统崩溃报告和带符号的二进制。报告的异常地址为 `0x8`，故障线程是 `com.apple.root.default-qos.cooperative`：

```text
WebKit::WebsiteDataStore::isOptInCookiePartitioningEnabled()
API::HTTPCookieStore::isOptInCookiePartitioningEnabled()
-[WKHTTPCookieStore getAllCookies:]
WKHTTPCookieStore.cookieSnapshot() / Session.swift:163
CookieCallback.wait(timeout:start:) / Session.swift:149–153
EcardPaymentModel.acceptToken(...) / EcardPaymentModel.swift:226
```

同时，主线程正在执行 `WKWebView dealloc` 和 `EcardTokenBridge.__ivar_destroyer`。`CookieCallback.wait` 原本是没有 actor 隔离的异步方法，会将回调注册切换到通用并发执行器；上层付款模型的 `@MainActor` 不能跨过这个边界保护 WebKit。Windows 平台替身不会进入 WebKit，因此 200 个对照进程全部通过。

新增 `CookieCallbackExecutorTests.swift`，直接验证从主线程及后台任务调用时，回调注册都必须在主线程执行。[修复前 40462873872](https://github.com/54zhien/ccsut/actions/runs/40462873872) 两项均失败，超时、取消、重复回调检查仍通过，形成不依赖偶发崩溃的回归证据。

修复将 `CookieCallback.wait`、其 `start` 参数及 `WKHTTPCookieStore` 异步包装明确标记为 `@MainActor`。保留原有锁、超时、取消和只能完成一次的机制，不改付款请求或重试策略。

依据：[Apple Cookie API](https://developer.apple.com/documentation/webkit/wkhttpcookiestore/getallcookies(_:))、[Swift SE-0338 的非隔离异步执行器规则](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md)。

## 已做的检查

| 检查 | 结果 |
| --- | --- |
| 原测试文件、原编译参数，100 个独立进程 | [通过，40454770807](https://github.com/54zhien/ccsut/actions/runs/40454770807) |
| 即时断言日志与调试符号，10 个独立进程 | [通过，40454111371](https://github.com/54zhien/ccsut/actions/runs/40454111371) |
| Address Sanitizer，30 个独立进程 | [通过，40454458131](https://github.com/54zhien/ccsut/actions/runs/40454458131) |
| 原测试文件与 Thread Sanitizer，20 个独立进程 | [通过，40460614093](https://github.com/54zhien/ccsut/actions/runs/40460614093) |
| Main Thread Checker 与 Guard Malloc，各 10 个独立进程 | [通过，40460884334](https://github.com/54zhien/ccsut/actions/runs/40460884334) |

原失败与 100 次原程序复现使用同一镜像 `macos-26-arm64 20261013.0424.1`，不能将通过归因于镜像升级。原程序的接口响应来自本地 fixture，没有执行真实学校付款。

上述早期检测均未捕获问题。之后扩大原始程序验证取得了原进程系统堆栈，见上文。付款请求仍使用本地 fixture，没有执行真实学校付款。

## 补充诊断

断言改用即时标准错误输出，模型测试带调试符号。测试进程崩溃后尝试在 LLDB 中诊断，并保存二进制和系统崩溃报告。诊断中的再次运行即使通过，也保留第一次的失败；LLDB 不可用或超时也不能覆盖原崩溃退出码。新增离线测试验证这些规则。

常规 CI 恢复单次执行，不以多次运行筛选成功结果。压力检查留在调查分支的独立工作流中。

## 发布状态

修复提交 `89aa3b5` 的[完整回归与模拟器编译 40462990963](https://github.com/54zhien/ccsut/actions/runs/40462990963) 通过；[线程契约与原付款测试 300 次独立进程验证 40462991019](https://github.com/54zhien/ccsut/actions/runs/40462991019) 通过。独立复核未发现生产代码问题，并建议补充回调注册后再取消、随后收到迟到回调的验证，已补充到线程契约测试。

合并后仍须等待主分支全部 CI 通过再发布。旧 Releases 已按要求删除，旧 Git 标签保留。下一版使用 `0.1.0` 标签与版本号，不能覆盖历史 `v0.1.0`。CI、模拟器与安装包校验不能代替真机及真实学校付款验收。

诊断参考：[Apple 内存、线程与崩溃诊断](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)。

## 合并后的界面测试等待问题

付款修复合并为 `75c62e7` 后，完整会话回归与 IPA 构建通过。[校园界面运行 40463988826](https://github.com/54zhien/ccsut/actions/runs/40463988826) 在等待离校表单关闭按钮消失时超时，失败行是 `PageInteractionUITests.swift:531`。该运行的录屏明确显示表单已关闭，原有离校记录仍在；日志中一次 `exists` 查询及其自动重试超过了外层五秒 predicate waiter 的时间窗口。

将这项等待改为 XCTest 的 `waitForNonExistence(timeout:)`，直接等待元素消失，仍使用五秒限时，并保留后续原记录存在的断言与两次打开/关闭流程。不更改 App 的页面或关闭行为，也不重试失败用例以替换原失败记录。

参考：[Apple waitForNonExistence(timeout:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/waitfornonexistence(timeout:))。后续主分支必须重新完成三项 CI 才可发布。

README 顶部使用完整 App 图标，来自原生 Icon Composer 导出的 `Default.png`（运行 `40062568546`）。已核对该运行与当前提交的 `AppIcon.icon` 源文件完全一致。
