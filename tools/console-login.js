/**
 * console-login.js — 在统一认证登录页一键登录（零依赖，浏览器控制台直接跑）
 *
 * 用法：
 *   1. 打开 https://tls.ccsut.cn/admin/caslogin
 *      （会自动跳到 auth.ccsut.cn 的登录页）
 *   2. F12 → Console → 粘贴本文件全部内容 → 回车
 *   3. 按提示输入学号密码，脚本自动切「密码登录」、填表、勾「记住账号/记住密码」、提交
 *
 * 说明：
 *   · 密码只在当前页面内存里，不会外发，也不会写 localStorage
 *   · 勾「记住账号/记住密码」是为了让 CAS 下发长效 Cookie，下次可免登录
 *   · 如果页面停在扫码页，脚本会自动切到密码登录
 */
(async function ccsutLogin() {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const log = (...a) => console.log('%c[ccsut]', 'color:#1b4fd1;font-weight:bold', ...a);

  // ---------- 1. 收集凭据 ----------
  const saved = JSON.parse(sessionStorage.getItem('__ccsut_cred') || '{}');
  const username = saved.u || prompt('学号：', '');
  if (!username) return log('已取消');
  const password = saved.p || prompt('密码（首次为身份证后六位，末位 X 改 0）：', '');
  if (!password) return log('已取消');
  sessionStorage.setItem('__ccsut_cred', JSON.stringify({ u: username, p: password }));

  // ---------- 2. 切到「密码登录」tab ----------
  const tabs = [...document.querySelectorAll('.ant-tabs-tab')];
  const pwdTab = tabs.find((t) => (t.textContent || '').includes('密码登录'));
  if (pwdTab && !pwdTab.classList.contains('ant-tabs-tab-active')) {
    pwdTab.click();
    await sleep(600);
  }

  // ---------- 3. 等表单渲染 ----------
  let inputs = [];
  for (let i = 0; i < 30; i++) {
    inputs = [...document.querySelectorAll('input')];
    if (inputs.some((el) => el.type === 'password')) break;
    await sleep(200);
  }
  const pwdInput = inputs.find((el) => el.type === 'password');
  const textInputs = inputs.filter((el) => el.type === 'text');
  if (!pwdInput || !textInputs.length) return log('✗ 没找到登录表单，确认页面在密码登录 tab');

  // ---------- 4. 写值（必须触发原生 input 事件，Angular 才认） ----------
  const setVal = (el, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, v);
    ['input', 'change', 'keyup', 'blur'].forEach((t) =>
      el.dispatchEvent(new Event(t, { bubbles: true }))
    );
  };

  const userInput = textInputs.find((el) => /用户名|手机号|账号/.test(el.placeholder || '')) || textInputs[0];
  setVal(userInput, username);
  setVal(pwdInput, password);

  // 图形/短信验证码框（有的学校开了，留空让页面自己校验）
  const codeInput = textInputs.find((el) => /验证码/.test(el.placeholder || ''));
  if (codeInput && codeInput !== userInput) {
    const code = prompt('页面要求验证码，请输入（没有就留空直接确定）：', '') || '';
    setVal(codeInput, code);
  }

  await sleep(300);

  // ---------- 5. 勾选「记住账号」「记住密码」 ----------
  const boxes = [...document.querySelectorAll('label.ant-checkbox-wrapper, .ant-checkbox-wrapper')];
  for (const label of boxes) {
    if (!/记住/.test(label.textContent || '')) continue;
    const cb = label.querySelector('input[type=checkbox]');
    if (cb && !cb.checked) {
      label.click();
      await sleep(150);
    }
  }
  log('已勾选记住项：', boxes.filter((b) => /记住/.test(b.textContent || '')).length, '个');

  // ---------- 6. 提交 ----------
  await sleep(300);
  const btn = [...document.querySelectorAll('button')].find(
    (b) => (b.textContent || '').trim() === '登录'
  );
  if (!btn) return log('✗ 没找到登录按钮');
  btn.click();
  log('已提交，等待跳转…');

  // ---------- 7. 等结果 ----------
  const t0 = Date.now();
  const timer = setInterval(() => {
    if (Date.now() - t0 > 20000) {
      clearInterval(timer);
      log('20s 未跳转，看页面提示（密码错误 / 验证码 / 账号锁定）');
      sessionStorage.removeItem('__ccsut_cred'); // 别把密码留在会话里
      return;
    }
    const msg = [...document.querySelectorAll('.ant-message-notice, .ant-form-explain')]
      .map((e) => (e.textContent || '').trim())
      .filter(Boolean)
      .join(' | ');
    if (msg) log('页面提示：', msg);
    if (!location.href.includes('/cas/login')) {
      clearInterval(timer);
      sessionStorage.removeItem('__ccsut_cred');
      log('✓ 登录成功 →', location.href);
      log('接下来可以跑 tools/capture.mjs 把接口抓下来');
    }
  }, 800);
})();
