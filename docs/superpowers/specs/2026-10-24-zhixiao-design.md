# 智校模块设计

## 用户已确定的方向

在现有 iOS App 的底部导航新增「智校」，包含请假记录、离返校记录、一卡通余额与流水、电表缴费。使用已有 TGC 会话。先建立独立 worktree，避免影响另一个 Codex 的工作。

## 边界

- SwiftUI、Swift 6、iOS 26；沿用当前 App 的界面语言和会话体系。
- 原生网络层只实现已验证的查询接口。请假申请、充值、挂失、电表缴费的办理均打开官方 WebView。
- 不改已有课表、成绩、考试、选课、我的的业务行为；不调整已有页面的动画、布局或底栏滚动策略。
- `reference/out/` 是敏感输入，只允许本地解析字段和类型。禁止复制进工作树、打印原始内容、入库或上传。
- 新增响应不持久化、不写 URLCache、不进入日志或错误正文。身份证号、银行卡号、手机号默认不进入展示模型；需要展示时只保留脱敏结果。自由文本同样做号码脱敏。流水 remark 默认不展示。
- 退出、换号、取消后丢弃迟到结果；新模块的会话凭证不得恢复旧账号数据。已有 Keychain TGC 保存机制继续使用。

## 方案选择

最初建议在「我的」中加入校园服务入口，以保留五个底部页签。用户选择新增「智校」底部页签，并增加电表缴费入口。采用独立模块及查询客户端，避免把教务、缴费应用 token 和 berserker 平台 token 混为一谈。

## 用户界面

「智校」为独立导航栈。首页提供请假记录、离返校记录、一卡通、电表缴费四个入口。

- 请假记录：类别、时间范围、天数、状态、经过号码脱敏的事由；支持刷新和分页。「申请请假」进入官方页面。
- 离返校记录：返校与离校两类，显示批次、日期、状态和必要的脱敏摘要；独立加载和错误状态。
- 一卡通：卡余额、待清算金额、卡状态及流水列表。金额使用整数分和 Decimal 格式化为元；不推断样本未证实的交易正负含义。支持刷新、加载下一页，失败保留已有列表并允许重试。「充值」「挂失」进入官方一卡通 WebView。
- 电表缴费：打开已知官方缴费入口 `/charge/feeitem/toAppitem?feeitemid=408`，由网页完成校区/楼栋/房间选择和支付；不接入现有原生建单、支付方法。
- 每个页面区分加载、空数据、失败和登录失效，避免将解码失败显示为空记录。

## ehall 查询

进入子系统前，以该模块的移动页作为 callback 调用 `validate_full`。如需 CAS 跳转，执行官方 `cas-proxy/app/redirect` 链；学校域名的 HTTP 跳转提升为 HTTPS，Cookie 每跳按域和路径匹配。

验证成功后使用返回的 `userId`。本地样本比较已确认，以下三个查询参数中的身份均匹配该 userId，均不是学号：

- `POST /backstage/leaveadmin/leaveApply/queryListForPage`，body `{pageNum,pageSize,pageParam:{userId}}`，读取 `data.list` 和分页元数据。
- `POST /backstage/returnschool/returnApply/queryListByStudentId`，body `{studentId:userId}`，读取 `data[]`。
- `POST /backstage/returnschool/studentGqleave/queryStuGqleaveInfo`，同上，校验字符串 `code`，读取 `data[]`。

业务查询遇到 401，重新建立相应子系统会话后仅重试一次。业务失败、403、解码失败和网络超时不误判成空列表或无限重试。

## 一卡通查询

使用共享的非持久 WebKit 会话，并将当前 TGC 按正确域注入。加载官方 berserker-auth 入口，由官方前端完成 ZTS/CAS/oauth/token 链，不重新实现加密账号口令或支付协议。认证 WebView 保持挂载，显示进度；需要用户登录时允许查看官方页面。

只接收固定官方 origin 的平台 token；以当前账号和 CookieJar 代数约束使用，账号不符时拒绝读取。具体 token 获取方式与请求头以官方前端代码为准，不能复用现有 charge-app token 或猜测字段。

- `GET /berserker-app/ykt/tsm/queryCard`：校验 `code/success` 及内层 `retcode`；读取 `data.card[]` 中必要字段。
- `GET /berserker-search/search/personal/turnover?size=...&current=...`：读取 `data.records` 和 `total/current/pages`。

## 验证与交付

使用人工合成数据测试响应解码、分页、整数分转换、脱敏、401 单次重试、账号切换和取消；不从真实抓包生成测试 fixture。保留现有会话与登录回归测试。

Windows 可执行的基线为 `node --test ios/Tests/login-script.test.mjs`，当前 6/6 通过。Swift/WebKit 与完整 App 构建需要 macOS/Xcode；构建、模拟测试、真机查询和实际支付验收分别报告，不互相替代。

实现者自行决定文件内的命名、常规 SwiftUI 细节和每页条数；不新增与以上功能无关的系统入口。
