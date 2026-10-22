import fs from "node:fs/promises";
import { chromium } from "playwright";

const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 1600 } });
await ctx.addCookies(state.cookies);

const page = await ctx.newPage();
let payload = null;
page.on("response", async r => {
  if (r.url().includes("sdpkkbList")) {
    try { payload = await r.json(); } catch(e) { payload = { err: e.message }; }
  }
});

await page.goto("https://tls.ccsut.cn/admin/xsd/pkgl/xskb/queryKbForXsd", { waitUntil: "networkidle", timeout: 30000 });
await page.waitForTimeout(3000);

// 页面里的 xhid
const xhid = await page.evaluate(() => {
  const html = document.documentElement.innerHTML;
  const m = html.match(/xhid\s*[=:]\s*['"]?([A-Za-z0-9]{20,})/);
  const input = document.querySelector('#xhid, input[name=xhid]');
  return { fromRegex: m ? m[1] : null, fromInput: input ? input.value : null };
});
console.log("xhid:", JSON.stringify(xhid));

if (payload) {
  await fs.writeFile("./out/kb_data.json", JSON.stringify(payload, null, 2));
  console.log("\n=== sdpkkbList 响应结构 ===");
  console.log("顶层 keys:", Object.keys(payload).join(", "));
  const s = JSON.stringify(payload);
  console.log("大小:", s.length, "bytes");
  console.log("前 1200 字符:");
  console.log(s.slice(0, 1200));
} else {
  console.log("\n未捕获到 sdpkkbList");
}

await browser.close();
