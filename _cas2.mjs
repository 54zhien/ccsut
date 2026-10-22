import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
});
const page = await ctx.newPage();
await page.goto("https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin", { waitUntil: "networkidle", timeout: 40000 }).catch(()=>{});
await page.waitForTimeout(3500);

// 用通用方式找「密码登录」
const clicked = await page.evaluate(() => {
  const all = [...document.querySelectorAll("div,span,a,li,button,p")];
  const exact = all.filter(el => el.children.length === 0 && (el.textContent||"").trim() === "密码登录");
  if (!exact.length) return { ok:false, count:0 };
  const el = exact[0];
  const rect = el.getBoundingClientRect();
  el.click();
  el.parentElement?.click();
  return { ok:true, count: exact.length, tag: el.tagName, cls: (el.className||"").toString().slice(0,80), x: rect.x, y: rect.y };
});
console.log("点击结果:", JSON.stringify(clicked));

await page.waitForTimeout(2500);

const info = await page.evaluate(() => {
  const inputs = [...document.querySelectorAll("input")].map((el,i) => ({
    i, type: el.type, name: el.name, id: el.id,
    placeholder: el.placeholder || "",
    cls: (el.className||"").toString().slice(0,70),
    visible: !!(el.offsetWidth || el.offsetHeight),
  }));
  const btns = [...document.querySelectorAll("button,[type=submit],[class*=btn]")]
    .map(b => ({ tag:b.tagName, text:(b.textContent||"").trim().slice(0,20), cls:(b.className||"").toString().slice(0,50) }))
    .filter(b => b.text).slice(0,8);
  const checkboxes = [...document.querySelectorAll("[class*=checkbox],input[type=checkbox]")]
    .map(c => ({ tag:c.tagName, cls:(c.className||"").toString().slice(0,50), text:(c.textContent||"").trim().slice(0,20) })).slice(0,8);
  return { inputs, btns, checkboxes, bodyText: document.body.innerText.slice(0,250) };
});

console.log("\n=== 点击后 input (" + info.inputs.length + ") ===");
info.inputs.forEach(i => console.log(` ${i.i}. type=${i.type} name=${i.name} id=${i.id} ph=${i.placeholder} vis=${i.visible} cls=${i.cls}`));
console.log("\n=== 按钮 ===");
info.btns.forEach(b => console.log(` ${b.tag} "${b.text}" cls=${b.cls}`));
console.log("\n=== 复选框 ===");
info.checkboxes.forEach(c => console.log(` ${c.tag} "${c.text}" cls=${c.cls}`));
console.log("\n=== 页面文字 ===");
console.log(info.bodyText);

await page.screenshot({ path: "./out/cas_pwd.png", fullPage: true });
await browser.close();
