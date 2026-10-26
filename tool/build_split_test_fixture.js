// Build-only fixture helper. Never modifies a native asset cache or original GGUF.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

function options(args) {
  const names = new Set(['--model', '--output-parent', '--max-shard-size', '--parallel']);
  if (args.length !== names.size * 2) throw new Error('Missing split builder options');
  const parsed = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!names.has(args[i]) || Object.hasOwn(parsed, args[i]) || !args[i + 1] ||
        /[\x00-\x1f]/.test(args[i + 1])) throw new Error('Invalid split builder option');
    parsed[args[i]] = args[i + 1];
  }
  if (!/^[1-9]\d*[MG]$/.test(parsed['--max-shard-size']) ||
      !/^[1-9]\d*$/.test(parsed['--parallel'])) throw new Error('Invalid split builder limits');
  return Object.freeze(parsed);
}

function validateLock(lock) {
  if (!/^[a-f0-9]{40}$/.test(lock.commit) || !/^[a-f0-9]{64}$/.test(lock.archiveSha256) ||
      lock.archiveUrl !== `https://github.com/ggml-org/llama.cpp/archive/${lock.commit}.tar.gz`) {
    throw new Error('Invalid locked native source identity');
  }
}

async function digest(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

async function obtainArchive(archive, lock, run, cachedArchive) {
  if (cachedArchive) {
    fs.copyFileSync(cachedArchive, archive, fs.constants.COPYFILE_EXCL);
  } else {
    run('curl', ['--fail', '--location', '--retry', '4', '--output', archive, lock.archiveUrl]);
  }
  if (await digest(archive) !== lock.archiveSha256) throw new Error('Native archive mismatch');
}

async function main(args) {
  const config = options(args);
  const repository = path.resolve(__dirname, '..');
  const lockPath = path.join(repository, 'third_party/llm_llamacpp/native/llama_cpp.lock.json');
  const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
  validateLock(lock);
  const model = JSON.parse(cp.execFileSync('dart', ['tool/export_bundled_model_manifest.dart'], {
    cwd: repository, encoding: 'utf8',
  }));
  if (await digest(config['--model']) !== model.sha256) throw new Error('Immutable model mismatch');
  const root = fs.mkdtempSync(path.join(path.resolve(config['--output-parent']), 'vitalis-split-helper-'));
  const run = (command, values) => cp.execFileSync(command, values, {cwd: repository, stdio: 'inherit'});
  const archive = path.join(root, 'source.tar.gz');
  await obtainArchive(archive, lock, run, process.env.VITALIS_NATIVE_SOURCE_ARCHIVE);
  const sourceRoot = path.join(root, 'source');
  fs.mkdirSync(sourceRoot);
  run('tar', ['-xzf', archive, '-C', sourceRoot]);
  const build = path.join(root, 'build');
  run('cmake', ['-S', path.join(sourceRoot, `llama.cpp-${lock.commit}`), '-B', build,
    '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_SHARED_LIBS=OFF', '-DGGML_NATIVE=OFF',
    '-DGGML_OPENMP=OFF', '-DGGML_BACKEND_DL=OFF', '-DGGML_VULKAN=OFF',
    '-DLLAMA_STANDALONE=OFF', '-DLLAMA_BUILD_COMMON=ON', '-DLLAMA_BUILD_TOOLS=ON',
    '-DLLAMA_BUILD_APP=OFF', '-DLLAMA_BUILD_SERVER=OFF', '-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_EXAMPLES=OFF', '-DLLAMA_OPENSSL=OFF', '-DLLAMA_BUILD_MTMD=OFF']);
  run('cmake', ['--build', build, '--config', 'Release', '--target', 'llama-gguf-split',
    '--parallel', config['--parallel']]);
  const executable = `llama-gguf-split${process.platform === 'win32' ? '.exe' : ''}`;
  const tools = [path.join(build, 'bin', 'Release', executable),
    path.join(build, 'bin', executable)].filter((candidate) => fs.existsSync(candidate));
  if (tools.length !== 1) throw new Error('Split helper executable is absent or ambiguous');
  const tool = tools[0];
  const provenance = path.join(root, 'provenance.json');
  fs.writeFileSync(provenance, JSON.stringify({
    commit: lock.commit, archiveSha256: lock.archiveSha256,
    sourceLockSha256: await digest(lockPath), toolSha256: await digest(tool), buildExitCode: 0,
    diagnosticScope: 'Pinned upstream fixture-helper build; not a zero-warning production verdict',
  }, null, 2));
  const output = path.join(root, 'fixture');
  run('dart', ['tool/prepare_split_fixture.dart', '--model', config['--model'], '--splitter', tool,
    '--provenance', provenance, '--output', output, '--max-shard-size', config['--max-shard-size']]);
  const manifest = path.join(output, 'manifest.json');
  const evidence = path.join(repository, '.ci-evidence/native');
  fs.mkdirSync(evidence, {recursive: true});
  // Archive only provenance, never model payloads or generated native binaries.
  fs.copyFileSync(manifest, path.join(evidence, 'split-fixture-manifest.json'));
  fs.copyFileSync(provenance, path.join(evidence, 'split-helper-provenance.json'));
  if (process.env.GITHUB_ENV) {
    if (/[\r\n]/.test(manifest)) throw new Error('Invalid fixture environment path');
    fs.appendFileSync(process.env.GITHUB_ENV, `VITALIS_SPLIT_TEST_FIXTURE=${manifest}\n`);
  }
  process.stdout.write(`Split fixture ready: ${manifest}\n`);
}

module.exports = {options, validateLock, obtainArchive};
if (require.main === module) main(process.argv.slice(2)).catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
