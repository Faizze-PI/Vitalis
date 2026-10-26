const assert = require('assert/strict');
const fs = require('fs');
const {options, validateLock, obtainArchive} = require('./build_split_test_fixture');
const args = ['--model', 'model with spaces.gguf', '--output-parent', 'new parent',
  '--max-shard-size', '300M', '--parallel', '2'];
assert.equal(options(args)['--model'], 'model with spaces.gguf');
assert(Object.isFrozen(options(args)));
for (const invalid of [[], [...args.slice(0, -2)],
  args.map((value, index) => index === 0 ? '--unknown' : value),
  args.map((value, index) => index === 0 ? '--parallel' : value),
  args.map((value, index) => index === 1 ? 'unsafe\nvalue' : value),
  args.map((value, index) => index === 5 ? '0M' : value),
  args.map((value, index) => index === 7 ? '-1' : value)]) {
  assert.throws(() => options(invalid));
}
const lock = JSON.parse(fs.readFileSync('third_party/llm_llamacpp/native/llama_cpp.lock.json', 'utf8'));
validateLock(lock);
for (const invalid of [{...lock, commit: 'mutable-tag'}, {...lock, archiveSha256: 'first-download'},
  {...lock, archiveUrl: 'https://example.test/native.tar.gz'}]) {
  assert.throws(() => validateLock(invalid));
}
process.stdout.write('Split helper option and immutable-lock contracts passed.\n');
async function cachedArchiveTests() {
  const path = require('path');
  const root = fs.mkdtempSync(path.join(require('os').tmpdir(), 'split-archive-test-'));
  try {
    const cached = path.join(root, 'cached source.tar.gz');
    const output = path.join(root, 'source.tar.gz');
    fs.writeFileSync(cached, 'abc');
    const identity = {...lock, archiveSha256:
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'};
    const noNetwork = () => { throw new Error('Verified cache must not download'); };
    await obtainArchive(output, identity, noNetwork, cached);
    assert.equal(fs.readFileSync(output, 'utf8'), 'abc');
    assert.equal(fs.readFileSync(cached, 'utf8'), 'abc');
    await assert.rejects(obtainArchive(path.join(root, 'bad.tar.gz'), lock,
      noNetwork, cached), /Native archive mismatch/);
    await assert.rejects(obtainArchive(output, identity, noNetwork, cached), /EEXIST/);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
  process.stdout.write('Verified archive reuse and mismatch rejection passed.\n');
}
cachedArchiveTests().catch((error) => { console.error(error); process.exitCode = 1; });
