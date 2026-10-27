import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { sessionRequest } from './session-request.mjs';

test('requests scope cookies and retain server deletions for the next read', async () => {
  const server = http.createServer((req, res) => {
    res.setHeader('Set-Cookie', 'current=; Max-Age=0; Path=/');
    res.end(req.headers.cookie ?? '');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const cookie = (name, domain, extra = {}) => ({ name, value: 'fixture', domain, path: '/',
      expires: -1, secure: false, httpOnly: true, sameSite: 'Lax', ...extra });
    const state = { cookies: [cookie('school', 'auth.ccsut.cn'), cookie('current', '127.0.0.1'),
      cookie('private', '127.0.0.1', {path:'/private'}),
      cookie('expired', '127.0.0.1', {expires:1})], origins: [] };
    const url = `http://127.0.0.1:${server.address().port}/public`;
    const first = await sessionRequest(url, state);
    assert.equal(await first.text(), 'current=fixture');
    const second = await sessionRequest(url, state);
    assert.equal(await second.text(), '');
    assert.ok(state.cookies.some(c => c.name === 'school'), 'unrelated credentials are retained, not sent');
  } finally { await new Promise(resolve => server.close(resolve)); }
});
