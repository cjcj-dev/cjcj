#!/usr/bin/env zx
// Fetch exact tuple inputs; retain the existing shared mirror transport policy.
import {fs, path, repo, entry, exit} from '../entry-common.mjs';
import {run, capture, required, logged} from './entry.mjs';
await entry(async () => {
  const root = required('TUPLE_ROOT', 11, 'TUPLE_ROOT is required');
  await run(['mkdir', '-p', `${root}/logs`]);
  await logged(import.meta.url, `${root}/logs/source-fetch.log`, async () => {
    async function fetchExact(url, sha, dest, sparse = '') {
      let gitDirectory = false;
      try { gitDirectory = fs.statSync(`${dest}/.git`).isDirectory(); } catch {}
      if (!gitDirectory) {
        await run(['git', 'init', dest]);
        await run(['git', '-C', dest, 'remote', 'add', 'origin', url]);
      }
      if (sparse) await run(['git', '-C', dest, 'sparse-checkout', 'set', sparse]);
      await run(['bash', '-c', 'set -euo pipefail; source "$1"; srcbuild_git_fetch "$2" "$3" "$4"',
        'fetch-tuple', path.join(repo, 'build/lib/srcbuild_git.sh'), dest, url, sha]);
      await run(['git', '-C', dest, 'checkout', '--detach', 'FETCH_HEAD']);
      const head = await capture(['git', '-C', dest, 'rev-parse', 'HEAD'], {check: false});
      process.stderr.write(head.stderr);
      if (head.stdout.replace(/\n+$/, '') !== sha) exit(1);
    }
    const runtime = path.join(repo, 'ci/fetch-llvm-runtime.mjs');
    await run(['npx', '--yes', 'zx@8', runtime, '--check-input', `${root}/paired-runtime`]);
    await fetchExact(required('LLVM_URL', 32), required('LLVM_SHA', 32), `${root}/llvm-project`);
    await run(['npx', '--yes', 'zx@8', runtime, `${root}/paired-runtime`]);
    // Original diagnostic pipeline is explicitly best effort (including missing header).
    await run(['bash', '-c', 'set -o pipefail; sed -n \'/enum EnumReflectionType/,/};/p\' "$1" | grep -c \'^  ERT_\' || true',
      'reflection-count', `${root}/llvm-project/llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h`]);
    await fetchExact(required('CANGJIE_COMPILER_URL', 41), required('CANGJIE_COMPILER_SHA', 41), `${root}/cangjie-compiler`, 'schema');
    await run(['test', '-f', `${root}/cangjie-compiler/schema/CjoFormat.fbs`]);
    await fetchExact(required('FLATBUFFERS_URL', 44), required('FLATBUFFERS_SHA', 44), `${root}/flatbuffers`);
    await run(['test', '-f', `${root}/flatbuffers/CMakeLists.txt`]);
  });
});
