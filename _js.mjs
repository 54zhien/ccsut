import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const base = "/frontend/views/student/xkPage/js/";

for (const f of ["ggxxk.js","xsdxk.js","cxxk.js","index.js"]) {
  const r = await fetch("https://tls.ccsut.cn" + base + f, { headers:{cookie:ck,"user-agent":UA} });
  const t = await r.text();
  await fs.writeFile("./out/xk_" + f, t, "utf8");
  console.log(`\n=== ${f}  ${r.status}  ${t.length}b ===`);

  // 所有 /admin/ 开头的路径
  const paths = [...new Set([...t.matchAll(/["'`](\/admin\/[A-Za-z0-9_\/]+)["'`]/g)].map(m=>m[1]))];
  if (paths.length) { console.log("接口:"); paths.forEach(p=>console.log("  " + p)); }

  // 选课/退课相关的函数名
  const fns = [...new Set([...t.matchAll(/(\w*(?:xk|Xk|选课|退选|submit|Submit)\w*)\s*[:=]\s*(?:function|\()/g)].map(m=>m[1]))].slice(0,12);
  if (fns.length) console.log("函数:", fns.join(", "));
}
