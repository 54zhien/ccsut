import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function req(p, {method="GET", form=null}={}){
  const headers={cookie:ck,"user-agent":UA};
  let body;
  if(form){ headers["content-type"]="application/x-www-form-urlencoded; charset=UTF-8"; body=form; }
  const r = await fetch("https://tls.ccsut.cn"+p,{headers,redirect:"manual",method,body});
  const buf=Buffer.from(await r.arrayBuffer());
  return {s:r.status, loc:r.headers.get("location")||"", size:buf.length, text:buf.toString("utf8")};
}

// ---- 1. 课表页里的学期选项 ----
const kb = await req("/admin/xsd/pkgl/xskb/queryKbForXsd");
console.log("课表页:", kb.s, kb.size, "bytes");
const opts = [...kb.text.matchAll(/<option[^>]*value="([^"]*)"[^>]*>([^<]*)</g)].map(m=>`${m[1]}=${m[2]}`);
console.log("学期选项(前8):", opts.slice(0,8).join(" | ") || "无");
const xnxqInput = kb.text.match(/id="xnxq"[^>]*value="([^"]*)"/);
console.log("默认 xnxq:", xnxqInput ? xnxqInput[1] : "未找到");

// 课表 td 里有内容吗
const tds = [...kb.text.matchAll(/<td[^>]*>([\s\S]{0,200}?)<\/td>/g)].map(m=>m[1].replace(/<[^>]+>/g,"").trim()).filter(Boolean);
console.log("非空 td 数:", tds.length, " 前5:", tds.slice(0,5).join(" / "));

await sleep(800);

// ---- 2. 选课初始化 ----
const lv2 = await req("/admin/xsd/xk/listV2", {method:"POST", form:""});
console.log("\nlistV2:", lv2.s, lv2.size, "bytes");
try {
  const j = JSON.parse(lv2.text);
  console.log("  ret:", j.ret, " xsxm:", j.data?.xsxm, " xnxq:", j.data?.xkxnxq);
  console.log("  pcencs:", JSON.stringify(j.data?.pcencs || {}).slice(0,160));
  console.log("  cxxkwkcts:", j.data?.cxxkwkcts);
} catch(e){ console.log("  解析失败:", lv2.text.slice(0,160)); }

await sleep(800);

// ---- 3. 成绩相关路径试探 ----
for (const p of ["/admin/xsd/xsdzgcjcx/xscjcx", "/admin/xsd/xsdzgcjcx/xscjdy", "/admin/xsd/cjcx/xscjcx"]) {
  const r = await req(p);
  console.log(`\n${p} => ${r.s} ${r.size}b ${r.loc ? "-> "+r.loc.slice(0,90) : ""}`);
  await sleep(600);
}
