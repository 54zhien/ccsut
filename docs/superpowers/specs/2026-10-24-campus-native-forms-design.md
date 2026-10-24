# 校园原生办理设计

## 目标与授权

用户要求「申请请假」「办理离校登记」直接在原生界面完成。这更新了先前“提交操作一律跳 WebView”的范围。沿用已建立的 `codex/zhixiao-services` 独立工作树、SwiftUI 界面风格、现有 CAS/TGC 与账号代数机制。

本次覆盖新建请假申请、新建节假日离校/留校登记，以及提交后的记录刷新。返校申请、修改/撤回/审批/销假不纳入本次；既有返校查询与电表缴费保持现状。开发与自动化验证不向学校提交真实申请，不上传真实附件。

## 方案

用户已选定原生办理。采用 SwiftUI 表单直接调用官方业务接口，动态读取官方配置、候选项与审批人。静态写死表单会遗漏学校配置的附件、定位和审批规则；WebView 继续办理不满足本次要求，因此不作为申请流程方案。认证失效时复用 App 既有统一登录流程，认证完成后重新核对当前账号，再进入原生表单。此前官方表单 WebView 的真机故障仍未确认原因，本方案不依赖其成功加载，也不将其报告为已修复。

本文件中的界面组织、资源上限、提交状态处理是实现建议，尚待用户确认；它们不是对学校服务端行为的推测。

## 证据与边界

- 现有技术档案和真实响应只证明了记录查询；不能将其作为提交接口已经实测成功的证据。
- 官方请假包：`https://ehall.ccsut.cn/backstage/leaveadmin/page/mobile/main.a7bd21fa209ffd90f973.js`。已静态核对请假组件、必填判断、半天进位规则、审批人查询、附件及提交路径。
- 官方离校包：`https://ehall.ccsut.cn/backstage/returnschool/page/mobile/main-es2015.c0f4f892018c50a027e9.js`。已静态核对 `dR` 组件的新建/更新区分、假期类型、联系方式、离校/留校字段和提交路径。
- REA 对两个公开组件摘录完成语法分析，未执行代码；静态关系不代表真实请求已成功。完整公开包与摘录保存在 git 忽略的工作区中，不含真实会话。
- `reference/out` 只在原位置解析结构；不打印、复制、提交或上传其会话及个人信息。不得用真实响应作为测试 fixture。

## 请假申请

表单按官方配置显示：请假类型、开始/结束时间、自动计算的天数、请假事由、紧急联系人电话、审批人，以及条件性的是否离校、离校时间、去向类型/明细、定位和附件。每项有可见标签，错误就近显示；沿用现有顶栏、强调色、卡片、系统日期选择器和可访问性字号。

先完成身份验证，再读取：

| 读取目的 | 官方接口与输入 |
| --- | --- |
| 表单配置 | POST `/backstage/baseinfo/sysConfig/querySysConfigItems`，`configKeys` 包含 `leave_address_config`、`leaveApplyDateCheck`、`leave_date_title`、`leave_date_content`、`fileNum`、`dataAddressShow`、`leave_qxlx_config`、`leaveSchoolTimeSelect`、`linkmanPhone`、`leaveadminApplyPowerUser`、`leaveadmin_show_files`、`leaveadmin_userExtra`、`leaveadmin_sflx` |
| 可用类型 | POST `/backstage/leaveadmin/LeaveType/queryListForPage`，`{pageNum,pageSize,pageParam:{typeName:null,studentId:validatedUserId,power:true}}`，仅使用 `enableStatus == 0` 的候选项；分页读取完整候选列表 |
| 审批人 | POST `/backstage/leaveadmin/leaveTask/getFirstRoleUsers`，官方使用 multipart 字段 `leaveDay`、`leaveTypeId`、`realName`；读取返回的 `roleId`、`roleName`、`users` |
| 角色候选补充 | 学校配置要求时 GET `/backstage/auth/baserole/users/<roleId>`；不得自行构造审批人 ID |
| 联系人预填 | POST `/backstage/baseinfo/studentInfo/queryStudentById`、`/backstage/baseinfo/studentFamily/queryByid`，仅解码本次所需电话与联系人字段，忽略身份证等无关字段 |
| 去向类型 | POST `/backstage/baseinfo/common/queryAreaLabel`，`{level:2}` |
| 定位地址 | 仅配置要求时申请系统前台定位权限，将真实坐标按官方 `gcj02` 约定转换后 GET `/backstage/app-manager/platformData/geocoder`；拒绝权限、定位失败或坐标不可用时明确阻止该必填项提交，不伪造地址 |

天数按官方半天向上进位：大于 0 且不足半天为 0.5 天，超过半天不足一天为 1 天，整天不额外加半天；结束时间必须晚于开始时间。学校的类型时间段约束生效。日期在界面统一按学校时区显示，请求序列化与官方 Date JSON 行为一致。

