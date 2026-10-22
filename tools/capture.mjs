#!/usr/bin/env node
/**
 * capture.mjs — 登录长工院教务，导出会话 + 接口清单 + 会话寿命体检
 *
 * 用法：
 *   node tools/capture.mjs                       启动 Chrome，手动登录
 *   node tools/capture.mjs --cdp 9222            连你已开的 Chrome
 *   node tools/capture.mjs --out ./out           指定输出目录
 *
 * 产物：
 *   out/session-report.md   会话体检报告（Cookie 有效期 / 能不能长期免登录）
 *   out/state.json          Playwright storageState —— 等同密码，勿外传
 *   out/api.json            全部请求
 *   out/summary.md          按模块归类的接口速查
 *   out/page-types.md       各页面返回 HTML 还是 JSON（决定能不能做原生）
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';

const args = process.argv.slice(2);
const flag = (name, def = null) => {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return def;
  const v = args[i + 1];
  return v && !v.startsWith('--') ? v : true;
};

const OUT_DIR = path.resolve(flag('out', './out'));
const CDP_PORT = flag('cdp', null);
const CAS =
  'https://auth.ccsut.cn/backstage/cas/login?service=' +
  encodeURIComponent('https://tls.ccsut.cn/admin/caslogin');
const JW = 'https://tls.ccsut.cn';

const IGNORE_EXT = /\.(js|css|png|jpe?g|gif|svg|ico|woff2?|ttf|eot|map|webp)(\?|$)/i;
const HOSTS = ['tls.ccsut.cn', 'auth.ccsut.cn', 'ehall.ccsut.cn'];

/** @type {Array<{method:string,url:string,requestBody:string|null,status:number|null,mime:string|null,bytes:number,responseBody:string|null}>} */
const records = [];
/** 页面侦察：登录后主要入口返回什么 */
const pageTypes = [];

function shouldRecord(url, rt) {
  if (IGNORE_EXT.test(url)) return false;
  if (!HOSTS.some((h) => url.includes(h))) return false;
  if (['image', 'font', 'stylesheet'].includes(rt)) return false;
  return true;
}

// ────────────────────────────── 会话体检 ──────────────────────────────
function diagnoseSession(state) {
  const now = Date.now() / 1000;
  const rows = state.cookies
    .filter((c) => c.domain.includes('ccsut.cn'))
    .map((c) => {
      const hasExp = c.expires && c.expires > 0;
      const days = hasExp ? (c.expires - now) / 86400 : null;
      return {
        name: c.name,
        domain: c.domain,
        path: c.path,
        httpOnly: !!c.httpOnly,
        secure: !!c.secure,
        sameSite: c.sameSite ?? '-',
        expiresAt: hasExp ? new Date(c.expires * 1000).toISOString().slice(0, 19).replace('T', ' ') : '会话级（关闭浏览器即失效）',
        days: days === null ? null : Number(days.toFixed(2)),
      };
    })
    .sort((a, b) => (b.days ?? -1) - (a.days ?? -1));

  const remember = rows.find((r) => /rememberMe/i.test(r.name));
  const jsession = rows.find((r) => /JSESSIONID|SESSION/i.test(r.name));
  const uid = rows.find((r) => r.name === 'uid');
  const tgc = rows.find((r) => r.name === 'TGC');
  const longLived = rows.filter((r) => r.days && r.days >= 1);

  // 判定：TGC 是最强信号 —— CAS 的票据授权 Cookie。
  // 只要它在，访问 /admin/caslogin?service=... 就会静默发新 ticket，用户零操作。
  let verdict;
  if (tgc && tgc.days && tgc.days > 1) {
    verdict = {
      level: 'A',
      title: '可以长期免登录（CAS 静默续期）',
      detail: `TGC 有效期 ${tgc.days} 天。App 存住它，到期前访问 /admin/caslogin 会自动发新 ticket、重建会话，用户完全无感。` +
        (remember ? `另有 rememberMe ${remember.days} 天兜底。` : ''),
    };
  } else if (remember && remember.days && remember.days > 1) {
    verdict = {
      level: 'A',
      title: '可以长期免登录（rememberMe）',
      detail: `rememberMe 有效期 ${remember.days} 天，冷启动注回即可。`,
    };
  } else if (jsession && jsession.days && jsession.days > 0.5) {
    verdict = {
      level: 'B',
      title: '服务端会话本身较长，可以靠保活续命',
      detail: `会话 Cookie 有效期 ${jsession.days} 天，配合定期保活可长期在线。`,
    };
  } else if (rows.some((r) => r.days === null)) {
    verdict = {
      level: 'C',
      title: '需要 Cookie 快照 + 保活',
      detail: '存在会话级 Cookie，需本地加密快照 + 冷启动注回 + 失效时静默重登。',
    };
  } else {
    verdict = { level: '?', title: '数据不足，看下表人工判断', detail: '' };
  }

  return { rows, verdict, remember, jsession, uid, tgc, longLived };
}

