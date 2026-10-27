import fs from "node:fs/promises";
import { chromium } from "playwright";

const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 1400 } });
await ctx.addCookies(state.cookies);
const page = await ctx.newPage();

const apis = [];
page.on("response", r => {
  const u = r.url();
  if (u.includes("/backstage/") && !u.match(/\.(js|css|png|jpg|svg|woff2?|ttf)/)) {
    apis.push(`${r.status()} ${r.request().method()} ${new URL(u).pathname}`);
  }
});

await page.goto("https://ehall.ccsut.cn/backstage/auth/page/oafportal/", { waitUntil: "networkidle", timeout: 40000 }).catch(()=>{});
await page.waitForTimeout(4000);

console.log("最终 URL:", page.url());
const info = await page.evaluate(() => ({
  title: document.title,
  text: document.body.innerText.slice(0, 400),
  links: [...document.querySelectorAll('a,[onclick],[data-url]')].map(e=>(e.innerText||'').trim()).filter(Boolean).slice(0,30),
}));
console.log("title:", info.title);
console.log("\n页面文本:\n" + info.text);
console.log("\n可点击项:", info.links.join(" | "));
await page.screenshot({ path: "./out/ehall.png", fullPage: true });

console.log("\n=== backstage 请求 ===");
console.log([...new Set(apis)].slice(0, 25).join("\n"));

await browser.close();
