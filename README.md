# 长沙工业学院教务系统（tls.ccsut.cn）技术档案 & 自建客户端方案

> 全部结论来自 2026-10-22 对该域名的实测（curl + 浏览器 HAR + 前端 bundle 静态分析），不是猜测。
> 文中出现的接口都是真实响应过的路径。

---

## 0. 一句话结论

`tls.ccsut.cn` 是**超星（学习通）的综合教学管理系统**，登录走三套并行通道：**学习通扫码**、**账密（RSA 加密）**、**学校统一身份认证 CAS（auth.ccsut.cn）**。

你说的"每次进去都要扫码"，根因不是系统限制，而是**学习通内嵌 WebView 不保存会话 Cookie**：`tls.ccsut.cn` 发的 `uid` 是**会话级 Cookie（没有 Max-Age）**，WebView 一关就没了，所以下次只能重新认证，而学习通能提供的最省事认证方式就是扫码。

**自建 App 只要把 Cookie 持久化 + 用 CAS 做静默续期，就能做到"打开即用、永不扫码"。** 下面给三条路线，路线 A 一天能出可用版本。

---

## 0.5 实测结果（2026-10-22，真实账号跑通）

用 `tools/capture.mjs` 登录一次后的确定结论，**推翻了我最初的两个猜测**：

### ① 会话是 A 级，可以长期免登录

登录后最重要的 Cookie 不是 `rememberMe`，而是 **`TGC`**：

| Cookie | 域 | 有效期 |
|---|---|---|
| **`TGC`** | auth.ccsut.cn | **14 天**（HttpOnly） |
| `username` / `puid` / `defaultPass` / `initPass` / `inactivePass` | tls.ccsut.cn | 14 天 |
| `twiceAuthSign` | tls.ccsut.cn | 12 小时 |
| `jw_uf` / `jw_uf_d` / `jw_uf_u` | tls.ccsut.cn | 4 小时 |
| `uid` / `route` / `JSESSIONID` | tls.ccsut.cn | 会话级 |

`TGC` 是 CAS 的 Ticket Granting Cookie。**只要它有效，App 访问 `/admin/caslogin` 就能静默换到新 ticket、重建会话，用户零操作。**

结论：**14 天内完全免登录，且到期前一次静默续期即可续命**。不需要 rememberMe，不需要保活轮询。

### ② 后端是前后端分离的 Vue SPA，接口是干净 JSON

不是服务端渲染！证据：

- 登录后入口：`/admin/` → 302 → `/frontend/views/student/xkPage/index.html`
- 前端栈：**Vue + axios + element-ui + http-vue-loader**（运行时加载 `.vue`）
- `/frontend/utils/request.js` 全文 59 行，就一个 axios 包装，**`withCredentials: true`，没有任何签名 / token / 加密头**
- 接口统一返回 `{"ret":0,"msg":"success","data":{...}}`

**这意味着原生改造的成本比预估低得多**——不用解析 HTML 表格，直接吃 JSON。

### ③ 真实接口清单（全部实测 200）

| 模块 | 接口 | 返回 | 说明 |
|---|---|---|---|
| 课表页 | `/admin/xsd/pkgl/xskb/queryKbForXsd` | HTML 骨架 + AJAX 填充 | 70KB，表格结构完整 |
| 校历周次 | `/admin/api/getXlzc` | JSON | 课表用 |
| 周次列表 | `/admin/api/getZclistByXnxq` | JSON | 按学期取 |
| 选课列表 | `/admin/xsd/xk/listV2` | **JSON（实测 31KB 真实数据）** | 含 `dataXnxq: "2026-2027-1"`、课程归属字典 |
| 教学班数据 | `/admin/xsd/xk/listjxbDataV2` | **JSON（实测 71KB）** | 含 `mysksjd` 上课时间段 |
| 选课检查 | `/admin/xsd/xk/checkSfxkBypcid` | JSON | 批次可用性 |
| Tab 配置 | `/admin/xsd/xk/getShowTab` | JSON | 功能页签 |
| 字典 | `/admin/xsd/xkprocess/student/getDictByGroupCode` | JSON | 课程归属等 |
| 表格字段 | `/admin/system/gridfield/getTranslation` | JSON | 列名翻译 |
| 成绩 | `/admin/xsd/xsdzgcjcx/xscjdy` | **302 → JSP 报表** | `/report//reportJsp/showReportNoWord.jsp?rpx=csgyxy/xsd/cjgl/` |

**成绩这块是唯一的例外**：走的是老的 JSP 报表引擎（`showReportNoWord.jsp`），不是 JSON。要么解析报表 HTML，要么直接 WebView。

