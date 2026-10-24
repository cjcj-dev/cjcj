#!/usr/bin/env zx
// Run the Git helper in the selected real Bash; tuple fetching uses its zx entry.
import {fs, path, assert, repo, entry, run, capture} from '../../ci/entry-common.mjs';
import os from 'node:os';
await entry(async () => {
  const shell = process.env.BASH_UNDER_TEST || process.env.BASH || 'bash';
  const helper = process.env.SRCBUILD_GIT_SH || path.join(repo, 'build/lib/srcbuild_git.sh');
  const fetch = process.env.FETCH_SOURCES_MJS || path.join(repo, 'ci/platform_tuples/fetch_sources.mjs');
  const work = fs.mkdtempSync(path.join(process.env.SRCBUILD_GIT_EVIDENCE || os.tmpdir(), 'git-shell-'));
  console.log(`CONTRACT_EVIDENCE=${work}\nHELPER=${helper}`);
  await run([shell, '-c', 'printf "BASH_VERSION=%s\\nBASH_PATH=%s\\n" "$BASH_VERSION" "$BASH"']);
  const base = {...process.env};
  for (const key of Object.keys(base)) if (/^(CJCJ_SRCBUILD_|CJCJ_LLVM_RUNTIME_)/.test(key)) delete base[key];
  delete base.RUNTIME_REF; delete base.RUNTIME_SRC_URL;
  const git = async (...argv) => (await capture(['git', ...argv])).stdout.trim();
  const inputs = {};
  for (const [name, file, body] of [
    ['llvm', 'llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h', 'enum EnumReflectionType {\n  ERT_NONE,\n};\n'],
    ['compiler', 'schema/ModuleFormat.fbs', 'table Fixture {}\n'],
    ['flatbuffers', 'CMakeLists.txt', 'cmake_minimum_required(VERSION 3.16)\n'],
    ['runtime', 'runtime/tools/generate-runtime-layout.py', '# source fetch fixture\n'],
  ]) {
    const src = path.join(work, `src-${name}`), bare = path.join(work, `bare-${name}`);
    fs.mkdirSync(path.dirname(path.join(src, file)), {recursive: true}); fs.writeFileSync(path.join(src, file), body);
    await git('init', src); await git('-C', src, 'add', '.');
    await git('-C', src, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture');
    const sha = await git('-C', src, 'rev-parse', 'HEAD'); await git('clone', '--bare', src, bare);
    inputs[name] = {sha, bare};
  }
  let fails = 0;
  const check = (name, predicate, detail) => {
    console.log(`ASSERT_REACHED name=${name}`);
    if (predicate) console.log(`ASSERT_PASS name=${name}`);
    else { fails++; console.error(`ASSERT_FAIL name=${name} detail=${JSON.stringify(detail)}`); }
  };
  async function fetchHelper(label, url, sha, mirrors, required) {
    const dest = path.join(work, label), trace = path.join(work, `${label}.trace`);
    await git('init', dest); await git('-C', dest, 'remote', 'add', 'origin', url);
    const env = {...base, GIT_TRACE: trace};
    if (mirrors !== undefined) env.CJCJ_SRCBUILD_SOURCE_MIRRORS = mirrors;
    if (required !== undefined) env.CJCJ_SRCBUILD_REQUIRE_MIRRORS = required;
    const result = await run([shell, '-c', 'set -euo pipefail; source "$1"; srcbuild_git_fetch "$2" "$3" "$4"',
      'helper-contract', helper, dest, url, sha], {env, log: path.join(work, `${label}.log`), check: false});
    fs.writeFileSync(path.join(work, `${label}.rc`), `${result.exitCode}\n`);
    return {result, dest, trace: fs.existsSync(trace) ? fs.readFileSync(trace, 'utf8') : ''};
  }
  const noShellError = text => !text.includes('local: -A') && !text.includes('entries[@]');
  const direct = await fetchHelper('checkout-empty', `file://${inputs.llvm.bare}`, inputs.llvm.sha);
  check('fetch_head', direct.result.exitCode === 0 && await git('-C', direct.dest, 'rev-parse', 'FETCH_HEAD') === inputs.llvm.sha &&
    direct.result.stdall.includes(`SOURCE-MIRROR none, falling back to file://${inputs.llvm.bare}`) && direct.trace.includes('fetch') && noShellError(direct.result.stdall), direct.result);
  if (process.env.SKIP_FETCH_SOURCES !== '1') {
    const fixture = path.join(work, 'fetch-repo');
    for (const [from, to] of [
      [fetch, 'ci/platform_tuples/fetch_sources.mjs'], [helper, 'build/lib/srcbuild_git.sh'],
      ...['ci/platform_tuples/entry.mjs', 'ci/entry-common.mjs', 'ci/fetch-llvm-runtime.mjs'].map(file => [path.join(repo, file), file]),
    ]) { const dest = path.join(fixture, to); fs.mkdirSync(path.dirname(dest), {recursive: true}); fs.copyFileSync(from, dest); }
    fs.writeFileSync(path.join(fixture, 'ci/runtime_pin.env'), `RUNTIME_REF=${inputs.runtime.sha}\nRUNTIME_SRC_URL=file://${inputs.runtime.bare}\n`);
    const tuple = path.join(work, 'tuple');
    const env = {...base, TUPLE_ROOT: tuple, GIT_TRACE: path.join(work, 'sources.trace')};
    for (const [prefix, name] of [['LLVM', 'llvm'], ['CANGJIE_COMPILER', 'compiler'], ['FLATBUFFERS', 'flatbuffers']]) {
      env[`${prefix}_URL`] = `file://${inputs[name].bare}`; env[`${prefix}_SHA`] = inputs[name].sha;
    }
    const r = await run(['npx', '--yes', 'zx@8', path.join(fixture, 'ci/platform_tuples/fetch_sources.mjs')], {env, log: path.join(work, 'sources.log'), check: false});
    fs.writeFileSync(path.join(work, 'sources.rc'), `${r.exitCode}\n`);
    const heads = {};
    for (const [name, dir] of [['llvm', 'llvm-project'], ['compiler', 'cangjie-compiler'], ['flatbuffers', 'flatbuffers'], ['runtime', 'paired-runtime']]) {
      const head = await capture(['git', '-C', path.join(tuple, dir), 'rev-parse', 'HEAD'], {check: false}); heads[name] = head.stdout.trim();
    }
    check('fetch_sources_head', r.exitCode === 0 && Object.entries(inputs).every(([name, input]) => heads[name] === input.sha) &&
      r.stdall.includes('SOURCE-MIRROR none, falling back to') && noShellError(r.stdall) &&
      fs.existsSync(path.join(tuple, 'cangjie-compiler/schema/ModuleFormat.fbs')) && fs.existsSync(path.join(tuple, 'flatbuffers/CMakeLists.txt')), {rc: r.exitCode, heads});
  }
  const canonical = 'https://example.invalid/a?[b]*.git';
  const hit = await fetchHelper('checkout-hit', canonical, inputs.llvm.sha, `${canonical}=file://${inputs.llvm.bare}`);
  check('mirror_hit', hit.result.exitCode === 0 && await git('-C', hit.dest, 'rev-parse', 'FETCH_HEAD') === inputs.llvm.sha &&
    await git('-C', hit.dest, 'remote', 'get-url', 'origin') === canonical && hit.trace.includes(`file://${inputs.llvm.bare}`) && !hit.trace.includes(`fetch ${canonical}`), hit.result);
  for (const [name, url, sha, mirrors, required, message] of [
    ['invalid_message', `file://${inputs.llvm.bare}`, inputs.llvm.sha, 'not-a-mapping', undefined, 'invalid CJCJ_SRCBUILD_SOURCE_MIRRORS entry: not-a-mapping'],
    ['duplicate_message', 'https://example.invalid/a?.git', inputs.llvm.sha, `https://example.invalid/a?.git=file://${inputs.llvm.bare};https://example.invalid/a?.git=file://${inputs.compiler.bare}`, undefined, 'duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source: https://example.invalid/a?.git'],
    ['require_mirrors', 'https://example.invalid/missing.git', 'deadbeef', undefined, '1', 'source mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1'],
  ]) {
    const result = (await fetchHelper(name, url, sha, mirrors, required)).result;
    check(name, result.exitCode !== 0 && result.stdall.includes(message) && noShellError(result.stdall), result);
  }
  const urls = ['https://example.invalid/a?.git', 'https://example.invalid/a*.git', 'https://example.invalid/a[b].git', 'https://example.invalid/eq.git'];
  const values = ['file:///mirror-q', 'file:///mirror-star', 'file:///mirror-bracket', 'file:///mirror?x=1'];
  const glob = await run([shell, '-c', 'set -euo pipefail; source "$1"; shift; for url in "$@"; do srcbuild_git_resolve_source_mirror "$url"; done',
    'glob-contract', helper, ...urls], {env: {...base, CJCJ_SRCBUILD_SOURCE_MIRRORS: urls.map((url, i) => `${url}=${values[i]}`).join(';')}, log: path.join(work, 'glob.log'), check: false});
  fs.writeFileSync(path.join(work, 'glob.rc'), `${glob.exitCode}\n`);
  check('glob_exact', glob.exitCode === 0 && glob.stdall.trim() === values.join('\n'), glob);
  console.log(`CONTRACT_FAILS=${fails}`);
  assert.equal(fails, 0);
});