// ────────────────────────────── 主流程 ──────────────────────────────
async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });

  const browser = CDP_PORT
    ? await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`)
    : await chromium.launch({
        headless: !!flag('headless'),
        channel: flag('browser', 'chrome') === 'chromium' ? undefined : 'chrome',
        args: ['--start-maximized'],
      });

  const context = CDP_PORT ? browser.contexts()[0] : await browser.newContext({ viewport: null, locale: 'zh-CN' });
  const page = context.pages()[0] ?? (await context.newPage());

  // 抓包
  page.on('response', async (res) => {
    const req = res.request();
    const url = req.url();
    if (!shouldRecord(url, req.resourceType())) return;
    let responseBody = null;
    let mime = null;
    let bytes = 0;
    try {
      const headers = res.headers();
      mime = headers['content-type'] ?? null;
      if (mime && /json|text|xml|javascript/.test(mime) && !/image|font/.test(mime)) {
        const buf = await res.body();
        bytes = buf.length;
        responseBody = buf.length <= 200_000 ? buf.toString('utf8') : `<omitted ${buf.length} bytes>`;
      }
    } catch {
      /* ignore */
    }
    records.push({ method: req.method(), url, requestBody: req.postData() ?? null, status: res.status(), mime, bytes, responseBody });
  });

  console.log('\n==== 打开统一身份认证 ====');
  await page.goto(CAS, { waitUntil: 'domcontentloaded' });

  console.log(`
