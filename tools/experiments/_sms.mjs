import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport:{width:390,height:844}, userAgent:"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148" });
const page = await ctx.newPage();
await page.goto("https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin", { waitUntil:"networkidle", timeout:40000 }).catch(()=>{});

const r = await page.evaluate(async () => {
  const sleep = ms => new Promise(r=>setTimeout(r,ms));
  // 等页签
  let tabs = [];
  for (let i=0;i<40;i++){ tabs = [...document.querySelectorAll(".ant-tabs-tab")]; if (tabs.length) break; await sleep(200); }
  const names = tabs.map(t=>(t.textContent||"").trim());
  // 点「验证码登录」
  const target = tabs.find(t=>(t.textContent||"").includes("验证码登录"));
  if (!target) return { ok:false, names };
  if (!target.classList.contains("ant-tabs-tab-active")) { target.click(); await sleep(1200); }
  await sleep(800);
  return {
    ok: true, names,
    inputs: [...document.querySelectorAll("input")].map((e,i)=>({
      i, type:e.type, ph:e.placeholder||"", vis: !!(e.offsetWidth||e.offsetHeight),
      cls:(e.className||"").toString().slice(0,50)
    })),
    buttons: [...document.querySelectorAll("button")].map(b=>({ text:(b.textContent||"").trim(), cls:(b.className||"").toString().slice(0,50) })).filter(b=>b.text),
    text: document.body.innerText.slice(0,300),
  };
});
console.log(JSON.stringify(r, null, 2));
await page.screenshot({ path: "./out/cas_sms.png", fullPage: true });
await browser.close();
