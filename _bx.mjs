import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:form});
  return {s:r.status, text: await r.text()};
}
async function get(p){
  const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA}});
  return {s:r.status, text: await r.text()};
}

// 1) 批次 ID
const bx = await post("/admin/xsd/xk/xkpcxsmd/getbxpcid");
console.log("=== getbxpcid ===", bx.s);
console.log(bx.text.slice(0, 400));

// 2) 用真实 pcid 调用
let pcid = null, pcenc = null;
try { const j = JSON.parse(bx.text); pcid = j.data; } catch(e){}
console.log("\npcid =", pcid);

const init = await post("/admin/xsd/xk/listV2");
const ij = JSON.parse(init.text);
const encs = ij.data?.pcencs || {};
console.log("pcencs keys:", Object.keys(encs));
if (pcid && encs[pcid]) { pcenc = encs[pcid]; console.log("命中 pcenc, 长度", pcenc.length); }
else console.log("!! pcid 不在 pcencs 里");

// 3) 用正确的 pcid/pcenc 拉教学班
if (pcid && pcenc) {
  const form = new URLSearchParams({
    from:"ggxxk", kcmc:"", kcxz:"", jxms:"", kcgs:"", teacher:"",
    pcid: pcid, kkxq:"", kclb:"", pcenc: pcenc, kclx:""
  }).toString();
  const r = await post("/admin/xsd/xk/listjxbDataV2", form);
  const rj = JSON.parse(r.text);
  console.log("\n=== listjxbDataV2 ===", r.s, "ret:", rj.ret, "教学班:", rj.data?.initData?.length ?? 0);
  if (rj.data?.initData?.length) {
    const c = rj.data.initData[0];
    console.log("样例:", c.kcmc, "|", c.teacher, "|", c.xf, "学分 |", c.yxrl);
  }
}
