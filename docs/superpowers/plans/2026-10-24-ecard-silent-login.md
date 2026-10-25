# 电费缴费后台自动登录

用户确认当前数据已正常加载，要求自动登录不再闪现 sheet。沿用已跑通的 CAS、网关 Cookie 交接和 token 验证，不改接口或支付规则。

当前 start() 在缓存缺失时直接设置 loginRequest，sheet 的 task 才开始 fetchToken，因此即使已有 SSO 会话也必须先显示窗口。本次将认证任务移到 model，先用同一 WebStore、不可见且有有效视口的 WKWebView 获取 token。缓存命中直接加载；后台成功后交接 Cookie 并加载数据。sheet 只挂载正在认证的同一个 webView，不再启动/重启任务。

bridge 在可信学校认证页面发现持续可见的密码/验证码/二维码控件时通知 model 显示认证窗口。门户先执行既有 CAS/电费入口跳转，避免本可自动跳过的登录页立即触发 sheet。仅等待超时不等于需要用户认证，等待超过 8 秒仅显示「打开认证页面」按钮，不自动弹窗。

关闭 sheet 或离开页面会取消认证、延迟按钮和 Cookie 交接任务，并使用原 revision/账号 generation 丢弃迟到结果。已有待确认订单保留，后台认证不触发建单/支付。学校不同服务有独立会话，有效 CAS 可用于续验；不能承诺学校要求交互的验证永远免除。

文件：EcardPaymentModel.swift 拥有认证生命周期、按需展示；EcardTokenBridge.swift 检测交互页面、后台视口；EcardPaymentView.swift 移除 sheet task 并提供延迟手动入口。保持已有样式。按用户要求不运行测试，仅核对取消分支、编译 Release 并交付 IPA；是否消除真机闪窗待用户确认。

实现 411e3dd 的 Release 编译打包通过（run40055675078）。只读审查发现：SwiftUI task 在等待主账号资料后需要再次检查取消，防止页面退出后才启动认证；已在 model.start 前加入检查。后台认证、交互升级、Cookie 交接与原订单保留分支完成静态核对，未运行测试；补充取消守卫后重新编译打包。
