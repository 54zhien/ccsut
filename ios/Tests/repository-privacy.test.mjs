import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const tracked = cwd => execFileSync('git', ['ls-files', '-z'], { cwd, encoding: 'utf8' })
  .split('\0').filter(Boolean);
const isDist = path => path.startsWith('dist/');

test('local distribution and diagnostic files are absent from the repository index', () => {
  // Also catches a future forced add, which .gitignore alone cannot prevent.
  assert.equal(tracked(root).filter(isDist).length, 0,
    'Remove dist files from the index; never print their potentially private contents');
});

test('ordinary git add excludes existing and newly named dist outputs', () => {
  const fixture = mkdtempSync(join(tmpdir(), 'ccsut-privacy-'));
  try {
    execFileSync('git', ['init', '--quiet'], { cwd: fixture });
    copyFileSync(join(root, '.gitignore'), join(fixture, '.gitignore'));
    for (const path of ['dist/install.md', 'dist/new-build/student-diagnostic.txt',
      'dist/new-build/session.json', 'dist/new-build/screen.png', 'src/ordinary.txt']) {
      const target = join(fixture, path);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, 'Synthetic fixture only. No personal data.\n');
    }
    execFileSync('git', ['add', '.'], { cwd: fixture, stdio: 'pipe' });
    const files = tracked(fixture);
    assert.equal(files.filter(isDist).length, 0, 'New dist directories must also be ignored');
    assert.ok(files.includes('src/ordinary.txt'), 'Ordinary source files must still be tracked');
  } finally {
    // mkdtemp creates this exact child of the OS temporary directory.
    if (dirname(fixture) !== tmpdir()) throw new Error('Unexpected fixture cleanup location');
    rmSync(fixture, { recursive: true, force: true });
  }
});
