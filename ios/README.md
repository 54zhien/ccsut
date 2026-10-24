# 长工教务 · iOS

长沙工业学院教务系统的原生 iOS 客户端。
SwiftUI + Swift 6 + iOS 26。

---

## 功能

「校园」页提供请假记录、节假日离返校记录与电表缴费入口。请假和离返校通过已有 CAS/TGC 查询，进入子系统前验证会话，401 时仅重建并重试一次；申请在官方 WebView 办理。电表缴费复用现有 `EcardPaymentView`，仅从教务页迁移入口，原有认证、确认和订单处理保持不变。一卡通余额与流水暂未接入。

新增校园记录只保存在内存，手机号、身份证号、银行卡号不进入展示模型，自由文本号码脱敏；错误不包含服务器响应正文。真实会话和抓包文件不得用作仓库 fixture。

| 模块 | 数据源 | 实测规模 |
|---|---|---|
| 课表 | `POST /admin/xsd/pkgl/xskb/sdpkkbList` | 98 条 / 10 门课 / 4 大节 × 7 天 |
| 成绩 | `GET /admin/ydd/inf/getXscjJson?xnxq=111` | 61 门 / 5 个学期 |
| 选课 | `POST /admin/xsd/xk/listjxbDataV2` | 138 门（63 网课 + 75 面授） |
| 会话 | `TGC` 14 天 | 冷启动免登录，到期静默续期 |

登录全部走 WebView 代理，不重写任何加密逻辑。

---

## 认证体系

### 域名拓扑

```
auth.ccsut.cn   CAS 统一身份认证（Spring Boot + Angular）
tls.ccsut.cn    教务系统（超星综合教学管理系统 v3）
ehall.ccsut.cn  智慧校园门户（Pitcher 3.0，只做导航）
```

### CAS 的三个页签

页签 class 是 `.ant-tabs-tab`（Angular + Ant Design）：

| 页签 | 字段 | 说明 |
|---|---|---|
| 扫码登录 | 二维码 | 不需要验证码，最快 |
| 密码登录 | 学号 + 密码 + 短信验证码 | 密码是独立的一套 |
| **验证码登录** | 工号/学号/手机号 + 短信验证码 | **本 App 用这条，不需要密码** |

验证码是**短信验证码**（DOM 里没有 captcha 图片，只有「获取验证码」按钮）。
服务端先校验验证码，空的直接拒，密码根本不检查。

### Cookie 生命周期

| Cookie | 域 | 有效期 | 作用 |
|---|---|---|---|
| `TGC` | auth.ccsut.cn | **14 天** | CAS 票据，静默续期的关键 |
| `jw_uf` | tls.ccsut.cn | 4 小时 | **教务接口唯一必需的凭证** |
| `username` / `puid` | tls.ccsut.cn | 14 天 | 身份标识 |
| `JSESSIONID` | tls.ccsut.cn | 会话级 | 可有可无 |

**实测结论**：把 14 条 Cookie 逐个删掉做隔离测试，只有去掉 `jw_uf` 会失败，其余全部能拿到数据。

---

## 关键接口

### 课表

```
GET  /admin/xsd/pkgl/xskb/queryKbForXsd?xnxq=2026-2027-1   ← 只用来取隐藏字段 xhid
POST /admin/xsd/pkgl/xskb/sdpkkbList?xnxq=...&xhid=...      ← 真数据
```

`queryKbForXsd` 返回的 HTML 里 `<td>` 全是空的，数据是页面加载后 AJAX 拉的。
别解析 HTML，直接调 `sdpkkbList`。

字段里都包着 `<a href="javascript:...">`，要剥。`djc` 是 1-8（小节），压缩成 4 大节：`(djc + 1) / 2`。

### 成绩

```
GET /admin/ydd/inf/getXscjJson?xnxq=111
```

`xnxq=111` 是服务端约定的「全部学期」，一次拿回所有成绩。

**不要走 `/admin/xsd/xsdzgcjcx/xscjdy`** —— 那是 PC 端的 JSP 报表，学校缺 `.rpx` 模板文件，永远报「报表文件不存在」。`ydd` 这个模块（超星「云督导」）才是移动端用的 JSON 接口。

### 选课

```
POST /admin/xsd/xk/listV2              ← 拿 pcencs（可能有多批）
POST /admin/xsd/xk/listjxbDataV2       ← 拿具体课程
```

`pcencs` 是 `{pcid: pcenc}`，**可能有多批**（实测 2 批：线上 63 门 + 线下 75 门），必须遍历合并，只取第一个会漏一大半。

`status == "1"` 表示已选。

---

## 踩过的坑

按发现顺序，都是实测踩出来的：

**1. WebView 不可见会停止渲染**
把 `WKWebView` 缩成 1×1 或 `opacity(0.01)`，WebKit 会判定不可见并停止导航，表现为永远卡在「加载认证页」。
正确做法是全屏渲染 + 用不透明的原生层遮住。

**2. CAS 登录页的 URL 里含 `tls.ccsut.cn`**
```swift
// 错：CAS 页的 service 参数里就含这个域名，会把登录页误判成已登录
absolute.contains("tls.ccsut.cn")
// 对：按 host 精确匹配
url.host == "tls.ccsut.cn"
```

**3. 响应结构的字段类型和直觉不符**
```swift
let kfrlbfb: Int?                            // 实际是字符串 "100"
let jxms: String?                            // 实际是数组 ["中文教学"]
```
任一不符整个结构解码失败，而 `if let env = try? JSONDecoder()...` 会**吞掉错误**，既不报警也不显示失败，只是给你一个空列表。
用不到就别声明，`Decodable` 会忽略未声明的键。

**4. `httpShouldSetCookies` 会覆盖手写的 Cookie header**
`URLSessionConfiguration.httpShouldSetCookies = true` 时，`URLSession` 用 `HTTPCookieStorage` 里的 Cookie 替换你手写的 `Cookie` 头。

**5. `adoptCookies` 的轮询结束条件**
不能以「拿到任意一条 Cookie」为结束 —— 打开 CAS 页瞬间就有 `JSESSIONID`，这时还没登录。要等 `jw_uf` / `puid` / `username` 出现。

**6. Angular 渲染延迟**
`didFinish` 时 DOM 往往还是空的，`querySelectorAll('.ant-tabs-tab')` 得到空数组。必须轮询等页签出现。

---

## 构建

GitHub Actions + `macos-26` runner，Xcode 26。

```bash
git push origin main      # 自动构建
```

产物是**未签名 IPA**，用 SideStore / Sideloadly 自签安装。

部署目标 **iOS 26.0**（用了 `glassEffect`、`tabBarMinimizeBehavior`）。

---

## 目录

```
ios/CCSUT/
├── CCSUTApp.swift      入口 / RootView / TabView / 我的页
├── Session.swift       会话：Keychain / CookieJar / TGC 续期
├── API.swift           网络层
├── Models.swift        数据模型
├── LoginView.swift     登录页（原生 UI + 后台 WebView）
├── ScheduleView.swift  课表（4 大节 × 7 天 + 周次胶囊）
├── ScoreView.swift     成绩单（按学期分组 + GPA）
├── ElectiveView.swift  选课（138 门 + 已选筛选）
├── WebPanel.swift      WKWebView 容器 + JS 执行
└── WebLoginSheet.swift 底部弹窗登录（备用）
```