### ④ 课表现在是空的，不是接口坏

`queryKbForXsd` 返回 67KB 页面，表格骨架完整（12 行 × 94 格，星期日→星期六），但单元格无数据——因为当前处于 **2026-2027-1 选课阶段**，下学期课表还没排。等课表生成后同一接口就会填充。

---

## 0.6 对方案的影响（修正后）

原计划里的"会话保活、Cookie 快照、静默重登"三件套，**现在只需要第一件**：

```
登录（WebView 一次）
  → 保存 TGC + 全套 Cookie（Keystore / Keychain）
  → 冷启动注入 → 直接进主界面
  → 第 13 天起：后台静默访问 /admin/caslogin，TGC 换新 ticket，续 14 天
  → 用户永远不用再登录
```

工作量重估（单端 Android）：

| 模块 | 原估 | 修正后 | 原因 |
|---|---|---|---|
| 登录 + 会话 | 4 天 | **2 天** | 不用处理会话级 Cookie 的复杂失效逻辑 |
| 课表 | 4 天 | **3 天** | 表格结构固定，无数据时也要能渲染 |
| 选课 / 学分 | 4 天 | **3 天** | 直接吃 JSON |
| 成绩 | 2 天 | **2 天** | JSP 报表，建议 WebView |
| **合计** | 14 天 | **10 天** | — |

---

## 1. 站点测绘（实测）

### 1.1 域名拓扑

```
ccsut.cn
├── tls.ccsut.cn     超星 综合教学管理系统 v3（教务：课表/成绩/考试/选课）
├── auth.ccsut.cn    统一身份认证 CAS（Spring Boot + Angular SPA）  ← 真正的登录中枢
├── ehall.ccsut.cn   智慧校园门户 / 网关（/backstage）
└── passport2.chaoxing.com   学习通扫码认证（外部，超星云）
```

### 1.2 关键响应头指纹

| 探测 | 结果 | 含义 |
|---|---|---|
| `GET https://tls.ccsut.cn/` | `303 → /admin/login` | 全站除白名单外强制登录 |
| `Set-Cookie` | `uid=<uuid>; HttpOnly; Path=/`（**无 Max-Age/Expires**） | 网关会话 ID，**关浏览器即失效** |
| `Set-Cookie` | `route=<hex>` | 网关/负载均衡会话亲和 |
| `POST /admin/login`（失败） | `Set-Cookie: rememberMe=deleteMe` | **Apache Shiro** 框架指纹 |
| 页面模板 | `超星综合教学管理系统`，Thymeleaf 服务端渲染 | 后端 Java / Spring |
| 静态资源 | `/static/v3/*`、`/static/uadmin/*`、`/static/vendors/*` | jQuery + layui + 自研后台皮肤 |
| CAS 后端 | 404 返回 `{"timestamp":...,"status":404,"error":"Not Found","message":"No message available"}` | Spring Boot |
| CAS 前端 | Angular（`ng-login/main.*.js`，2.4 MB，webpack 混淆） | — |
| `auth.ccsut.cn` 响应头 | `strict-transport-security`、`x-envoy-upstream-service-time` | 前置 Envoy / nginx |

### 1.3 渲染方式（推理已修正）

**最初我推断"服务端渲染"，实测证明是错的。** 记录一下错在哪，避免再犯：

| 我当时的证据 | 我的推断 | 实际情况 |
|---|---|---|
| 登录页由 Thymeleaf 渲染，内联 `loginFsObj` 等变量 | 后端是 Java MVC | ✅ 对，但**只有登录页**是 |
| 前端栈是 jQuery + layui | jQuery 时代的服务端渲染页面 | ❌ 只对登录页成立 |
| `/admin/index` 返回 303 而非 JSON 401 | 路由是页面级 | ❌ 路径本来就不存在，303 是重定向到真首页 |
| 静态资源带 `?_t=` 版本戳 | 传统 MVC | ❌ Vue 项目也这么打点 |

**真实架构**：

```
/admin/  →  302  →  /frontend/views/student/xkPage/index.html
                        ↓
                    Vue + axios + element-ui + http-vue-loader
                        ↓
                    /admin/**  (JSON API，统一 {"ret":0,"msg":"success","data":{}})
```

- 前端：**Vue 2 + axios + element-ui**，组件用 `http-vue-loader` 运行时加载 `.vue`
- 后端：Spring Boot，接口全返回 JSON
- 认证：**纯 Cookie**（`withCredentials: true`），没有 token、没有签名、没有加密头

