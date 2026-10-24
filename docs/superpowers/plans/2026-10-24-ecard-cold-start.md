# 冷启动恢复一卡通 SSO 会话

用户反馈：重新登录 App 后缴费不用登录，但结束 App 进程后冷启动，缴费又需要认证。

根因证据：WebStore.dataStore 使用 nonPersistent，进程结束后网页 Cookie 清空；SessionStore.bootstrap 只恢复 Keychain → CookieJar。原生 verifySession 成功时直接进入 loggedIn/loadProfile，后者立即启动一卡通后台预取，没有执行 injectToWebKit。performRefresh（续期）已有 injectToWebKit；真正重新登录时网页本身已有 Cookie，因此出现行为差异。

修复：仅在 bootstrap 的原生验证成功分支，先将当前已验证、包含验证响应轮换值的 allCookies 同步到 WebKit；检查账号代数和任务取消后，才进入主界面及 loadProfile 的一卡通预取。保持 nonPersistent、Keychain Cookie 保存、内存 token 缓存及退出清理策略，不额外持久化缴费 token，不改 UI/接口/支付。

验证范围：用户要求先不测试，本次不新增/运行测试或真实登录/缴费。静态核对 bootstrap、performRefresh、logout 的执行顺序和 generation 守卫；Release 编译打包后交付，需用户实际结束进程并冷启动确认。
