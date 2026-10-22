import fs from "node:fs/promises";
const j = JSON.parse(await fs.readFile("./out/kb_data.json","utf8"));
const arr = j.data;

// djc 范围
const djcs = [...new Set(arr.map(o=>o.djc))].sort((a,b)=>a-b);
console.log("djc 取值:", djcs.join(","));

// xingqi 范围
const xqs = [...new Set(arr.map(o=>o.xingqi))].sort((a,b)=>a-b);
console.log("xingqi 取值:", xqs.join(","));

// 按 大节=(djc+1)/2 分组，看每个 (星期,大节) 有几门不同课程
const strip = s => (s||"").replace(/<[^>]+>/g,"").trim();
const map = {};
for (const o of arr) {
  const big = Math.max(1, Math.min(4, Math.floor((o.djc + 1) / 2)));
  const key = `周${o.xingqi}-大节${big}`;
  (map[key] ||= []).push(strip(o.kcmc));
}
console.log("\n=== (星期,大节) → 课程 ===");
Object.entries(map).sort().forEach(([k, list]) => {
  const uniq = [...new Set(list)];
  console.log(`${k}: ${list.length}条 / ${uniq.length}门  ${uniq.join(" , ")}`);
});

// 同一天同一大节里，不同 djc 是否真的是同一门课
console.log("\n=== 检查 周1 的 djc 分布 ===");
arr.filter(o=>o.xingqi===1).forEach(o=>{
  console.log(`  djc=${o.djc} big=${Math.floor((o.djc+1)/2)}  ${strip(o.kcmc)}  ${o.zc}  ${strip(o.croommc)}`);
});