**结论：这是做原生的理想形态**，直接吃 JSON，不用解析 HTML 表格。

例外是**成绩**：走老式 JSP 报表引擎（`/report/reportJsp/showReportNoWord.jsp`），和 Vue 那套是两代技术栈并存。

### 1.4 三条登录通道

#### 通道 ① 学习通扫码（你现在用的）

```
GET  https://passport2.chaoxing.com/cloudscanlogin?pcrefer=...&mobiletip=教务管理系统
  ↓ 手机学习通扫一扫
GET  https://tls.ccsut.cn/admin/scanLogin?ticket=<超星票据>
  ↓ 失败会 302 →
GET  /admin/loginFailPage?errorCode=1001     # 1001=票据缺失/无效
GET  /admin/loginFailPage?errorCode=1009     # 1009=CAS ticket 校验失败
```

#### 通道 ② 账密直登（教务系统自带）

```
GET  /admin/login                    # 27,628 字节登录页
POST /admin/login
     username=学号
     password=<RSA-1024 PKCS#1 v1.5 加密后的 Base64>
     vcode=&jcaptchaCode=<超星滑块票据>&rememberMe=1
```

- RSA 公钥（页面内硬编码，1024 bit）：
  ```
  MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC8Tzf/AcQMsbV4KEiPm4kGalSFwuP5hPVkuhGEgXU+pfrstvMuvR8vt5bcoIu8rSj8ZWFK2W4Wi9yaj2W+VTQ531Kolw/F6H/tkmD67T5/hZ9m9RSPkY0welMqJDvGjgcUV5nODfLReOP9Vr8F7clC6a6zbxGIaPc/TeJJJnffzQIDAQAB
  ```
- 验证码：`captcha.chaoxing.com/load.min.js`，`captchaId = fdHguSojgSJag5B74ij8Bu8ZAzWlNgXM`（滑块/点选，**这是账密直登最烦的一步**）
- `rememberMe` 由页面 `.check` 复选框控制：勾上 → `rememberMe=1` → Shiro 下发 rememberMe Cookie（通常 30 天）

#### 通道 ③ 统一身份认证 CAS（**推荐走这条**）

```
GET  https://tls.ccsut.cn/admin/caslogin
  → 302 https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin

GET  https://auth.ccsut.cn/backstage/cas/login?service=...
  → HTML 里带 flowExecutionKey（每次刷新都变）

POST https://auth.ccsut.cn/backstage/cas/login
  Content-Type: application/x-www-form-urlencoded

  username=学号
  password=<16 字节密文的 Base64，前端 AES/SM4 加密>
  execution=<flowExecutionKey>
  _eventId=submit
  geolocation=
  captcha=
  rememberMe=true            ← 关键开关
  domain=auth.ccsut.cn
  tenantId=
  validateCode=

  → 302 Location: https://tls.ccsut.cn/admin/caslogin?ticket=ST-xxxx
GET 该 Location
  → 302 /admin/index + Set-Cookie（教务系统会话）
```

CAS 自身的配置接口（**无需登录**，实测）：

```
GET https://auth.ccsut.cn/backstage/app-manager/sysConfig/getLoginConfig
```

返回（节选，真实值）：

```json
{
  "login_mode_method_sort": ["scan","password","validateCode"],
  "login_mode_scan": "1",
  "login_mode_pwd": "1",
  "login_mode_idcard": "1",
  "login_third_qywechat": "1",
  "login_pwd_timeout_days": "180",
  "login_pwd_timeout_enable": "0",
  "login_tactics_count": "5",
  "login_pwd_strength_length": "8",
  "login_qr_code_url": "/backstage/app-manager/apk/download",
  "login_auth_by_wechat_gateway": "https://ehall.ccsut.cn/backstage"
}
```

解读：
- 三种登录方式全开（扫码 / 账密 / 短信验证码）
- **`login_pwd_timeout_enable = 0`**：密码不过期
- **`login_tactics_count = 5`**：连续错 5 次锁定，自动登录脚本要做失败退避
- `login_qr_code_url` 指向学校自己的 App APK 下载，说明学校已经做过一个壳

CAS 扫码登录的协议（如果你想让手机扫电脑二维码登录）：

```
GET  /backstage/cas/qr/getQRCodeUUID
     → {"success":true,"message":"操作成功!","data":"qrCodeLoginUUID-<uuid>"}

POST /backstage/cas/qr/findBindUser?qrCodeUUID=qrCodeLoginUUID-<uuid>
     → {"success":false,"message":"超时","data":3}      # 未扫码
     → 扫码并确认后返回用户绑定信息
```

