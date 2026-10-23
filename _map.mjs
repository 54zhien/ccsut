import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";

async function probe(path) {
  try {
    const r = await fetch("https://tls.ccsut.cn" + path, {
      headers: { cookie: ck, "user-agent": UA },
      redirect: "manual",
    });
    const loc = r.headers.get("location") || "";
    const text = r.status === 200 ? await r.text() : "";
    const title = text.match(/<title>([^<]*)<\/title>/i)?.[1]?.trim() || "";
    const landed = /\/admin\/login|loginFailPage/.test(loc);
    return { s: r.status, loc, len: text.length, title, landed };
  } catch (e) { return { s: 0, loc: "", len: 0, title: "ERR", landed: false }; }
}

const paths = [
  "/admin/",
  "/admin/xsd/xsjbxx/xsjbxx",
  "/admin/xsd/xsjbxx/getXsjbxx",
  "/admin/xsd/pyfa/pyfa",
  "/admin/xsd/ksap/ksap",
  "/admin/xsd/pjxx/pjxx",
  "/admin/xsd/kxjs/kxjs",
  "/admin/xsd/xk/xk",
  "/admin/xsd/pkgl/xskb/xskb",
  "/admin/ydd/inf/showScore",
  "/admin/ydd/inf/showZgcj",
  "/admin/xsd/xkprocess/student/index",
  "/admin/xsd/xscjcx/xscjcx",
  "/admin/api/getXlzc",
];

console.log("路径".padEnd(40), "状态", " 落地页/标题");
console.log("-".repeat(92));
for (const p of paths) {
  const r = await probe(p);
  const note = r.landed ? "→ 登录页" : (r.loc ? "→ " + r.loc.replace("https://tls.ccsut.cn","").slice(0,42) : r.title);
  console.log(p.padEnd(40), String(r.s).padStart(4), " ", note);
}
