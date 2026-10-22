import fs from "node:fs/promises";
const raw = await fs.readFile("./out/kb_data.json","utf8");
const j = JSON.parse(raw);
const arr = j.data;
console.log("总条数:", arr.length);
console.log("ret:", j.ret, j.msg);

// 字段清单
const keys = new Set();
arr.forEach(o => Object.keys(o).forEach(k => keys.add(k)));
console.log("\n字段:", [...keys].join(", "));

// 星期 / 大节 分布
const grid = {};
arr.forEach(o => {
  const k = `周${o.xingqi}第${o.djc}节`;
  grid[k] = (grid[k]||0)+1;
});
console.log("\n=== 星期×节次分布 ===");
console.log(Object.entries(grid).sort().map(([k,v])=>`${k}:${v}`).join("  "));

// 周次格式样本
const zcs = [...new Set(arr.map(o=>o.zc))];
console.log("\n=== 周次格式（去重前12）===");
console.log(zcs.slice(0,12).join(" | "));

// 课程去重
const courses = [...new Set(arr.map(o => (o.kcmc||"").replace(/<[^>]+>/g,"")))];
console.log("\n=== 课程列表 ===");
console.log(courses.join("\n"));

// 一条完整样本
console.log("\n=== 样例 ===");
console.log(JSON.stringify(arr[0], null, 1).slice(0, 1200));
