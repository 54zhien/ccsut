import fs from "node:fs/promises";
const js = await fs.readFile("./out/front__frontend_views_student_xkPage_js_index_js","utf8");
console.log("js size:", js.length);

// 所有 url: 赋值
const urls = [...js.matchAll(/url\s*:\s*['"`]([^'"`]+)['"`]/g)].map(m=>m[1]);
console.log("\n=== url: 赋值 ===");
console.log([...new Set(urls)].join("\n") || "无");

// 所有字符串里带 /admin 或 /frontend 的
const paths = [...js.matchAll(/['"`]((?:\.\.\/|\/)[A-Za-z0-9_\-./]{4,80})['"`]/g)].map(m=>m[1]);
console.log("\n=== 其他路径 ===");
console.log([...new Set(paths)].filter(p=>p.includes("admin")||p.includes("views")).join("\n") || "无");

// 函数名里带 xk/cj/kb 的
const fns = [...js.matchAll(/(?:function\s+|^\s*)(\w*(?:xk|Xk|XK|cj|Cj|CJ|kb|Kb|KB|score|Score)\w*)\s*[(:]/gm)].map(m=>m[1]);
console.log("\n=== 相关函数 ===");
console.log([...new Set(fns)].slice(0,40).join(" "));
