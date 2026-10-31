import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {BuildError} from './errors.mjs';
import crypto from 'node:crypto';
import {readPeSymbols} from './pe-symbols.mjs';

export const LOAD_BAD_MASK_SYMBOL = 'g_cjLoadBadMask';

function requireDirectory(directory, label) {
  if (!directory) throw new BuildError('runtime.split', `${label} is required`);
  const resolved = path.resolve(directory);
  if (!fs.statSync(resolved, {throwIfNoEntry: false})?.isDirectory()) {
    throw new BuildError('runtime.split', `${label} is not a directory: ${resolved}`);
  }
  return resolved;
}

function requireRuntime(file, label) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.split', `${label} runtime is missing: ${file}`);
  }
  return file;
}

function requireCompiler(file) {
  if (!fs.statSync(file, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.sdk-abi', `packaged compiler is missing: ${file}`);
  }
  return file;
}

function entryRecipe(file) {
  const recipe = file + '.entry';
  if (!fs.statSync(recipe, {throwIfNoEntry: false})?.isFile()) return null;
  const lines = fs.readFileSync(recipe, 'utf8').trimEnd().split('\n');
  if (lines[0] !== 'cjcj-sdk-entry-v1' || lines.length < 6) {
    throw new BuildError('runtime.split', `invalid installed entry recipe: ${recipe}`);
  }
  return lines;
}

// `installEntries` writes `<'/'.join(directory.split('/')).length>` as the ascent
// for the group it is installing, and `compiler_identity` independently requires
// `1` for the `bin` group, so the number is a producer fact and not a free field.
function recipeAscent(recipe) {
  const field = recipe[1];
  const ascent = Number(field);
  if (field !== String(ascent) || !Number.isSafeInteger(ascent) || ascent < 0 || ascent > 32) {
    throw new BuildError('runtime.split', `invalid installed entry ascent: ${field}`);
  }
  return ascent;
}

function recipeMemberLabel(relative, label) {
  if (!relative || path.isAbsolute(relative) || relative.startsWith('/') || relative.includes('\\')
    || relative.split('/').some(part => part === '..' || part === '.')) {
    throw new BuildError('runtime.split', `invalid installed entry member in ${label}: ${JSON.stringify(relative)}`);
  }
  return relative;
}

// The native launcher (ci/bootstrap/native-launcher/entry.cpp:60-82) resolves
// `/proc/self/exe`, reads the recipe beside those bytes, walks `ascent`
// directories up from the executable's own directory to reach the root, and
// refuses an absolute or escaping member.  Replay that here: the root is derived
// from the executable, not from whichever directory the caller passed in.
function launcherRecipe(executable) {
  if (!fs.statSync(executable, {throwIfNoEntry: false})?.isFile()) return null;
  const physical = fs.realpathSync(executable);
  const lines = entryRecipe(physical);
  if (!lines) return null;
  const ascent = recipeAscent(lines);
  let root = path.dirname(physical);
  for (let level = 0; level < ascent; level += 1) root = path.dirname(root);
  return {physical, lines, root, retained: recipeMemberLabel(lines[2], `${physical}.entry`),
    libraries: lines.slice(5).map(relative => recipeMemberLabel(relative, `${physical}.entry`))};
}

// The native entry forwards to the ordinary installed compiler. Read its
// execution path for symbol checks; the build manifest never controls execution.
function packagedCompiler(sdk, target) {
  const lines = entryRecipe(path.join(sdk, 'bin', 'cjcj-stage1' + target.spec.exeSuffix));
  if (lines) {
    const rel = lines[2];
    if (!rel || path.isAbsolute(rel) || rel.split('/').includes('..')) {
      throw new BuildError('runtime.sdk-abi', 'invalid installed compiler entry path');
    }
    return requireCompiler(path.join(sdk, rel));
  }
  return requireCompiler(path.join(sdk,'bin','cjc'+target.spec.exeSuffix));
}

function runtimeRelativePath(target, role) {
  const host = role === 'host';
  return path.join(
    'runtime',
    'lib',
    host ? (target.spec.hostRuntimeTuple || target.spec.runtimeTuple) : target.spec.runtimeTuple,
    host ? (target.spec.hostRuntimeLibrary || target.spec.runtimeLibrary) : target.spec.runtimeLibrary,
  );
}

// The runtime a compiler loads is decided by whichever loader the compiler's own
// execution path selects: an installed launcher rewrites the loader from its own
// recipe before exec'ing the retained bytes, while a source-build compiler output
// runs directly and is served by the host SDK runtime that hostLoaderPath
// selects. Read the recipe of the executable the caller will actually run instead
// of inferring the role from a directory or variable name, so a host SDK handed
// in for other purposes cannot be substituted for the compiler's real runtime and
// the runtime under test cannot be passed off as the host one.
export function compilerRuntimeDirectory({sdk, hostSdk, target, compiler}) {
  const sdkRoot = requireDirectory(sdk, 'SDK');
  const executable = compiler
    ? requireCompiler(compiler)
    : requireCompiler(path.join(sdkRoot, 'bin', 'cjc' + target.spec.exeSuffix));
  const recipe = launcherRecipe(executable);
  if (recipe) {
    for (const relative of recipe.libraries) {
      const directory = path.join(recipe.root, relative);
      if (fs.statSync(path.join(directory, target.spec.runtimeLibrary), {throwIfNoEntry: false})?.isFile()) {
        return directory;
      }
    }
    throw new BuildError(
      'runtime.split',
      `installed entry recipe declares no ${target.spec.runtimeLibrary} directory: ${recipe.physical}.entry`,
    );
  }
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_OFFICIAL_SDK_ROOT');
  return path.dirname(requireRuntime(path.join(hostRoot, runtimeRelativePath(target, 'host')), 'host'));
}

export function assertPlainHostRuntime({
  hostSdk,
  target,
  readSymbols = readRuntimeSymbols,
  log = console.log,
}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_OFFICIAL_SDK_ROOT');
  const hostRuntime = requireRuntime(
    path.join(hostRoot, runtimeRelativePath(target, 'host')),
    'host',
  );
  const hostCount = countLoadBadMask(readSymbols(hostRuntime, target));
  if (hostCount !== 0) {
    throw new BuildError(
      'runtime.split',
      `${LOAD_BAD_MASK_SYMBOL} count contract failed: host=${hostCount} path=${hostRuntime}; expected host=0`,
    );
  }
  const hostReal = fs.realpathSync(hostRuntime);
  log(`HOST_RUNTIME_ASSERT_PASS host=${hostCount} path=${hostReal}`);
  return {hostSdk: hostRoot, hostRuntime: hostReal, hostCount};
}

export function runtimeSplitPaths({hostSdk, targetSdk, target}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_OFFICIAL_SDK_ROOT');
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  const hostRelative = runtimeRelativePath(target, 'host');
  const targetRelative = runtimeRelativePath(target, 'target');
  return {
    hostSdk: hostRoot,
    targetSdk: targetRoot,
    hostRuntime: requireRuntime(path.join(hostRoot, hostRelative), 'host'),
    targetRuntime: requireRuntime(path.join(targetRoot, targetRelative), 'target'),
  };
}

export function readRuntimeSymbols(file, target) {
  if (target.spec.os === 'windows' && (!target.spec.crossCompile || /\.dll$/i.test(file))) return readPeSymbols(file, target, 'exports');
  const args = target.spec.os === 'darwin'
    ? ['-g', file]
    : ['-D', '--defined-only', file];
  const result = spawnSync('nm', args, {encoding: 'utf8'});
  if (result.status !== 0) {
    throw new BuildError(
      'runtime.split',
      `nm failed for ${file}: rc=${result.status} ${String(result.stderr || '').trim()}`,
    );
  }
  return result.stdout;
}

export function readCompilerSymbols(file, target) {
  if (target.spec.os === 'windows' && (!target.spec.crossCompile || /\.exe$/i.test(file))) return readPeSymbols(file, target, 'imports');
  const args = target.spec.os === 'darwin'
    ? ['-u', file]
    : ['-D', '--undefined-only', file];
  const result = spawnSync('nm', args, {encoding: 'utf8'});
  if (result.status !== 0) {
    throw new BuildError(
      'runtime.sdk-abi',
      `nm failed for packaged compiler ${file}: rc=${result.status} ${String(result.stderr || '').trim()}`,
    );
  }
  return result.stdout;
}

export function countLoadBadMask(symbols) {
  return String(symbols).split(/\r?\n/)
    .filter(line => new RegExp(`\\b${LOAD_BAD_MASK_SYMBOL}\\b`).test(line)).length;
}

function countSdkLoadBadMask(symbols, target) {
  const symbol = target.spec.os === 'darwin'
    ? `_${LOAD_BAD_MASK_SYMBOL}`
    : LOAD_BAD_MASK_SYMBOL;
  return String(symbols).split(/\r?\n/)
    .filter(line => new RegExp(`\\b${symbol}\\b`).test(line)).length;
}

export function assertSdkCompilerRuntimeAbi({
  sdk,
  target,
  readCompiler = readCompilerSymbols,
  readRuntime = readRuntimeSymbols,
  log = console.log,
}) {
  const sdkRoot = requireDirectory(sdk, 'SDK');
  const compiler = packagedCompiler(sdkRoot, target);
  const runtime = requireRuntime(
    path.join(sdkRoot, runtimeRelativePath(target, 'target')),
    'packaged',
  );
  const compilerCount = countSdkLoadBadMask(readCompiler(compiler, target), target);
  const runtimeCount = countSdkLoadBadMask(readRuntime(runtime, target), target);
  if (![compilerCount, runtimeCount].every(count => count === 0 || count === 1)) {
    throw new BuildError(
      'runtime.sdk-abi',
      `${LOAD_BAD_MASK_SYMBOL} ABI count is not boolean: compiler=${compilerCount} path=${compiler}; ` +
      `runtime=${runtimeCount} path=${runtime}`,
    );
  }
  if (compilerCount !== runtimeCount) {
    throw new BuildError(
      'runtime.sdk-abi',
      `${LOAD_BAD_MASK_SYMBOL} ABI mismatch: compiler=${compilerCount} path=${compiler}; ` +
      `runtime=${runtimeCount} path=${runtime}`,
    );
  }
  const compilerReal = fs.realpathSync(compiler);
  const runtimeReal = fs.realpathSync(runtime);
  log(
    `SDK_COLOUR_ABI_ASSERT_PASS compiler=${compilerCount} path=${compilerReal} ` +
    `runtime=${runtimeCount} path=${runtimeReal}`,
  );
  return {
    sdk: sdkRoot,
    compiler: compilerReal,
    runtime: runtimeReal,
    compilerCount,
    runtimeCount,
  };
}

export function assertRuntimeSplit({
  hostSdk,
  targetSdk,
  target,
  readSymbols = readRuntimeSymbols,
  log = console.log,
}) {
  const paths = runtimeSplitPaths({hostSdk, targetSdk, target});
  const hostCount = countLoadBadMask(readSymbols(paths.hostRuntime, target));
  const targetCount = countLoadBadMask(readSymbols(paths.targetRuntime, target));
  if (hostCount !== 0 || targetCount !== 1) {
    throw new BuildError(
      'runtime.split',
      `${LOAD_BAD_MASK_SYMBOL} count contract failed: host=${hostCount} path=${paths.hostRuntime}; ` +
      `target=${targetCount} path=${paths.targetRuntime}; expected host=0 target=1`,
    );
  }
  const hostReal = fs.realpathSync(paths.hostRuntime);
  const targetReal = fs.realpathSync(paths.targetRuntime);
  if (hostReal === targetReal) {
    throw new BuildError('runtime.split', `host and target runtime resolve to the same file: ${hostReal}`);
  }
  log(
    `RUNTIME_SPLIT_ASSERT_PASS host=${hostCount} path=${hostReal} ` +
    `target=${targetCount} path=${targetReal}`,
  );
  return {...paths, hostRuntime: hostReal, targetRuntime: targetReal, hostCount, targetCount};
}

export function hostLoaderPath({hostSdk, targetSdk, target, inherited = '', includeTargetLlvm = true}) {
  const hostRoot = requireDirectory(hostSdk, 'CJCJ_OFFICIAL_SDK_ROOT');
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  const hostRuntime = requireRuntime(
    path.join(hostRoot, runtimeRelativePath(target, 'host')),
    'host',
  );
  return [
    includeTargetLlvm ? path.join(targetRoot, 'third_party', 'llvm', target.spec.os === 'windows' ? 'bin' : 'lib') : '',
    path.dirname(hostRuntime),
    path.join(targetRoot, 'tools', 'lib'),
    inherited,
  ].filter(Boolean).join(path.delimiter);
}

export function targetLoaderPath({targetSdk, target, inherited = ''}) {
  const targetRoot = requireDirectory(targetSdk, 'target SDK');
  return [
    path.join(targetRoot, 'third_party', 'llvm', target.spec.os === 'windows' ? 'bin' : 'lib'),
    path.join(targetRoot, 'runtime', 'lib', target.spec.runtimeTuple),
    path.join(targetRoot, 'tools', 'lib'),
    inherited,
  ].filter(Boolean).join(path.delimiter);
}

export function assertRuntimeCommonCache({cache, runtimeTarget, log = console.log}) {
  if (!fs.statSync(cache, {throwIfNoEntry: false})?.isFile()) {
    throw new BuildError('runtime.split.cache', `CMake cache is missing after stdlib configure: ${cache}`);
  }
  const matches = fs.readFileSync(cache, 'utf8').split(/\r?\n/)
    .filter(line => line.startsWith('RUNTIME_COMMON_LIB_DIR:STRING='));
  if (matches.length !== 1) {
    throw new BuildError(
      'runtime.split.cache',
      `expected one RUNTIME_COMMON_LIB_DIR entry in ${cache}, found ${matches.length}`,
    );
  }
  const configured = path.resolve(matches[0].slice(matches[0].indexOf('=') + 1));
  const expectedRoot = path.resolve(runtimeTarget);
  if (configured !== expectedRoot && !configured.startsWith(`${expectedRoot}${path.sep}`)) {
    throw new BuildError(
      'runtime.split.cache',
      `RUNTIME_COMMON_LIB_DIR escaped target runtime: configured=${configured} expected_root=${expectedRoot}`,
    );
  }
  log(`RUNTIME_SPLIT_CMAKE_ASSERT_PASS configured=${configured} expected_root=${expectedRoot}`);
  return configured;
}

// Read the shell words emitted by CMake/Ninja, without executing the command.
// Unknown expansion is rejected in executable/loader paths, not guessed.
function generatedWords(line) {
  const words=[]; let word='', quote='', escaped=false;
  line=line.replace(/\$([ $:])/g, '$1');
  for(const c of line) {
    if(escaped){word+=c;escaped=false;continue;}
    if(c==='\\'&&quote!=="'"){escaped=true;continue;}
    if(quote){if(c===quote)quote='';else word+=c;continue;}
    if(c==='"'||c==="'"){quote=c;continue;}
    if(/\s/.test(c)){if(word){words.push(word);word='';}}else word+=c;
  }
  if(quote||escaped)throw new BuildError('runtime.split.commands','unclosed generated command quoting');
  if(word)words.push(word);return words;
}
function commandExecutable(word, environment, cwd) {
  if(/[$`]/.test(word))throw new BuildError('runtime.split.commands','unresolved compiler path: '+word);
  const candidates=word.includes('/')?[path.resolve(cwd,word)]
    :String(environment.PATH||'').split(path.delimiter).filter(Boolean).map(dir=>path.resolve(cwd,dir,word));
  for(const file of candidates) {
    try{fs.accessSync(file,fs.constants.X_OK);if(fs.statSync(file).isFile())return fs.realpathSync(file);}catch{}
  }
  throw new BuildError('runtime.split.commands','generated compiler is not executable: '+word);
}
export function assertHostRuntimeCommands({
  buildFile, hostRuntime, targetRuntime, loaderEnv = 'LD_LIBRARY_PATH', environment = {}, log = console.log,
}) {
  if (!fs.statSync(buildFile, {throwIfNoEntry: false})?.isFile())
    throw new BuildError('runtime.split.commands', `generated build file is missing: ${buildFile}`);
  const hostReal=fs.realpathSync(hostRuntime), targetReal=fs.realpathSync(targetRuntime);
  const runtimeName=path.basename(hostRuntime), tuple=path.basename(path.dirname(hostRuntime));
  const targetDirectory=path.dirname(targetReal);
  const targetSdk=path.resolve(path.dirname(targetRuntime),'../../..');
  const targetLib=path.join(targetSdk,'lib',path.basename(path.dirname(targetRuntime)));
  const real=file=>fs.realpathSync(file);
  let checked=0;
  const checkedPaths=new Map();
  for(const line of fs.readFileSync(buildFile,'utf8').split(/\r?\n/)) {
    if(!/^\s*COMMAND\s*=|^\s*command\s*=/.test(line))continue;
    if(!/\bcjc(?:\.exe)?(?:[\s"']|$)/.test(line))continue;
    const words=generatedWords(line.slice(line.indexOf('=')+1));
    let cwd=path.dirname(buildFile), segment=[];
    for(const word of [...words,'&&']) {
      if(!['&&',';','||'].includes(word)){segment.push(word);continue;}
      if(segment[0]==='cd'){cwd=path.resolve(cwd,segment[1]);segment=[];continue;}
      const at=segment.findIndex(v=>/^(cjc|cjc\.exe)$/.test(path.basename(v)));
      if(at<0){segment=[];continue;}
      const env={...environment};
      for(const token of segment.slice(0,at)) {
        const assignment=token.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s);
        if(assignment)env[assignment[1]]=assignment[2];
      }
      const executable=commandExecutable(segment[at],env,cwd),recipe=launcherRecipe(executable);
      const effectiveLoader=recipe?(recipe.lines[3]==='darwin'?'DYLD_LIBRARY_PATH':recipe.lines[3]==='windows'?'PATH':'LD_LIBRARY_PATH'):loaderEnv;
      const libraries=recipe?recipe.libraries.map(rel=>path.join(recipe.root,rel))
        :String(env[effectiveLoader]||'').split(path.delimiter).filter(Boolean).map(dir=>path.resolve(cwd,dir));
      if(libraries.some(dir=>/[$`]/.test(dir)))throw new BuildError('runtime.split.commands','unresolved compiler loader path');
      let expected=hostReal;
      if(recipe) {
        const retained=path.join(recipe.root,recipe.retained);
        requireCompiler(retained);
        // entry.cpp reports argv[0] beside libexec/compiler. The compiler's
        // adjacent runtime link and the entry recipe must select the same image.
        if(path.basename(path.dirname(retained))==='compiler'&&path.basename(path.dirname(path.dirname(retained)))==='libexec')
          expected=real(path.join(path.dirname(retained),'../runtime/lib',tuple,runtimeName));
        for(const dir of libraries) {
          if(!fs.existsSync(dir))continue;
          // An installed compiler can share its adjacent execution runtime
          // with its target. A raw host or separate execution SDK cannot.
          if(expected!==targetReal&&(real(dir)===targetDirectory||(fs.existsSync(targetLib)&&real(dir)===real(targetLib))))
            throw new BuildError('runtime.split.commands','compiler entry includes target libraries: '+dir);
        }
      }
      const selected=libraries.map(dir=>path.join(dir,runtimeName)).find(file=>fs.statSync(file,{throwIfNoEntry:false})?.isFile());
      if(!selected||real(selected)!==expected)
        throw new BuildError('runtime.split.commands',`generated cjc command selects wrong runtime: compiler=${executable} selected=${selected||'<missing>'} expected=${expected}`);
      checkedPaths.set(executable,real(selected));checked+=1;segment=[];
    }
  }
  if(checked===0)throw new BuildError('runtime.split.commands','no generated cjc command was checked in '+buildFile);
  log('RUNTIME_SPLIT_COMMAND_ASSERT_PASS '+JSON.stringify({checked,compilers:Object.fromEntries(checkedPaths),target:targetReal}));
  return checked;
}
