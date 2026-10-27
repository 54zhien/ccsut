import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

for (const file of ['_e2e.mjs', '_e2e2.mjs', '_probe2.mjs']) {
  test(`${file} refuses writes before reading credentials`, () => {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL(`../${file}`, import.meta.url))],
      { cwd: tmpdir(), encoding: 'utf8', timeout: 3000 });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /--allow-school-writes/);
    assert.doesNotMatch(result.stderr, /state\.json/);
  });
}
