import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function get(url){
  const r = await fetch(url,{headers:{cookie:ck,"user-agent":UA}});
  const t = await r.text();
  return {s:r.status, t};
}
const base = "https://tls.ccsut.cn/report/reportJsp/showReportNoWord.jsp";
const xhid = "8741a414b0774fa5a6606a85a87db4d0";
const pcid = "678d4ec099ed4eeba1cbe76b7ae07426";
const currentid = "aa6737834f024414b960d4de74dc3e57";

const cases = [
  ["xnxq=null（原样）", `?rpx=csgyxy/xsd/cjgl/dgxsyxcj.rpx&xnxq=null&xhid=${xhid}&pcid=${pcid}&sfxsgz=1&ggxx=&xhid=${xhid}&xdxz=&zhcjMin=0&zhcjMax=100&currentid=${currentid}`],
  ["xnxq=2026-2027-1", `?rpx=csgyxy/xsd/cjgl/dgxsyxcj.rpx&xnxq=2026-2027-1&xhid=${xhid}&pcid=${pcid}&sfxsgz=1&zhcjMin=0&zhcjMax=100&currentid=${currentid}`],
  ["换 rpx 名 xscj", `?rpx=csgyxy/xsd/cjgl/xscj.rpx&xnxq=2026-2027-1&xhid=${xhid}&currentid=${currentid}`],
  ["换 rpx 名 cjcx", `?rpx=csgyxy/xsd/cjgl/cjcx.rpx&xnxq=2026-2027-1&xhid=${xhid}&currentid=${currentid}`],
];
for (const [label, q] of cases) {
  const r = await get(base + q);
  const txt = r.t.replace(/<[^>]+>/g," ").replace(/\s+/g," ").trim();
  console.log(`\n[${label}] ${r.s} len=${r.t.length}`);
  console.log("  " + txt.slice(0, 200));
}
