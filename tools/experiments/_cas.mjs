import { chromium } from "playwright";
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({
  viewport: { width: 390, height: 844 },
  userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
});
const page = await ctx.newPage();

const url = "https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin";
await page.goto(url, { waitUntil: "networkidle", timeout: 40000 }).catch(()=>{});
await page.waitForTimeout(4000);

const info = await page.evaluate(() => {
  const inputs = [...document.querySelectorAll("input")].map(el => ({
    type: el.type, name: el.name, id: el.id,
    placeholder: el.placeholder || "",
    cls: (el.className || "").toString().slice(0,60),
    visible: !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length),
  }));
  const iframes = [...document.querySelectorAll("iframe")].map(f => f.src);
  const tabs = [...document.querySelectorAll('[class*="tab"],[role="tab"]')].map(e => (e.textContent||"").trim()).filter(Boolean).slice(0,10);
  const btns = [...document.querySelectorAll("button")].map(b => (b.textContent||"").trim()).filter(Boolean).slice(0,10);
  return {
    title: document.title,
    htmlLen: document.documentElement.outerHTML.length,
    bodyText: document.body.innerText.slice(0, 300),
    inputs, iframes, tabs, btns,
  };
});

console.log("title:", info.title);
console.log("HTML 长度:", info.htmlLen);
console.log("\n=== 页面文字 ===");
console.log(info.bodyText);
console.log("\n=== input 元素 (" + info.inputs.length + ") ===");
info.inputs.forEach((i,n)=>console.log(` ${n}. type=${i.type || "(空)"} name=${i.name} id=${i.id} placeholder=${i.placeholder} visible=${i.visible} class=${i.cls}`));
console.log("\n=== iframe ===", info.iframes.join(" | ") || "无");
console.log("=== tab ===", info.tabs.join(" | ") || "无");
console.log("=== button ===", info.btns.join(" | ") || "无");

await page.screenshot({ path: "./out/cas.png", fullPage: true });
await browser.close();
