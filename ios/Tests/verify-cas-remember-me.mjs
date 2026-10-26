import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Execute the production WKUserScript without WebKit. No account, code or network.
const source = fs.readFileSync(new URL('../CCSUT/WebPanel.swift', import.meta.url), 'utf8');
const script = source.match(/enum CASLoginPersistence[\s\S]*?static let script = """\n([\s\S]*?)\n\s*"""/)?.[1] ?? '';
function run({ host = 'auth.ccsut.cn', path = '/backstage/cas/login',
               action = 'https://auth.ccsut.cn/backstage/cas/login', method = 'post',
               value = 'false', field = true, event = false, installs = 1 } = {}) {
    const remember = { value };
    const credential = { value: 'unchanged-fixture' };
    const listeners = [];
    let submissions = 0;
    class Form {
        constructor() { this.action = action; this.method = method; }
        querySelector(selector) {
            if (selector === 'input[name="username"]' || selector === 'input[name="password"]') return credential;
            return field && selector === 'input[name="rememberMe"]' ? remember : null;
        }
        submit() { assert.equal(this, form); submissions++; }
    }
    const form = new Form();
    const context = vm.createContext({ URL, location: { origin: `https://${host}`, hostname: host, pathname: path },
        document: { baseURI: `https://${host}${path}`, addEventListener: (type, fn) => {
            if (type === 'submit') listeners.push(fn);
        } }, HTMLFormElement: Form });
    for (let i = 0; i < installs; i++) vm.runInContext(script, context);
    if (event) listeners.forEach(fn => fn({ target: form }));
    else form.submit();
    return { value: remember.value, submissions, credential: credential.value };
}
assert.equal(run().value, 'true', 'actual CAS form must submit rememberMe=true');
assert.equal(run({ event: true }).value, 'true', 'normal form submission also enables persistence');
assert.equal(run({ value: 'true' }).value, 'true');
assert.equal(run({ installs: 2 }).submissions, 1, 'installation never duplicates a login POST');
assert.equal(run().credential, 'unchanged-fixture');
for (const options of [
    { host: 'other.ccsut.cn' }, { path: '/other' },
    { action: 'https://other.ccsut.cn/backstage/cas/login' },
    { action: 'https://auth.ccsut.cn/other' },
    { action: 'http://auth.ccsut.cn/backstage/cas/login' },
    { action: 'https://user@auth.ccsut.cn/backstage/cas/login' },
    { method: 'get' }, { field: false },
]) assert.equal(run(options).value, 'false', `unrelated form stays untouched: ${JSON.stringify(options)}`);
assert.match(source, /addUserScript\(WKUserScript\([\s\S]*?source: CASLoginPersistence.script,[\s\S]*?injectionTime: \.atDocumentStart,[\s\S]*?forMainFrameOnly: true/, 'login WebViews install the production script');
console.log('PASS: CAS persistence submit/event handling, scope, credential preservation and WebView installation');
