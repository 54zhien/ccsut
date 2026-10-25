#!/usr/bin/env node
/**
 * keepalive.mjs — 会话保活 / 失效检测 / 存活时长测量
 *
 * 两种用法，目的完全不同：
 *
 *   ① 保活（让会话永不掉线）
 *      node tools/keepalive.mjs --state ./out/state.json --watch
 *      默认每 10 分钟打一次卡，服务端会话会被不断续期。
 *
 *   ② 测服务端空闲超时（想知道"到底能撑多久"）
 *      node tools/keepalive.mjs --state ./out/state.json --watch --interval 1800
 *      每 30 分钟才探一次，第一次报失效的时间点 ≈ 服务端 session timeout。
 *
 *   单次检查：node tools/keepalive.mjs --state ./out/state.json
 *
 * 退出码：0=有效  2=失效  1=出错
 */

import fs from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const flag = (n, d = null) => {
  const i = args.indexOf(`--${n}`);
  if (i === -1) return d;
  const v = args[i + 1];
  return v && !v.startsWith('--') ? v : true;
};

const STATE_PATH = flag('state', './out/state.json');
const WATCH = !!flag('watch', false);
const INTERVAL = Number(flag('interval', 600)) * 1000;
const LOG_PATH = flag('log', null);

// /admin/index 在该部署是 303 中转页，永远无法判活；
// getXlzc 才是判活探针：会话有效返回 {"ret":0,...}，失效时 302 登录页
const PROBE = 'https://tls.ccsut.cn/admin/api/getXlzc';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const startedAt = Date.now();
let lastOkAt = null;
let pingCount = 0;
const timeline = [];

/** 把毫秒转成 1h23m 这种紧凑格式 */
function human(ms) {
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d) return `${d}d${h}h`;
  if (h) return `${h}h${m}m`;
  if (m) return `${m}m${s % 60}s`;
  return `${s}s`;
}

function cookieHeader(cookies) {
  return cookies
    .filter((c) => c.domain.includes('ccsut.cn'))
    .map((c) => `${c.name}=${c.value}`)
    .join('; ');
}

async function checkOnce(state) {
  const startedAt = Date.now();
  const res = await fetch(PROBE, {
    method: 'GET',
    redirect: 'manual',
    headers: { cookie: cookieHeader(state.cookies), 'user-agent': UA, accept: 'application/json' },
  });

  // 服务端可能在响应里刷新 Cookie，合并回去
  let refreshed = 0;
  for (const sc of res.headers.getSetCookie?.() ?? []) {
    const [pair] = sc.split(';');
    const i = pair.indexOf('=');
    if (i < 0) continue;
    const name = pair.slice(0, i).trim();
    const value = pair.slice(i + 1).trim();
    const hit = state.cookies.find((c) => c.name === name && c.domain.includes('ccsut.cn'));
    if (hit && hit.value !== value) {
      hit.value = value;
      refreshed++;
    }
  }

  const location = res.headers.get('location') ?? '';
  let alive = res.status === 200 && !location.includes('/admin/login');
  if (alive) {
    // getXlzc 必须以 {"ret":0} 收尾；200 但 body 是登录 HTML 也算失效
    try {
      alive = JSON.parse(await res.text()).ret === 0;
    } catch {
      alive = false;
    }
  }
  return { alive, status: res.status, location, refreshed, ms: Date.now() - startedAt };
}

async function main() {
  const raw = (await fs.readFile(STATE_PATH, 'utf8')).replace(/^\uFEFF/, '');
  const state = JSON.parse(raw);
  const totalCookies = state.cookies.filter((c) => c.domain.includes('ccsut.cn')).length;
  if (!totalCookies) {
    console.error('✗ state.json 里没有 ccsut.cn 的 Cookie，先跑 tools/capture.mjs');
    process.exit(1);
  }

  if (!WATCH) {
    const r = await checkOnce(state);
    const stamp = new Date().toLocaleString('zh-CN', { hour12: false });
    if (r.alive) {
      console.log(`[${stamp}] ✓ 有效  HTTP ${r.status}  ${r.ms}ms  刷新 Cookie ${r.refreshed} 个`);
      process.exit(0);
    }
    console.log(`[${stamp}] ✗ 失效  HTTP ${r.status} → ${r.location || '(无跳转)'}`);
    console.log('           → 重登：node tools/capture.mjs');
    process.exit(2);
  }

  console.log(`保活模式启动，每 ${INTERVAL / 1000}s 探一次`);
  console.log(`探针：${PROBE}`);
  console.log(`Cookie：${totalCookies} 条 ccsut.cn\n`);

  let alive = true;
  for (;;) {
    pingCount++;
    let line;
    try {
      const r = await checkOnce(state);
      alive = r.alive;
      const t = `+${human(Date.now() - startedAt)}`;
      if (r.alive) {
        lastOkAt = Date.now();
        line = `${t.padEnd(10)} ✓ 有效   ${String(r.ms).padStart(5)}ms   刷新 ${r.refreshed}`;
      } else {
        line = `${t.padEnd(10)} ✗ 失效   HTTP ${r.status} → ${r.location || '(无跳转)'}`;
        if (lastOkAt) {
          line += `\n           上次成功：${new Date(lastOkAt).toLocaleString('zh-CN', { hour12: false })}`;
          line += `\n           有效存活：约 ${human(lastOkAt - startedAt)}`;
          line += `\n           → 这个数字接近服务端空闲超时`;
        }
      }
    } catch (e) {
      line = `+${human(Date.now() - startedAt)} ⚠ 网络错误 ${e.message}`;
    }

    console.log(line);
    timeline.push({ at: new Date().toISOString(), line });
    await fs.writeFile(STATE_PATH, JSON.stringify(state, null, 2)).catch(() => {});

    if (LOG_PATH) {
      await fs.mkdir(path.dirname(path.resolve(LOG_PATH)), { recursive: true }).catch(() => {});
      await fs.appendFile(path.resolve(LOG_PATH), line + '\n').catch(() => {});
    }

    // 失效后不再空转
    if (!alive && flag('stop-on-fail', true) !== false) {
      console.log('\n会话已失效，停止探测。重新登录：node tools/capture.mjs');
      process.exit(2);
    }

    await new Promise((r) => setTimeout(r, INTERVAL));
  }
}

main().catch((e) => {
  console.error('✗', e.message);
  process.exit(1);
});
