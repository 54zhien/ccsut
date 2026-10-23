import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const get = async (p) => {
  const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA} });
  return { s: r.status, text: await r.text() };
};

const page = await get("/frontend/views/student/xkPage/index.html");
console.log("xkPage HTML:", page.s, page.text.length, "bytes");
await fs.writeFile("./out/xkpage.html", page.text, "utf8");

// 提取引用的脚本
const scripts = [...page.text.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map(m=>m[1]);
const links = [...page.text.matchAll(/<link[^>]+href=["']([^"']+)["']/gi)].map(m=>m[1]);
console.log("\n=== script ===");
scripts.forEach(s=>console.log("  " + s));
console.log("=== link ===");
links.forEach(s=>console.log("  " + s));

// HTML 内联的 JS 片段
const inline = [...page.text.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]{0,4000}?)<\/script>/gi)].map(m=>m[1]);
console.log("\n=== 内联 script 数:", inline.length, "===");
inline.forEach((js,i)=>{ if (/xj|xk|选课|submit|ajax|axios/i.test(js)) console.log(`[${i}] ` + js.slice(0,600).replace(/\s+/g," ")); });
