# 付款模型测试崩溃调查

## 当前结论

尚未定位根因，也没有已验证的业务修复。不能用后续通过的测试宣称原崩溃已修好。

原失败：[Session regression tests 40453171719](https://github.com/54zhien/ccsut/actions/runs/40453171719)，提交 `538a32a`。付款 API 测试通过；付款模型进程收到 SIGSEGV，退出码 139。原测试使用缓冲输出，崩溃前没有模型断言日志，工作流也没有保存原进程崩溃报告。该运行的 artifact 列表为空。

## 已做的检查

| 检查 | 结果 |
| --- | --- |
| 原测试文件、原编译参数，100 个独立进程 | [通过，40454770807](https://github.com/54zhien/ccsut/actions/runs/40454770807) |
| 即时断言日志与调试符号，10 个独立进程 | [通过，40454111371](https://github.com/54zhien/ccsut/actions/runs/40454111371) |
| Address Sanitizer，30 个独立进程 | [通过，40454458131](https://github.com/54zhien/ccsut/actions/runs/40454458131) |
| 原测试文件与 Thread Sanitizer，20 个独立进程 | [通过，40460614093](https://github.com/54zhien/ccsut/actions/runs/40460614093) |
| Main Thread Checker 与 Guard Malloc，各 10 个独立进程 | [通过，40460884334](https://github.com/54zhien/ccsut/actions/runs/40460884334) |

原失败与 100 次原程序复现使用同一镜像 `macos-26-arm64 20261013.0424.1`，不能将通过归因于镜像升级。原程序的接口响应来自本地 fixture，没有执行真实学校付款。

模型登录测试仍创建真实 WebKit 组件；检查过该入口，但目前没有堆栈或检测器报告能证明它是原因。也没有证据将失败归因于重复付款逻辑。

## 补充诊断

断言改用即时标准错误输出，模型测试带调试符号。测试进程崩溃后尝试在 LLDB 中诊断，并保存二进制和系统崩溃报告。诊断中的再次运行即使通过，也保留第一次的失败；LLDB 不可用或超时也不能覆盖原崩溃退出码。新增离线测试验证这些规则。

常规 CI 恢复单次执行，不以多次运行筛选成功结果。压力检查留在调查分支的独立工作流中。

## 发布状态

主分支 `8dc117d` 的会话回归、IPA 构建和校园记录验证均通过，但原崩溃仍未解决，因此尚未满足用户要求的发布条件。旧 Releases 已按要求删除，旧 Git 标签保留。下一版使用 `0.1.0` 标签与版本号，不能覆盖历史 `v0.1.0`。

诊断参考：[Apple 内存、线程与崩溃诊断](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)。