更改类型、时长或审批条件时清空已选审批人，取消旧查询；迟到结果不得重新选回旧人。只有当前候选中唯一审批人可自动选择；多人时由用户选择。必填联系人号码始终遮蔽显示，不能因为网页的显示开关而忽略其提交必填判断。

提交使用 POST `/backstage/leaveadmin/leaveApply/submitLeaveApply`。身份字段只来自已匹配账号的验证结果/最小身份读取，不接受任意学生 ID。载荷按官方字段包含类型 ID/名称、时间、时长、事由、紧急电话、审批人/角色、离校相关字段及配置要求的去向/附件/地址。特别测试官方非直觉映射：`leaveSchool == "0"` 表示离校，`"1"` 表示不离校。

图片使用官方 `/backstage/filecenter/file/base64`（multipart `file` 与 `name`）；一般文件使用 `/backstage/filecenter/file`。上传返回的 ID 和文件名组成 `applyFiles` 或序列化 `fileList`。只在用户确认提交后上传。客户端建议上限为单文件 20 MiB、单草稿总计 50 MiB，学校更严格的限制优先；图片数量服从学校 `fileNum`。附件只显示脱敏文件名、数量与大小，不自动显示可能包含个人信息的预览。不实现删除服务端文件的协议。

## 节假日离校登记

原生填写假期类型、是否离校、起止时间、目的地（省/市/区）、详细地址、交通方式、车次、事由、本人及家长联系电话。是否离校由用户明确选择。当前开放类型为空时显示暂不可登记，不能用历史类型 ID 提交。

类型来源 POST `/backstage/returnschool/leaveType/page`，输入 `{name:null,status:"是",pageNum,pageSize}`，读取 `data.records` 的 `openid/name`；分页读取完整结果。学生预填来源 POST `/backstage/returnschool/studentGqleave/queryStudentInfo`，输入 `{studentId:validatedUserId}`，仅解码姓名、学号、班级、专业和本次所需电话，忽略 `sfzh`。地区候选使用官方公开包中的地区数据；将公开地区树单独提取为资源，记录来源与摘要，不把任何真实抓包写入资源。

提交使用 POST `/backstage/returnschool/studentGqleave/applyGqleave`。新建载荷的 `openid/status` 为 null，`studentId` 来自验证身份，`type` 来自开放假期候选，`isLeave` 使用官方的「是/否」字符串。离校时校验起止时间、目的地和两个有效电话；其他字段按官方条件提供。留校时清空 `reason/jtgj/tjcs/xxdz/txdz/startDate/endDate`，不夹带切换前的离校信息。此次不调用 `updGqleave`，不隐式修改历史记录。

## 会话、隐私与提交状态

继续使用修正后的 `validate_full` + Bearer 令牌和 Cookie；令牌、原始表单数据、电话号码、定位、附件及响应仅在内存中持有。手机号在输入、候选、摘要、错误和可访问性文字中均遮蔽；自由文本在编辑和展示时同样掩码号码，提交所需原值仅在内存保留，不能把掩码字符串写回实际载荷。身份证号、银行卡号不进入新表单模型。提交摘要只显示业务必要信息，不显示账号凭证或不透明 ID。

表单读取可在 401 后重新验证并重试一次。写入接口使用单独的发送路径，禁止自动跟随重定向、自动重试和业务失败转成功。401、403、配置变更、账号切换和取消有明确状态。账号切换或退出后清除草稿、候选项与迟到结果；提交摘要绑定不可变草稿及账号代数，确认后不能被异步预填覆盖。

提交前显示原生摘要，用户点「确认提交」才发出写请求；提交中防重复点击。明确成功显示「已提交，等待审核」并刷新原生记录，不能显示为审批通过。超时、断网或无法解码的写响应显示「结果待确认」，提供查询记录而不自动重发；若无法唯一匹配提交结果，保留待确认状态，不凭空认定失败或成功。未能确认落库的已上传附件不触发自动删除。

## 验证与交付

合成数据覆盖配置开关、动态候选、半天进位、时间限制、审批人变化、掩码输入、附件必填/限制、定位拒绝、离校/留校切换、确认快照、重复点击、未知提交结果、401 读重试、写入不重试、身份切换和取消。公开组件用于协议比对，测试不得执行真实写接口。Windows 执行 Foundation 回归，macOS 执行 SwiftUI/WebKit 编译与原生表单 UI 测试，保留失败证据。

最终提供新的未签名 IPA。分别报告协议静态核对、模拟响应测试、macOS 构建、真机表单读取与真实提交验收；真实提交只能由用户在 App 中按自己的实际申请需求确认，不能以测试名义代其发起。

## 留给实施者与尚未证明的事项

实施者决定文件拆分、控制项细节与测试组织，保持现有 App 风格。API 载荷字段、附件边界、定位转换和成功判定须逐项与公开源码核对；遇到官方配置或返回结构无法识别时明确报错，不能悄悄忽略必填条件。新增读取接口与提交协议目前为公开源码证据，尚无本次账号的实际成功响应；需在开发及真机只读加载中验证，不得将模拟测试当成学校实测。
