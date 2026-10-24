# 校园模块设计

用户已确定：新增底部导航「校园」，首版只有「请假」「节假日离返校」「电表缴费」。一卡通余额和流水延期。电表缴费只迁移现有入口，不替换页面、认证或支付逻辑。

## 基线与界面

独立分支 `codex/zhixiao-services`。完整缴费页面来自已提交的 `2483a48`，接入本分支后原工作树不变。沿用其两个页签「课表」「教务」，新增第三个「校园」。只从教务移除缴费入口，校园直接调用同一个 `EcardPaymentView()`。

校园沿用现有 Nagi 顶栏、账号按钮、强调色、服务卡片和导航方式。三个入口顺序为请假、节假日离返校、电表缴费。请假页支持刷新、分页，显示类型、起止时间、天数、已知状态和脱敏事由；离返校分两类，分别显示记录、错误与空状态。申请进入已验证的官方 WebView，不实现提交协议。

## 协议

进入 leaveadmin 或 returnschool 前调用 validate_full，以当前子系统页面为 callback；需要时执行 cas-proxy redirect/CAS 链，再次验证。返回的 account 必须匹配当前 App 账号，三个查询均使用返回的 userId：

- POST `/backstage/leaveadmin/leaveApply/queryListForPage`：`{pageNum,pageSize,pageParam:{userId}}`，读取 `data.list` 和分页元数据。
- POST `/backstage/returnschool/returnApply/queryListByStudentId`：`{studentId:userId}`，读取 `data[]`。
- POST `/backstage/returnschool/studentGqleave/queryStuGqleaveInfo`：同上，校验字符串 code，读取 `data[]`。

业务 HTTP 401 仅允许重新建立子系统会话并重试一次。403、业务错误、解码失败与超时分别报错，不能显示为空列表。认证逐跳限制官方域，学校 HTTP 跳转升为 HTTPS，每跳匹配 Cookie，不改变已有 APIClient。

## 隐私与生命周期

`reference/out` 仅本地解析结构，原始内容不得打印、复制到工作树、入库或上传。不调用 userProfile；手机号、银行卡、身份证字段不进入展示模型，自由文本做号码脱敏。新响应仅保存在内存，不写缓存、日志、错误正文、数据库或 UserDefaults。复用现有 CookieJar/Keychain 凭证机制；新请求绑定 CookieJar 代数，退出、换号与取消后拒绝迟到结果。

## 验证

合成数据覆盖 envelope、异常、脱敏、分页失败、刷新、401 单次重试、身份匹配、跨域 Cookie、退出和取消。Windows Swift 6.4.1 运行 Foundation 测试；SwiftUI、WebKit 和 App 编译通过 macOS/Xcode 验证。保留失败证据，分别报告本地逻辑测试、macOS 构建与真机验收。常规命名、条数及 SwiftUI 细节交给实现者决定。
