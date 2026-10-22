import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const r = await fetch("https://tls.ccsut.cn/frontend/views/student/xkPage/index.html",{headers:{cookie:ck,"user-agent":UA}});
const html = await r.text();
await fs.writeFile("./out/xkpage_nav.html", html);
console.log("size:", html.length);

// 菜单/链接
const hrefs = [...html.matchAll(/href="([^"]+)"/g)].map(m=>m[1]).filter(h=>h.includes("/admin/")||h.includes("views"));
console.log("\n=== admin/views 链接 ===");
console.log([...new Set(hrefs)].join("\n") || "无");

// iframeUrl 赋值
const iframes = [...html.matchAll(/iframeUrl\s*=\s*['"]([^'"]+)['"]/g)].map(m=>m[1]);
console.log("\n=== iframeUrl ===");
console.log([...new Set(iframes)].join("\n") || "无");

// 菜单文字
const menu = [...html.matchAll(/data-url="([^"]+)"[^>]*>([^<]{1,20})</g)].map(m=>`${m[2].trim()} -> ${m[1]}`);
console.log("\n=== data-url 菜单 ===");
console.log([...new Set(menu)].slice(0,30).join("\n") || "无");
