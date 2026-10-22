#!/usr/bin/env node
/**
 * 成绩接口探测
 *
 * 用法：
 *   node tools/probe-score.mjs
 *
 * 前提：out/state.json 是有效会话（先跑一次 tools/capture.mjs）
 *
 * 背景：
 *   PC 端成绩查询走 /admin/xsd/xsdzgcjcx/xscjdy → JSP 报表引擎，
 *   但学校的 .rpx 报表文件没部署，一进去就报「文件不存在」。
 *   学习通能查到成绩（含历史学期），说明还有一条 JSON 接口。
 *   这个脚本把候选路径全扫一遍，找出那条。
 */

import fs from "node:fs/promises";

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- 会话 ----------

let COOKIE = "";
try {
  const state = JSON.parse(await fs.readFile("./out/state.json", "utf8"));
  COOKIE = state.cookies
    .filter((c) => c.domain.includes("ccsut.cn"))
    .map((c) => `${c.name}=${c.value}`)
    .join("; ");
} catch {
  console.error("找不到 out/state.json，先跑：node tools/capture.mjs");
  process.exit(2);
}

async function req(path, { method = "GET", form = null, base = "https://tls.ccsut.cn" } = {}) {
  const headers = { cookie: COOKIE, "user-agent": UA, accept: "application/json, text/html, */*" };
  let body;
  if (form !== null) {
    headers["content-type"] = "application/x-www-form-urlencoded; charset=UTF-8";
    headers["x-requested-with"] = "XMLHttpRequest";
    body = form;
  }
  try {
    const r = await fetch(base + path, { method, headers, body, redirect: "manual" });
    const buf = Buffer.from(await r.arrayBuffer());
    return { s: r.status, loc: r.headers.get("location") || "", len: buf.length, text: buf.toString("utf8") };
  } catch (e) {
    return { s: "ERR", loc: "", len: 0, text: e.cause?.code || e.message };
  }
}

// ---------- 0. 会话是否活着 ----------

const probe = await req("/admin/");
// 注意：成功跳转的 URL 里 sfkqcas 参数编码了 cas/login，
// 不能简单用 includes("login") 判断，否则必然误判
const isLoginRedirect = /\/admin\/login|loginFailPage/.test(probe.loc);
const alive = probe.s === 302 && !isLoginRedirect;
console.log(`会话检查  /admin/  ${probe.s} ${isLoginRedirect ? "→ 登录页" : "→ " + probe.loc.slice(0, 48)}`);
if (!alive) {
  console.error("\n✗ 会话已失效。先跑一次：node tools/capture.mjs");
  process.exit(2);
}
console.log("✓ 会话有效\n");

// ---------- 1. 候选路径 ----------

const paths = [
  // 成绩模块的常见动作名
  ["/admin/xsd/xsdzgcjcx/xscjcx", "GET"],
  ["/admin/xsd/xsdzgcjcx/xscjlist", "GET"],
  ["/admin/xsd/xsdzgcjcx/xscjList", "GET"],
  ["/admin/xsd/xsdzgcjcx/list", "GET"],
  ["/admin/xsd/xsdzgcjcx/query", "GET"],
  ["/admin/xsd/xsdzgcjcx/getXscj", "GET"],
  ["/admin/xsd/xsdzgcjcx/getList", "GET"],
  ["/admin/xsd/xsdzgcjcx/xscj", "GET"],
  ["/admin/xsd/xsdzgcjcx/index", "GET"],

  // 独立成绩模块
  ["/admin/xsd/xscj/cx", "GET"],
  ["/admin/xsd/xscj/list", "GET"],
  ["/admin/xsd/xscj/query", "GET"],
  ["/admin/xsd/cjcx/cx", "GET"],
  ["/admin/xsd/cjcx/list", "GET"],
  ["/admin/xsd/cjcx/query", "GET"],
  ["/admin/xsd/cjgl/xscjcx", "GET"],
  ["/admin/xsd/cjgl/list", "GET"],

  // 综合查询（有些学校把成绩放这里）
  ["/admin/xsd/zhcx/xscj", "GET"],
  ["/admin/xsd/zhcx/cjcx", "GET"],

  // 移动端命名空间
  ["/m/admin/xsd/xsdzgcjcx/xscjcx", "GET"],
  ["/mobile/admin/xsd/xsdzgcjcx/xscjcx", "GET"],
  ["/app/admin/xsd/xsdzgcjcx/xscjcx", "GET"],
  ["/m/admin/xsd/cjcx/list", "GET"],

  // 成绩打印的下游：可能有 JSON 版
  ["/report/reportJsp/showReportNoWord.jsp?rpx=csgyxy/xsd/cjgl/dgxsyxcj.rpx&xnxq=2026-2027-1", "GET"],
];

console.log("=== 路径扫描 ===");
const hits = [];
for (const [p, method] of paths) {
  const r = await req(p, { method });
  const isLogin = r.s === 302 && r.loc.includes("login");
  const is404 = r.s === 404;
  const jsonish = r.text.trim().startsWith("{") || r.text.trim().startsWith("[");
  const tag = is404 ? "404 " : isLogin ? "登录" : jsonish ? "JSON" : String(r.s);
  console.log(`${tag.padEnd(5)} ${String(r.len).padStart(7)}b  ${p}`);
  if (!is404 && !isLogin && r.len > 50) {
    hits.push({ path: p, status: r.s, len: r.len, jsonish, sample: r.text.slice(0, 160) });
  }
  await sleep(550);
}

// ---------- 2. 看看命中项说了什么 ----------

if (hits.length) {
  console.log("\n=== 命中详情 ===");
  for (const h of hits) {
    console.log(`\n[${h.status}] ${h.path}  ${h.len}b ${h.jsonish ? "(JSON)" : ""}`);
    console.log("  " + h.sample.replace(/\s+/g, " "));
  }
} else {
  console.log("\n没有命中。成绩可能只走 JSP 报表，或者需要 POST 参数。");
}

// ---------- 3. getEndTime 那 316KB 到底是什么 ----------

console.log("\n=== getEndTime 结构（之前返回 316KB）===");
const initRaw = await req("/admin/xsd/xk/listV2", { method: "POST", form: "" });
let pcid = null;
try {
  const j = JSON.parse(initRaw.text);
  pcid = Object.keys(j.data?.pcencs || {})[0];
} catch {}
if (pcid) {
  const et = await req(`/admin/xsd/xk/getEndTime/2?pcid=${pcid}`);
  console.log(`状态 ${et.s}  长度 ${et.len}b`);
  const head = et.text.slice(0, 300).replace(/\s+/g, " ");
  console.log("开头: " + head);
  if (et.text.trim().startsWith("{")) {
    try {
      const j = JSON.parse(et.text);
      console.log("顶层 keys:", Object.keys(j).join(", "));
    } catch {}
  }
}
