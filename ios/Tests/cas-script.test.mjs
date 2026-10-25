import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const source = (await fs.readFile(new URL('../../_cas3.mjs', import.meta.url), 'utf8'))
  .replace(/^\uFEFF/, '')
  .replace(/^import .*;\r?\n/gm, '');

for (const account of ['fixture-account', undefined]) {
  test(`CAS fills the browser input with ${account ? 'the supplied account' : 'an empty default'}`, async () => {
    class Input {}
    Object.defineProperty(Input.prototype, 'value', { set(value) { this.filled = value; } });
    const user = Object.assign(new Input(), { type: 'text', placeholder: '用户名', offsetWidth: 100, dispatchEvent() {} });
    const password = { type: 'password', placeholder: '密码', offsetWidth: 100 };
    const tab = { textContent: '密码登录', classList: { contains: () => true } };
    const browserContext = vm.createContext({ HTMLInputElement: Input, Event: class {}, setTimeout,
      document: { querySelectorAll(selector) {
        return selector === '.ant-tabs-tab' ? [tab] : selector === 'input' ? [user, password] : [{ textContent: '登录' }];
      } }
    });
    let closed = false;
    const page = { goto: async () => {}, evaluate: async (callback, argument) => {
      browserContext.argument = argument;
      return vm.runInContext(`(${callback.toString()})(argument)`, browserContext);
    } };
    const nodeContext = vm.createContext({ process: { env: account ? { CCSUT_SNO: account } : {} },
      console: { log() {} }, chromium: { launch: async () => ({
        newContext: async () => ({ newPage: async () => page }),
        close: async () => { closed = true; }
      }) }
    });
    await vm.runInContext(`(async () => {\n${source}\n})()`, nodeContext);
    assert.equal(user.filled, account ?? '');
    assert.equal(closed, true);
  });
}
