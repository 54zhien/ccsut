import fs from "node:fs/promises";
import { chromium } from "playwright";

const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const browser = await chromium.launch({ channel: "chrome", headless: true });
const ctx = await browser.newContext({ viewport: { width: 430, height: 932 } });
await ctx.addCookies(state.cookies);
const page = await ctx.newPage();

const calls = [];
page.on("request", r => {
  const u = r.url();
  if (u.includes("/admin/") && !u.match(/\.(js|css|png|jpg|svg|woff)/)) {
    calls.push(`${r.method()} ${new URL(u).pathname}${new URL(u).search}`);
  }
});

await page.goto("https://tls.ccsut.cn/frontend/views/student/xkPage/index.html", { waitUntil: "networkidle", timeout: 40000 });
await page.waitForTimeout(3000);

// 页面结构
const info = await page.evaluate(() => {
  const tabs = [...document.querySelectorAll('.el-tabs__item, .ant-tabs-tab, [role=tab], .tab-item, li')]
    .map(e => (e.innerText||'').trim()).filter(t => t && t.length < 20);
  const btns = [...document.querySelectorAll('button, .el-button, a[onclick]')]
    .map(e => (e.innerText||'').trim()).filter(Boolean).slice(0, 25);
  return { title: document.title, tabs: [...new Set(tabs)].slice(0,20), buttons: [...new Set(btns)] };
});
console.log("=== 页面 ===");
console.log("title:", info.title);
console.log("tabs:", info.tabs.join(" | "));
console.log("buttons:", info.buttons.join(" | "));

// 依次点 tab，抓新增请求
for (const t of info.tabs.slice(0, 8)) {
  try {
    const el = page.locator(`text="${t}"`).first();
    if (await el.count()) {
      await el.click({ timeout: 2000 }).catch(()=>{});
      await page.waitForTimeout(1200);
    }
  } catch {}
}

await page.screenshot({ path: "./out/xkpage.png", fullPage: true });
await fs.writeFile("./out/xk_page.html", await page.content());

console.log("\n=== 所有 /admin 请求 ===");
console.log([...new Set(calls)].join("\n"));

await browser.close();
