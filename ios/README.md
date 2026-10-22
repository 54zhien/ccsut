# CCSUT · iOS 客户端

长沙工业学院教务系统的原生 iOS 客户端。
**SwiftUI + Swift 6 + iOS 26**，全部使用 Apple 当前最新接口。

---

## 技术选型（为什么是这些）

| 层 | 选择 | 理由 |
|---|---|---|
| UI | SwiftUI | Apple 官方唯一推荐方向，UIKit 已进入维护期 |
| 状态 | `@Observable` 宏 | iOS 17 起取代 `ObservableObject`，[官方迁移指南](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) |
| 网页 | **WebView + WebPage**（WebKit for SwiftUI） | iOS 26 原生，不再需要 `UIViewRepresentable` 包 `WKWebView` |
| 注入 JS | `callJavaScript(_:arguments:)` | 参数自动转义，不用手写 JSON |
| 材质 | `glassEffect` | iOS 26 Liquid Glass |
| 标签栏 | `Tab(_:systemImage:value:)` + `tabBarMinimizeBehavior` | iOS 18 / 26 新语法 |
| 密钥 | Keychain（`Security`） | 系统级，比 UserDefaults 安全 |

**部署目标：iOS 26.0**。用了 iOS 26 专属 API，低于这个版本编译不过。
如果你要兼容 iOS 18，需要把 `WebView`/`WebPage` 换回 `UIViewRepresentable + WKWebView`，并把 `glassEffect` 换成 `.thinMaterial`。

---

## 创建工程

```
Xcode 26 → File → New → Project
├── iOS → App
├── Product Name: CCSUT
├── Interface: SwiftUI
├── Language: Swift
└── Minimum Deployment: iOS 26.0
```

建好后删掉自动生成的 `ContentView.swift`，把 `ios/CCSUT/` 下这 7 个文件拖进工程：

```
CCSUT/
├── CCSUTApp.swift       App 入口 + RootView + TabView + 我的页
├── Session.swift        会话：Keychain / 探测 / TGC 续期
├── API.swift            网络层 + 课表 HTML 解析
├── Models.swift         数据模型（按实测 JSON 定义）
├── LoginView.swift      登录页（原生 UI + 隐藏 WebView）
├── ScheduleView.swift   课表网格
└── ElectiveView.swift   选课浏览
```

拖进去时勾选 **Copy items if needed** + 目标 target。

---

## Info.plist

现代 Xcode 用 `GENERATE_INFOPLIST_FILE = YES`，大部分键自动生成。需要手动补的只有：

| 键 | 值 | 原因 |
|---|---|---|
| `CFBundleDisplayName` | `长工院教务` | 桌面名称 |
| `UILaunchScreen` | `{}`（空字典） | 避免黑屏 |
| `NSAppTransportSecurity` | **不需要** | 全站 HTTPS |

**不需要** `WKAppBoundDomains`——设了会限制 WebView 只能访问白名单域名，我们的登录链路跨 `auth.ccsut.cn` → `tls.ccsut.cn`，设了反而更麻烦。

---

## 签名（自签）

```
Target → Signing & Capabilities
├── Team: 你的 Apple ID（Personal Team 即可）
├── Bundle Identifier: 改成唯一的，如 com.你的名字.ccsut
└── Automatically manage signing: ✓
```

Personal Team 的限制：
- **7 天过期**，到期要重新签名安装
- 最多 3 个 App
- 无法使用 Push / Background Modes

**Keychain 在自签下正常工作**，`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 不需要额外 entitlement。

---

## 运行前要改的一处

`Session.swift` 里的 `CookieKey` 用了 v2 后缀，如果你之前跑过 v1 版本，会重新登录一次。这是故意的——v1 存的是旧结构。

首次登录走这里：

```
App 启动
  → Keychain 有 Cookie？→ 注入 → 探测 /admin/
      ├── 200 且非 login → 直接进主界面
      └── 303 到 login  → TGC 还在？→ 静默续期 → 进
                        → TGC 也没了 → 登录页
  → Keychain 空 → 登录页
```

---

## 各模块状态

| 模块 | 代码 | 验证状态 |
|---|---|---|
| 登录（CAS 注入填表） | ✅ 完成 | ⚠️ 未在真机跑过，JS 逻辑在浏览器里验证过 |
| Cookie 持久化 | ✅ 完成 | ⚠️ 待真机验证 Keychain 存取 |
| TGC 静默续期 | ✅ 完成 | ⚠️ 待第 13 天验证 |
| 课表网格 | ✅ 完成 | ⚠️ **当前学期无数据**，解析逻辑未跑过真实数据 |
| 选课浏览 | ✅ 完成 | ✅ JSON 结构已实测（71 KB 真实响应） |
| 成绩 | ✅ WebView 兜底 | ✅ 接口地址已实测（JSP 报表） |

**课表这块要特别注意**：现在是 2026-2027-1 选课阶段，`queryKbForXsd` 返回的表格是空的。
`ScheduleParser` 按 `rowspan` 占位算法写得比较保守，等课表生成后第一次跑，可能需要根据实际单元格结构调整 `splitLines` 的切分逻辑。

---

## 已知限制

1. **选课是只读的**。写操作（选课、退课）不做——时间窗口短、失败不可逆、出事是学籍问题。
2. **成绩走 WebView**。`/admin/xsd/xsdzgcjcx/xscjdy` 会 302 到 JSP 报表引擎（`showReportNoWord.jsp`），那套和 Vue 是两代技术，不值得啃。
3. **没有推送**。自签拿不到 APNs 权限。
4. **后台不保活**。iOS 自签没有 Background Modes，只能前台续期。好在 TGC 有 14 天，正常使用完全够。

---

## 调试技巧

登录卡住时，`LoginView` 底部会露出最近 3 条日志（`logLines`），能看到：
- `加载认证页…` → WebView 在加载
- `注入：ok / no-form / no-button` → JS 执行结果
- `已提交，等待跳转…` → 提交了但没跳成功

如果一直 `no-form`，说明页面结构变了，去 Safari 里打开 CAS 页对照一下 `input[type=password]` 是否还在。

`ProfileView` 能看到当前所有 Cookie 和 TGC 剩余天数，用来判断续期是否正常。