### 1.5 已知接口清单

**CAS（auth.ccsut.cn）**

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/backstage/app-manager/project/info` | 学校信息、logo、主题、个人中心 URL |
| GET | `/backstage/app-manager/sysConfig/getLoginConfig` | 登录策略配置 |
| GET | `/backstage/app-manager/qrcode/generate?key=login&domain=...&ext=...` | 二维码图片 |
| GET | `/backstage/cas/qr/getQRCodeUUID` | 发起扫码登录 |
| POST | `/backstage/cas/qr/findBindUser` | 轮询扫码结果 |
| POST | `/backstage/cas/login` | 账密/验证码登录（表单） |
| POST | `/backstage/app-manager/notice/loginPage/queryListForPage` | 登录页公告 |
| GET | `/backstage/filecenter/file/<id>` | 文件/图片资源 |

**教务（tls.ccsut.cn）**

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/admin/login` | 登录页（白名单） |
| POST | `/admin/login` | 账密登录 |
| GET | `/admin/caslogin` | CAS 回调 |
| GET | `/admin/scanLogin` | 学习通扫码回调 |
| GET | `/admin/loginFailPage?errorCode=` | 失败页（1001/1009…） |
| GET | `/admin/forgetpass/index` | 找回密码 |
| GET | `/codegen/getCode?codetoken=` | 图形验证码（备用方案） |
| GET | `/admin/index` | 登录后首页 |

> 登录后的业务接口（课表、成绩、考试、选课、通知）全部在 `/admin/**` 下，需要有效会话才能枚举。
> 仓库里的 `tools/capture.mjs` 就是用来**用你自己的账号跑一次、把全部接口自动抓下来**的。

---

## 2. 为什么学习通每次都要扫码

三条独立原因，任一条都足以让你重复认证：

1. **网关 `uid` 是会话 Cookie**：`Set-Cookie: uid=...; HttpOnly; SameSite=lax`，**没有 `Max-Age` / `Expires`**。学习通 App 每次打开教务用的是新建 WebView，Cookie 罐子一销毁就归零。
2. **服务端会话短**：Shiro 会话默认 30 分钟无操作过期，教务系统这类系统通常就是这个值。你上午看课表、下午再进，中间早断了。
3. **学习通只提供"扫码"这一种免输密码的方式**：因为学习通自己已经登录了，扫码是它把身份传给超星教务的最短路径。它没有动力帮你持久化第三方 Cookie。

所以问题不在"必须扫码"，而在**没有东西替你保存会话**。

---

## 3. 三条路线对比

| | A. WebView 壳 | B. 协议级原生客户端 | C. PWA |
|---|---|---|---|
| 工期 | **1 天** | 2–6 周 | 2 小时 |
| 体验 | 网页 UI，但无扫码、有原生外壳 | 原生 UI，最好 | 网页 UI，最差 |
| 依赖 | 无 | 需要逆向登录加密 + 全部业务接口 | 无 |
| 抗改版 | 强（页面变了自己跟着变） | 弱（接口一改就崩） | 强 |
| 上手门槛 | 低 | 高 | 极低 |
| 推荐 | **先做这个** | 之后按需扩展 | 临时过渡 |

**建议：A 打底 + B 逐步替换**。先用壳解决"每次扫码"这个真痛点，跑通之后再一块块把课表、成绩换成原生页面。

---

## 4. 路线 A：WebView 壳（一天可用）

核心就三件事：

1. **Cookie 持久化**：把 `uid` / `route` / `JSESSIONID` / `rememberMe` 全部落盘，启动时注入。
2. **首次登录走"记住我"**：登录页勾上"记住我"，Shiro 会下发长有效期 `rememberMe` Cookie，即使 `uid` 过期也能免密重建会话。
3. **失效兜底**：检测到 `303 → /admin/login` 时，走 CAS 静默登录（见路线 B 的 CAS 部分），或弹出一次内嵌登录页。

代码见 `shell/`（Flutter）与 `tools/`（会话捕获/保活）。

### 关键实现点

```dart
// 1. 持久化：不要用默认的 CookieManager 内存态
final cookieManager = CookieManager.instance();
await cookieManager.setCookie(
  url: WebUri('https://tls.ccsut.cn'),
  name: 'uid', value: savedUid,
  domain: '.ccsut.cn', path: '/', isHttpOnly: true, isSecure: true,
);

// 2. 每次页面开始加载时判断是否被踢回登录页
if (url.path.startsWith('/admin/login')) {
  await restoreSession();       // 注入 Cookie 后 reload
}

// 3. 定期保活（前台每 10 分钟 ping 一次 /admin/index）
```

