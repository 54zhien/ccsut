import fs from "node:fs/promises";
const html = await fs.readFile("./out/kb.html","utf8");
console.log("size:", html.length);

// 找 JS 变量赋值（可能是课表数据）
const vars = [...html.matchAll(/var\s+(\w+)\s*=\s*(\[[\s\S]{0,120}|'[^']{0,80}'|"[^"]{0,80}"|\{[\s\S]{0,80})/g)]
  .map(m => ({ name: m[1], val: m[2].replace(/\s+/g," ").slice(0,90) }))
  .filter(v => /kb|cj|course|jx|list|data|arr|json/i.test(v.name));
console.log("\n=== 可疑 JS 变量 ===");
vars.slice(0,25).forEach(v => console.log(`  ${v.name} = ${v.val}`));

// 找 JSON 数组片段
const jsonArrays = [...html.matchAll(/\[\s*\{[^\]]{20,400}\}\s*\]/g)].map(m=>m[0].slice(0,200));
console.log("\n=== 内联 JSON 数组 ===", jsonArrays.length, "个");
jsonArrays.slice(0,3).forEach(j=>console.log("  ", j.replace(/\s+/g," ")));

// 找课程名特征（如"课"字结尾的字符串）
const names = [...html.matchAll(/["']([\u4e00-\u9fa5]{2,25}[\u4e00-\u9fa5A-Z0-9（）()\-]{0,15})["']/g)].map(m=>m[1]);
const uniq = [...new Set(names)].filter(n=>!/^(星期|节次|上午|下午|晚上|请选择|备注|刷新|课程表|我的课表|返回|打印|导出|确定|取消)/.test(n));
console.log("\n=== 疑似课程/教师名 ===", uniq.length, "个");
console.log(uniq.slice(0,20).join(" | ") || "无");
