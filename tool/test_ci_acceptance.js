'use strict';

const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const {requireSuccessfulJobs} = require('./verify_ci_acceptance');

requireSuccessfulJobs({root: {result: 'success'}, native: {result: 'success'}});
const invalid = [null, [], {}, 'success', {root: null}, {root: 'success'},
  ...['failure', 'cancelled', 'skipped', 'unknown', undefined].map(result =>
    ({root: {result: 'success'}, native: {result}}))];
for (const result of invalid) assert.throws(() => requireSuccessfulJobs(result));
const script = path.join(__dirname, 'verify_ci_acceptance.js');
function run(value) {
  return spawnSync(process.execPath, [script], {
    env: {...process.env, REQUIRED_RESULTS: value}, encoding: 'utf8',
  });
}
assert.equal(run(JSON.stringify({root: {result: 'success'}})).status, 0);
assert.equal(run('{malformed').status, 1);
assert.equal(run(JSON.stringify({root: {result: 'skipped'}})).status, 1);
process.stdout.write('CI acceptance self-test: success, invalid statuses and CLI exits pass\n');
