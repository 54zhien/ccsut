import fs from "node:fs/promises";
import { chromium } from "playwright";

const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 1600 } });
await ctx.addCookies(state.cookies);

const page = await ctx.newPage();
const api = [];
page.on("response", async r => {
  const u = r.url();
  if (u.includes("/admin/") || u.includes("/api/")) {
    api.push(`${r.status()} ${r.request().method()} ${new URL(u).pathname}${new URL(u).search}`);
  }
});

await page.goto("https://tls.ccsut.cn/admin/xsd/pkgl/xskb/queryKbForXsd", { waitUntil: "networkidle", timeout: 30000 });
await page.waitForTimeout(2500);

await page.screenshot({ path: "./out/kb_render.png", fullPage: true });

const info = await page.evaluate(() => {
  const txt = document.body.innerText;
  const cells = [...document.querySelectorAll("td")].map(td => (td.innerText || "").trim()).filter(Boolean);
  return {
    title: document.title,
    url: location.href,
    bodyLen: txt.length,
    cellCount: cells.length,
    sample: cells.slice(0, 20),
    hasCourse: /[\u4e00-\u9fa5]{3,}（|教师|教室|学分/.test(txt),
  };
});

console.log(JSON.stringify(info, null, 2));
console.log("\n=== 页面发出的请求 ===");
console.log([...new Set(api)].join("\n"));

await browser.close();
