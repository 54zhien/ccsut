import fs from "node:fs/promises";
import { chromium } from "playwright";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ccs = state.cookies.filter(c=>c.domain.includes("ccsut.cn"));

const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport:{width:1280,height:900}, userAgent:"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36" });

// 把 TGC 等注入，让 ehall 走 CAS 单点
await ctx.addCookies(ccs.map(c => ({
  name: c.name, value: c.value,
  domain: c.domain, path: c.path || "/",
  secure: !!c.secure, httpOnly: !!c.httpOnly,
  expires: c.expires && c.expires > 0 ? c.expires : -1,
})));

const page = await ctx.newPage();
await page.goto("https://ehall.ccsut.cn/", { waitUntil: "networkidle", timeout: 45000 }).catch(()=>{});
await page.waitForTimeout(4000);

const info = await page.evaluate(() => ({
  url: location.href,
  title: document.title,
  text: document.body.innerText.slice(0, 900),
}));
console.log("URL:", info.url);
console.log("标题:", info.title);
console.log("\n=== 页面文字 ===\n" + info.text);
await page.screenshot({ path: "./out/ehall_now.png", fullPage: false });
await browser.close();
