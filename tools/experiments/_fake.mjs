import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport:{width:390,height:844}, userAgent:"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148" });
const page = await ctx.newPage();
const net = [];
page.on("request", r => { if (r.method()==="POST") net.push(`${r.url()}`); });
page.on("response", async r => {
  if (r.request().method()==="POST") {
    const t = await r.text().catch(()=> "");
    net.push(`  ← ${r.status()} ${t.slice(0,200).replace(/\s+/g," ")}`);
  }
});

await page.goto("https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin", { waitUntil:"networkidle", timeout:40000 }).catch(()=>{});

const r = await page.evaluate(async () => {
  const sleep = ms => new Promise(r=>setTimeout(r,ms));
  const setVal = (el,v) => {
    const s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,"value").set;
    s.call(el,v); ["input","change","keyup","blur"].forEach(t=>el.dispatchEvent(new Event(t,{bubbles:true})));
  };
  let tab=null;
  for (let i=0;i<40&&!tab;i++){ tab=[...document.querySelectorAll(".ant-tabs-tab")].find(t=>(t.textContent||"").includes("密码登录")); if(!tab) await sleep(200); }
  if (!tab) return "no-tab";
  if (!tab.classList.contains("ant-tabs-tab-active")) { tab.click(); await sleep(900); }
  let pwd=null;
  for (let i=0;i<30&&!pwd;i++){ pwd=[...document.querySelectorAll("input")].find(e=>e.type==="password"&&e.offsetWidth>0); if(!pwd) await sleep(200); }
  if (!pwd) return "no-form";
  const user=[...document.querySelectorAll("input")].find(e=>/用户名|手机号/.test(e.placeholder||""));
  setVal(user,"00000000000");           // 假账号，避免影响真实账号锁定计数
  setVal(pwd,"wrongpass123");
  await sleep(400);
  const btn=[...document.querySelectorAll("button")].find(b=>(b.textContent||"").trim()==="登录");
  btn.click();
  return "clicked";
});
console.log("注入:", r);

await page.waitForTimeout(6000);
const after = await page.evaluate(() => ({
  url: location.href,
  text: document.body.innerText.slice(0, 500),
  errors: [...document.querySelectorAll(".ant-form-item-explain,.ant-message,.error,[class*=error],[class*=alert]")]
          .map(e=>(e.textContent||"").trim()).filter(Boolean).slice(0,6),
}));
console.log("\n提交后 URL:", after.url);
console.log("\n页面文字:\n" + after.text);
console.log("\n错误元素:", after.errors.join(" | ") || "无");
console.log("\n=== 网络 ===");
console.log(net.slice(-6).join("\n"));
await browser.close();