---

## 5. 路线 B：协议级客户端

### 5.1 会话获取（推荐 CAS，不用处理滑块）

CAS 的好处是**没有图形验证码**（只有短信验证码一种可选方式），账密直接能过。教务系统自带的 `/admin/login` 要过超星滑块，脚本化很痛苦。

一个完整的最小实现（Node.js，纯 HTTP，无浏览器）：

```js
// 1. 拿 flowExecutionKey
const html = await (await fetch(LOGIN_URL)).text();
const execution = html.match(/flowExecutionKey:\s*"([^"]+)"/)[1];

// 2. 加密密码（需要 AES key，见 5.2）
const encPwd = encryptPassword(plainPassword);

// 3. 提交
const res = await fetch('https://auth.ccsut.cn/backstage/cas/login', {
  method: 'POST',
  redirect: 'manual',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    username, password: encPwd, execution, _eventId: 'submit',
    geolocation: '', captcha: '', rememberMe: 'true',
    domain: 'auth.ccsut.cn', tenantId: '', validateCode: '',
  }),
});

// 4. ticket → 教务会话
const ticketUrl = res.headers.get('location');   // https://tls.ccsut.cn/admin/caslogin?ticket=ST-...
const cookies = await followAndCollectCookies(ticketUrl);
```

### 5.2 密码加密

实测：明文 `Test123456`（10 字节）→ 密文 Base64 `dzZfo30c6gw7cM/M2Komow==`（**16 字节**）。

16 字节块 = **AES-128 / SM4 的 ECB 模式**（或带固定 IV 的 CBC，密文里不含 IV）。前端 bundle 里能搜到 `_AES_KEY`、`_AES_IV`、`Pkcs7`、`ECB`、`CBC` 等符号，说明是 crypto-js 系的 AES。

**但你不必自己还原密钥**：`tools/capture.mjs` 用浏览器上下文完成登录，页面自己加密，脚本只负责收 Cookie。要纯 HTTP 实现时，用下面这行在登录页把它捞出来：

```js
// 在 auth.ccsut.cn 登录页控制台执行，拿到加密函数后直接调用
const enc = (pwd) => {
  // 触发一次真实提交前，hook XHR 拿 body，同时把 pwd 换成已知值反推
  // 或者直接 hook 加密函数：
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    if (u.includes('/cas/login')) {
      const origSend = this.send;
      this.send = function (body) {
        console.log('BODY:', body);   // 已知明文 → 密文，用于验证算法
        return origSend.apply(this, arguments);
      };
    }
    return origOpen.apply(this, arguments);
  };
};
```

### 5.3 业务接口

登录后跑 `tools/capture.mjs`，它会把所有 XHR/fetch 的 **方法 + URL + 请求体 + 响应体**写进 `out/api.json`，你按功能分类即可。

已知会出现的模块（超星教务 v3 标准布局）：`/admin/course/*`（课表）、`/admin/score/*`（成绩）、`/admin/exam/*`（考试）、`/admin/notice/*`（通知）、`/admin/student/*`（学籍）。

---

## 6. 落地清单

```
ccsut/
├── README.md                  ← 本文
├── package.json
├── tools/
│   ├── capture.mjs            登录 + 抓全部接口 + 导出 cookie（核心工具）
│   ├── keepalive.mjs          会话保活 / 失效检测
│   └── console-login.js       浏览器控制台一键登录（零依赖）
├── shell/                     Flutter WebView 壳
│   ├── pubspec.yaml
│   └── lib/main.dart
└── out/                       运行产物（cookie、接口清单）
```

### 快速开始

```bash
# 1. 抓会话（会打开浏览器，你手动登录一次）
npm i
npx playwright install chromium
node tools/capture.mjs --out ./out

# 2. 之后用抓到的会话跑原生客户端 / 保活
node tools/keepalive.mjs --state ./out/state.json
```

### 注意事项

- **别把账号密码写进代码**。用 Keychain / Android Keystore / `flutter_secure_storage`。
- **错 5 次会锁**（`login_tactics_count=5`），自动登录失败要退避，不要重试轰炸。
- **Cookie 是凭证**，`out/state.json` 等同密码，别提交到 Git（`.gitignore` 已排除 `out/`）。
- 学校有自己的 App（`/backstage/app-manager/apk/download`），可以先装来看看它怎么处理会话，能省不少事。
- 教务系统是学校生产环境，**只读接口随便调，写操作（选课、退课、提交评教）不要自动化**——出事是学籍问题。

