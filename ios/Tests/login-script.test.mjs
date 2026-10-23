import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

// Execute the actual JavaScript embedded in LoginView; no copied implementation.
const source = readFileSync(new URL('../CCSUT/LoginView.swift', import.meta.url), 'utf8');
const script = source.match(/private static let script = """([\s\S]*?)"""/)[1]
  .replace(/\\\\/g, '\\').replace(/\\"/g, '"');

async function action(mode, reply) {
  let alerts = [];
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
  const context = vm.createContext({
    account: 'fixture-student', code: '123456', action: mode,
    HTMLInputElement: Input, Event: class {},
    setTimeout(fn) { fn(); },
    document: { querySelectorAll(selector) {
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
