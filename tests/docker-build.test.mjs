// node:test entry point for the Docker build feature.
// Runs the shell suite (tests/docker-build.test.sh) once and reports one
// test per acceptance criterion based on its PASS/FAIL/SKIP lines.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const suite = fileURLToPath(new URL('./docker-build.test.sh', import.meta.url));
const run = spawnSync('sh', [suite], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const lines = (run.stdout ?? '').split('\n');

const CRITERIA = [
  '1.1', '1.2', '1.3', '1.4', '1.5',
  '2.1', '2.2', '2.3',
  '3.1', '3.2', '3.3', '3.4',
  '4.1', '4.2', '4.3', '4.4', '4.5', '4.6', '4.7',
  '5.1', '5.2',
];

const resultsFor = (id) => {
  const prefix = ` ${id} `;
  const pick = (kind) => lines.filter((l) => l.startsWith(`${kind}:${prefix}`));
  return { pass: pick('PASS'), fail: pick('FAIL'), skip: pick('SKIP') };
};

test('shell suite exits 0', () => {
  assert.equal(run.status, 0, `${run.stdout}\n${run.stderr}`);
});

for (const id of CRITERIA) {
  test(`criterion ${id}`, () => {
    const { pass, fail, skip } = resultsFor(id);
    assert.deepEqual(fail, [], `failing checks for ${id}`);
    assert.deepEqual(skip, [], `skipped checks for ${id}`);
    assert.ok(pass.length > 0, `no passing check for ${id}`);
  });
}
