import fs from "node:fs/promises";
import { chromium } from "playwright";

const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
await ctx.addCookies(state.cookies);
const page = await ctx.newPage();

const hops = [];
page.on("response", r => {
  if (r.request().resourceType() === "document")
    hops.push(`${r.status()} ${r.url()}`);
});

// 1) 成绩导出入口
await page.goto("https://tls.ccsut.cn/admin/xsd/xsdzgcjcx/xscjdy", { waitUntil: "networkidle", timeout: 30000 }).catch(()=>{});
await page.waitForTimeout(2000);
console.log("=== 跳转链 ===");
console.log(hops.join("\n"));
console.log("\n最终 URL:", page.url());
const txt = await page.evaluate(() => document.body.innerText.slice(0, 600));
console.log("\n页面文本:\n" + txt);
await page.screenshot({ path: "./out/score.png", fullPage: true });

// 2) 试各种成绩路径
console.log("\n=== 路径探测 ===");
for (const p of [
  "/admin/xsd/xsdzgcjcx/index",
  "/admin/xsd/xsdzgcjcx/xscjcx",
  "/admin/xsd/xsdzgcjcx/xscj",
  "/admin/xsd/cjcx/index",
  "/admin/xsd/xscj/index",
  "/admin/xsd/xsdzgcjcx/xscjdyb",
]) {
  const r = await ctx.request.get("https://tls.ccsut.cn" + p, { maxRedirects: 0 }).catch(()=>({status:()=>"ERR", headers:()=>({})}));
  console.log(`${String(r.status()).padEnd(5)} ${p}` + (r.headers().location ? " -> " + r.headers().location.slice(0,70) : ""));
}

await browser.close();