┌──────────────────────────────────────────────────────────────┐
│  在打开的浏览器里登录一次                                     │
│                                                              │
│  · 账号：学号                                                │
│  · 首次默认密码：身份证后六位（末位 X 改 0）                  │
│  · ⚠ 必须勾上「记住账号」「记住密码」                          │
│  · ⚠ 如果系统强制改初始密码，就按它走完，再回来              │
│  · 登录成功后脚本自动继续，不用管                            │
└──────────────────────────────────────────────────────────────┘
`);

  // 精确等待：必须真的落到教务系统，且不在 login / caslogin 中转页
  await page.waitForURL(
    (u) =>
      u.hostname === 'tls.ccsut.cn' &&
      !u.pathname.startsWith('/admin/login') &&
      !u.pathname.startsWith('/admin/caslogin') &&
      !u.pathname.startsWith('/admin/loginFailPage'),
    { timeout: 10 * 60 * 1000 }
  );
  console.log(`✓ 登录成功，当前页面：${page.url()}\n`);
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(2500);

  // 页面侦察：这套系统是「Vue 前端 + /admin/** JSON 接口」，真实路径如下
  const seeds = [
    ['入口', '/admin/'], // 会 302 到 /frontend/views/student/xkPage/index.html
    ['课表', '/admin/xsd/pkgl/xskb/queryKbForXsd'],
    ['成绩', '/admin/xsd/xsdzgcjcx/xscjdy'],
    ['选课页', '/frontend/views/student/xkPage/index.html'],
  ];
  console.log('==== 页面侦察（判断能不能做原生）====');
  for (const [label, p] of seeds) {
    try {
      const res = await page.goto(JW + p, { waitUntil: 'domcontentloaded', timeout: 25000 });
      await page.waitForTimeout(1200);
      const ct = res?.headers()['content-type'] ?? '?';
      const st = res?.status() ?? 0;
      const size = (await res?.body().catch(() => null))?.length ?? 0;
      pageTypes.push({ label, path: p, status: st, contentType: ct, bytes: size, finalUrl: page.url() });
      console.log(`  ${label.padEnd(4)} ${String(st).padEnd(4)} ${ct.split(';')[0].padEnd(24)} ${(size / 1024).toFixed(1)} KB`);
    } catch (e) {
      pageTypes.push({ label, path: p, status: 0, contentType: 'error', bytes: 0, error: e.message });
      console.log(`  ${label.padEnd(4)} 失败：${e.message.slice(0, 60)}`);
    }
  }

  // ── 导出 ──
  const state = await context.storageState();
  await fs.writeFile(path.join(OUT_DIR, 'state.json'), JSON.stringify(state, null, 2));

  // Netscape cookie jar
  const jar = state.cookies
    .map((c) => {
      const expires = c.expires && c.expires > 0 ? Math.floor(c.expires) : 0;
      const domain = c.domain.startsWith('.') ? c.domain : `.${c.domain}`;
      return [domain, c.httpOnly ? 'TRUE' : 'FALSE', c.path, c.secure ? 'TRUE' : 'FALSE', expires, c.name, c.value].join('\t');
    })
    .join('\n');
  await fs.writeFile(path.join(OUT_DIR, 'cookies.txt'), `# Netscape HTTP Cookie File\n${jar}\n`);

  // 接口清单
  const seen = new Set();
  const api = records.filter((r) => {
    const k = `${r.method} ${r.url}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  await fs.writeFile(path.join(OUT_DIR, 'api.json'), JSON.stringify(api, null, 2));

  const groups = new Map();
  for (const r of api) {
    const u = new URL(r.url);
    const seg = u.pathname.split('/').filter(Boolean).slice(0, 2).join('/') || '/';
    const key = `${u.host} /${seg}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  }
  const summary = [
    '# 接口速查',
    '',
    `生成时间：${new Date().toISOString()}`,
    `唯一请求：${api.length}`,
    '',
    ...[...groups.entries()]
      .sort((a, b) => b[1].length - a[1].length)
      .map(([k, list]) =>
        [`## ${k} (${list.length})`, '', ...list.map((r) => `- \`${r.method}\` \`${new URL(r.url).pathname}\` → ${r.status} ${r.mime?.split(';')[0] ?? ''}`), ''].join('\n')
      ),
  ].join('\n');
  await fs.writeFile(path.join(OUT_DIR, 'summary.md'), summary);

  // 页面类型报告
  const pt = [
    '# 页面类型侦察',
    '',
    '| 模块 | 路径 | 状态 | Content-Type | 大小 |',
    '|---|---|---|---|---|',
    ...pageTypes.map((p) => `| ${p.label} | \`${p.path}\` | ${p.status} | ${p.contentType.split(';')[0]} | ${(p.bytes / 1024).toFixed(1)} KB |`),
    '',
    '**判读**：全是 `text/html` → 服务端渲染，原生要解析 HTML；出现 `application/json` → 有 AJAX 层，可做部分原生。',
  ].join('\n');
  await fs.writeFile(path.join(OUT_DIR, 'page-types.md'), pt);

  // 会话体检报告
  const { rows, verdict } = diagnoseSession(state);
  const report = [
    '# 会话体检报告',
    '',
    `时间：${new Date().toISOString()}`,
    '',
    `## 结论：${verdict.level} 级 — ${verdict.title}`,
    '',
    verdict.detail,
    '',
    '## Cookie 明细',
    '',
    '| Cookie | 域名 | HttpOnly | Secure | SameSite | 到期时间 | 剩余天数 |',
    '|---|---|---|---|---|---|---|',
    ...rows.map(
      (r) => `| \`${r.name}\` | ${r.domain} | ${r.httpOnly ? '✓' : ''} | ${r.secure ? '✓' : ''} | ${r.sameSite} | ${r.expiresAt} | ${r.days ?? '—'} |`
    ),
    '',
    '## 下一步',
    '',
    '- 如果结论是 A/B：直接把 `state.json` 灌进 App，冷启动即可免登录。',
    '- 如果结论是 C：需要「Cookie 快照 + 冷启动注回 + 失效时静默重登」三件套。',
    '- 想测服务端空闲超时：`node tools/keepalive.mjs --state ./out/state.json --watch`，放着别动，看多久开始报失效。',
  ].join('\n');
  await fs.writeFile(path.join(OUT_DIR, 'session-report.md'), report);

  // ── 控制台汇总 ──
  console.log('\n════════════ 会话体检 ════════════');
  for (const r of rows) {
    const d = r.days === null ? '会话级' : `${r.days} 天`;
    console.log(`  ${r.name.padEnd(18)} ${d.padEnd(12)} ${r.domain}`);
  }
  console.log(`\n  ▸ 结论 ${verdict.level} 级：${verdict.title}`);
  if (verdict.detail) console.log(`    ${verdict.detail}`);

  console.log('\n════════════ 产物 ════════════');
  console.log(`  session-report.md  ← 先看这个`);
  console.log(`  page-types.md      ← 再看着个（能不能做原生）`);
  console.log(`  state.json         会话（等同密码）`);
  console.log(`  api.json           接口清单（${api.length} 条）`);
  console.log(`\n  下一步：node tools/keepalive.mjs --state ./out/state.json --watch`);
  console.log('  放着别动，看多久掉线 → 那就是服务端空闲超时\n');

  if (!CDP_PORT) await browser.close();
}

main().catch((e) => {
  console.error('\n✗ 失败：', e.message);
  if (/Executable doesn't exist|channel/.test(e.message)) {
    console.error('  提示：脚本默认用系统 Chrome。没装 Chrome 就加 --browser chromium，并先跑 npx playwright install chromium');
  }
  process.exit(1);
});
