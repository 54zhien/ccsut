import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport:{width:390,height:844}, userAgent:"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148" });
const page = await ctx.newPage();
await page.goto("https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin", { waitUntil:"networkidle", timeout:40000 }).catch(()=>{});

// 模拟 App 注入脚本（新版本：先等 tab 渲染）
const studentNumber = process.env.CCSUT_SNO ?? "";
const result = await page.evaluate(async (studentNumber) => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const setVal = (el, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(el, v);
    ["input","change","keyup","blur"].forEach(t => el.dispatchEvent(new Event(t, { bubbles:true })));
  };

  // 1. 等 Angular 渲染 tab
  let pwdTab = null, waited = 0;
  for (let i = 0; i < 50 && !pwdTab; i++) {
    const tabs = [...document.querySelectorAll(".ant-tabs-tab")];
    pwdTab = tabs.find(t => (t.textContent || "").includes("密码登录"));
    if (!pwdTab) { await sleep(200); waited += 200; }
  }
  if (!pwdTab) return { step:"no-tab", waited };

  // 2. 切页签
  let switched = false;
  if (!pwdTab.classList.contains("ant-tabs-tab-active")) {
    pwdTab.click();
    await sleep(900);
    switched = true;
  }

  // 3. 等密码框
  let pwd = null;
  for (let i = 0; i < 40 && !pwd; i++) {
    pwd = [...document.querySelectorAll("input")].find(el => el.type === "password" && el.offsetWidth > 0);
    if (!pwd) await sleep(200);
  }
  if (!pwd) return { step:"no-form", waited, switched };

  // 4. 填表
  const user = [...document.querySelectorAll("input")].find(el => /用户名|手机号|账号/.test(el.placeholder||""));
  [(user ? {ok:true} : null)].filter(Boolean);
  if (user) setVal(user, studentNumber);

  // 5. 验证码检测
  const captcha = [...document.querySelectorAll("input")].find(el => /验证码/.test(el.placeholder||"") && el.offsetWidth > 0);
  const btn = [...document.querySelectorAll("button")].find(b => (b.textContent||"").trim() === "登录");

  return {
    step: "ok",
    waited, switched,
    hasUser: !!user, userPh: user?.placeholder,
    hasPwd: !!pwd,
    hasCaptcha: !!captcha,
    captchaVisible: captcha ? captcha.offsetWidth > 0 : false,
    hasButton: !!btn,
    buttonText: btn?.textContent?.trim(),
    allInputs: [...document.querySelectorAll("input")].map(e => `${e.type}:${e.placeholder||"-"}`),
  };
}, studentNumber);
console.log(JSON.stringify(result, null, 2));
await browser.close();
