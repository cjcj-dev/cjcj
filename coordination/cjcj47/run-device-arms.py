#!/usr/bin/env python3
"""Run on kkk2 only; preserve each input, diff, TAP, rc and source hashes."""
import concurrent.futures, difflib, hashlib, json, os, pathlib, shutil, subprocess, time
root = pathlib.Path('/root/sym_cjcj_47_implement_r5749367643')
source = root / 'candidate'
output = root / 'device-arms-final'
output.mkdir(exist_ok=True)
cuts = {
 'windows-product': ('ci/platform_matrix/windows-final-compiler.mjs', "const final = await resolveProductBinary(path.join('target', 'release', 'bin'), 'Windows W2', {windows: true});", 'const final = seedInstalled;'),
 'bootstrap-producer': ('ci/srcbuild/lib/bootstrap-handoff.mjs', "await fs.copyFile(compiler, path.join(sdk, 'bin', 'cjcj-stage2'));", "await fs.copyFile(path.join(inputSdk, 'bin', 'cjc'), path.join(sdk, 'bin', 'cjcj-stage2'));"),
 'stdx-consumer': ('build/srcbuild/stages/common.mjs', 'const cangjieHome = consumerSdk(config);', "const cangjieHome = path.join(config.repoPath('compiler'), 'output');"),
 'tools-consumer': ('build/srcbuild/stages/tools.mjs', 'const targetHome = consumerSdk(config);', "const targetHome = path.join(config.repoPath('compiler'), 'output');"),
 'sdk-consumer': ('build/srcbuild/stages/package.mjs', 'const compilerOutput = consumerSdk(config, config.target.primaryCompilerOutput());', "const compilerOutput = path.join(config.repoPath('compiler'), config.target.primaryCompilerOutput());"),
 'final-producer': ('ci/srcbuild/lib/final-compiler.mjs', 'await fs.copyFile(binary, installed);', "await fs.copyFile(path.join(path.dirname(binary), 'decoy'), installed);"),
 'package-consumer': ('scripts/package_sdk.mjs', 'await fs.copyFile(binary, installed);', "await fs.copyFile(path.join(sdk, 'bin', 'cjc'), installed);"),
 'entry-identity': ('ci/srcbuild/lib/bootstrap-handoff.mjs', '    || await sha256(entry) !== identity.entrySha256\n', ''),
 'producer-identity': ('ci/srcbuild/lib/bootstrap-handoff.mjs', '\n    || await sha256(identity.producer) !== identity.compilerSha256', ''),
}
tests = ['build/test/windows-final-compiler.test.mjs', 'build/test/bootstrap-handoff.test.mjs', 'build/test/cangjie-written-tools.test.mjs',
 'build/test/final-compiler.test.mjs', 'build/test/package-provenance.test.mjs',
 'ci/srcbuild/tests/product-binary.test.mjs', 'ci/srcbuild/tests/release-wire.test.mjs']
products = sorted({row[0] for row in cuts.values()})
env = dict(os.environ)
env['PATH'] = ':'.join([str(root/'tools/node_modules/.bin'), str(root/'bin'), '/root/sym2_M2', env['PATH']])
subprocess.run(['uptime'], stdout=(output/'uptime-before.txt').open('w'), check=True)
def digest(file): return hashlib.sha256(file.read_bytes()).hexdigest()
def run(arm):
 directory = output/arm
 if directory.exists(): raise RuntimeError('refuse overwriting an existing arm: '+arm)
 shutil.copytree(source, directory, symlinks=True, ignore=shutil.ignore_patterns('.git', 'node_modules'))
 (directory/'node_modules').symlink_to(root/'tools/node_modules', target_is_directory=True)
 if arm in cuts:
  relative, before, after = cuts[arm]
  file = directory/relative
  original = file.read_text()
  assert original.count(before) == 1, (arm, original.count(before))
  mutated = original.replace(before, after)
  file.write_text(mutated)
  (output/(arm+'.diff')).write_text(''.join(difflib.unified_diff(original.splitlines(True), mutated.splitlines(True), fromfile='a/'+relative, tofile='b/'+relative)))
 hashes = {name: digest(directory/name) for name in products+tests}
 (output/(arm+'-hashes.json')).write_text(json.dumps(hashes, indent=2)+'\n')
 command = ['/root/sym2_M2/node', '--test', '--test-reporter=tap', *tests]
 start=time.monotonic()
 with (output/(arm+'.tap')).open('w') as log:
  result=subprocess.run(command, cwd=directory, env=env, stdout=log, stderr=subprocess.STDOUT)
 wall=time.monotonic()-start
 lines=(output/(arm+'.tap')).read_text().splitlines()
 failed=[line for line in lines if line.lstrip().startswith('not ok')]
 summary={'arm':arm,'rc':result.returncode,'wall':wall,'command':command,'failures':failed,
  'counts':[line for line in lines if line.startswith(('# tests ', '# pass ', '# fail '))]}
 (output/(arm+'.json')).write_text(json.dumps(summary, indent=2)+'\n')
 return summary
with concurrent.futures.ThreadPoolExecutor(max_workers=11) as pool:
 summaries=list(pool.map(run, ['green', *cuts, 'restored']))
subprocess.run(['uptime'], stdout=(output/'uptime-after.txt').open('w'), check=True)
(output/'summary.json').write_text(json.dumps(summaries, indent=2)+'\n')
print(json.dumps(summaries, indent=2))
