import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function raw(url, body){
  const r = await fetch(url,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body});
  return await r.text();
}
// 拿 pcenc
const init = await raw("https://tls.ccsut.cn/admin/xsd/xk/listV2", "");
const encs = JSON.parse(init).data.pcencs;
const [pcid, pcenc] = Object.entries(encs)[1];

const base = "https://tls.ccsut.cn/admin/xsd/xk/listjxbDataV2";
const fields = {from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""};

// A: URLSearchParams（curl 行为）
const a = new URLSearchParams(fields).toString();
const ra = JSON.parse(await raw(base, a));
console.log("A URLSearchParams  →", ra.data?.initData?.length ?? 0, "门  body长度", a.length);

// B: 模拟 Swift urlEncoded —— urlQueryAllowed 保留 / , ; : @
function swiftEnc(s){
  const keep = /[A-Za-z0-9\-._~!$'()*,;:@\/]/;
  return [...s].map(ch => keep.test(ch) ? ch : encodeURIComponent(ch)).join("");
}
const b = Object.entries(fields).map(([k,v])=>`${swiftEnc(k)}=${swiftEnc(v)}`).join("&");
const rb = JSON.parse(await raw(base, b));
console.log("B Swift式编码     →", rb.data?.initData?.length ?? 0, "门  body长度", b.length);
console.log("\npcenc 长度:", pcenc.length);
console.log("pcenc 前80:", pcenc.slice(0,80));
console.log("A 里 pcenc 段:", a.match(/pcenc=([^&]*)/)[1].slice(0,80));
console.log("B 里 pcenc 段:", b.match(/pcenc=([^&]*)/)[1].slice(0,80));
