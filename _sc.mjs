import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";

async function post(name, p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  const sc = r.headers.getSetCookie ? r.headers.getSetCookie() : (r.headers.get("set-cookie")?[r.headers.get("set-cookie")]:[]);
  console.log(`\n[${name}] ${p} → ${r.status}`);
  console.log("  Set-Cookie:", sc.length ? sc.map(s=>s.split(";")[0]).join(" | ") : "无");
  return await r.text();
}

await post("入口", "/admin/");
const init = await post("listV2", "/admin/xsd/xk/listV2", "");
const j = JSON.parse(init);
const [pcid, pcenc] = Object.entries(j.data.pcencs)[1];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
await post("listjxbDataV2", "/admin/xsd/xk/listjxbDataV2", form);

// 两个 JSESSIONID 的 domain/path
console.log("\n=== state.json 里的 JSESSIONID ===");
state.cookies.filter(c=>c.name==="JSESSIONID").forEach(c=>{
  console.log(`  domain=${c.domain} path=${c.path} secure=${c.secure} httpOnly=${c.httpOnly} expires=${c.expires ? new Date(c.expires*1000).toISOString() : "session"} len=${c.value.length}`);
});
