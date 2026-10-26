import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

// Execute the actual JavaScript embedded in LoginView; no copied implementation.
const source = readFileSync(new URL('../CCSUT/LoginView.swift', import.meta.url), 'utf8');
const script = source.match(/private static let script = """([\s\S]*?)"""/)[1]
  .replace(/\\\\/g, '\\').replace(/\\"/g, '"');

async function action(mode, reply, initialReply = null, page = {}) {
  let alerts = initialReply ? [{ textContent: initialReply, offsetWidth: 100, offsetHeight: 20 }] : [];
  class Input {
    constructor(placeholder) { this.placeholder = placeholder; this.type = 'text'; this.offsetWidth = 100; }
    set value(v) { this.text = v; }
    get value() { return this.text; }
    dispatchEvent() {}
  }
  const inputs = [new Input('工号/学号/手机号'), new Input('验证码')];
  const send = { textContent: '获取验证码', offsetWidth: 100, disabled: false, click() { respond(); } };
  const login = { textContent: '登录', offsetWidth: 100, disabled: false, click() { respond(); } };
  function respond() {
    if (reply === 'sent') { send.textContent = '60秒后重新获取'; send.disabled = true; }
    else if (reply) alerts = [{ textContent: reply, offsetWidth: 100, offsetHeight: 20 }];
  }
  let waits = 0;
  const location = { protocol: 'https:', hostname: 'auth.ccsut.cn', pathname: '/backstage/cas/login', ...page };
  const context = vm.createContext({
    account: 'fixture-student', code: '123456', action: mode,
    location,
    HTMLInputElement: Input, Event: class {},
    setTimeout(fn) {
      waits += 1;
      if (waits === page.navigateAtWait) { location.hostname = 'tls.ccsut.cn'; location.pathname = '/admin/index'; }
      fn();
    },
    document: { querySelectorAll(selector) {
      if (selector === '.ant-tabs-tab' && page.hostname === 'tls.ccsut.cn') return [];
      if (selector === '.ant-tabs-tab') return [{ textContent: '验证码登录', classList: { contains: () => true } }];
      if (selector === 'input') return inputs;
      if (selector === 'button') return [send, login];
      if (selector === 'label.ant-checkbox-wrapper') return [];
      return alerts;
    } },
  });
  return vm.runInContext(`(async () => { ${script} })()`, context);
}

test('SMS server rejection is shown instead of reporting sent', async () => {
  assert.match(await action('send', '发送过于频繁'), /发送过于频繁/);
});
test('SMS countdown confirms successful send', async () => {
  assert.equal(await action('send', 'sent'), 'sent');
});
test('SMS without confirmation times out instead of reporting sent', async () => {
  assert.equal(await action('send', null), 'timeout');
});
test('invalid login code is returned to the native hint', async () => {
  assert.match(await action('submit', '验证码错误'), /验证码错误/);
});
test('login without navigation or response terminates', async () => {
  assert.equal(await action('submit', null), 'timeout');
});
test('repeated identical login error in a new alert is still reported', async () => {
  assert.match(await action('submit', '验证码错误', '验证码错误'), /验证码错误/);
});

// Once CAS has returned to the portal there is no SMS form to wait for.
for (const mode of ['prepare', 'send', 'submit']) {
  test(`${mode} on an existing portal session requests native verification`, async () => {
    assert.equal(await action(mode, null, null, {
      hostname: 'tls.ccsut.cn', pathname: '/frontend/views/student/xkPage/index.html',
    }), 'authenticated');
  });
}
for (const pathname of ['/admin/login', '/admin/loginFailPage', '/admin/caslogin']) {
  test(`does not call the authentication entry ${pathname} a completed session`, async () => {
    assert.notEqual(await action('send', null, null, { hostname: 'tls.ccsut.cn', pathname }), 'authenticated');
  });
}

test('portal navigation during SMS confirmation requests native verification', async () => {
  assert.equal(await action('send', null, null, { navigateAtWait: 2 }), 'authenticated');
});
test('portal navigation during login confirmation requests native verification', async () => {
  assert.equal(await action('submit', null, null, { navigateAtWait: 3 }), 'authenticated');
});
