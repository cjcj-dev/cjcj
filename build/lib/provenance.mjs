import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

const CJCJ_MARKER = Buffer.from('CJCJ-COMMIT:');
const PROVENANCE_FILE = 'PROVENANCE.txt';

function commandOutput(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, encoding: 'utf8'});
  return result.status === 0 ? result.stdout.trim() : '';
}

function validCommitByte(byte) {
  return (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) ||
    (byte >= 97 && byte <= 122) || byte === 45 || byte === 46 || byte === 95;
}

function validateCommit(value, label) {
  if (!/^[0-9A-Za-z._-]+$/.test(value)) {
    throw new Error(`${label} contains unsupported characters: ${JSON.stringify(value)}`);
  }
  return value;
}

export function sourceCommit(sourceDir, injected = process.env.CJSTD_COMMIT || '') {
  let commit = injected.trim();
  if (!commit) commit = commandOutput('git', ['rev-parse', 'HEAD'], sourceDir);
  if (!commit) commit = 'unknown';
  const status = commandOutput('git', ['status', '--porcelain'], sourceDir);
  if (status && !commit.endsWith('-dirty')) commit += '-dirty';
  return validateCommit(commit, 'CJSTD_COMMIT');
}

export async function compilerCommit(compiler) {
  const binary = await fs.readFile(compiler);
  const values = new Set();
  let offset = 0;
  while (offset < binary.length) {
    const marker = binary.indexOf(CJCJ_MARKER, offset);
    if (marker < 0) break;
    const begin = marker + CJCJ_MARKER.length;
    let end = begin;
    while (end < binary.length && validCommitByte(binary[end])) end += 1;
    if (end > begin) values.add(binary.subarray(begin, end).toString('ascii'));
    offset = begin;
  }
  if (values.size > 1) {
    throw new Error(`compiler has conflicting CJCJ-COMMIT stamps: ${[...values].join(', ')}`);
  }
  // Three outcomes, not two. The old code returned the bare string `unknown`
  // when it found no marker at all — and a binary that really is stamped
  // `CJCJ-COMMIT:unknown` (sourceCommit writes that word when git says nothing)
  // returned the same string. The caller then reported "carries no CJCJ-COMMIT
  // stamp", which is false for the second one. tools/whatis.py already split
  // these as `absent` vs `stamped-unknown`; this brings the build side to the
  // same vocabulary.
  //   ''        no marker anywhere      — the scanner only records `end > begin`,
  //                                       so the empty string cannot be a stamp value
  //   'unknown' marker present, value unusable
  //   <value>   marker present and usable
  return values.size === 1 ? [...values][0] : '';
}

// A stamp value is usable when it is a clean commit SHA. Anything else that is
// physically present (`unknown`, a version string, a truncated SHA) is
// `stamped-unknown`: someone did stamp it, they just did not stamp an identity.
export function classifyStamp(value) {
  if (value === '') return 'absent';
  if (/^[0-9a-f]{40}$/.test(value)) return 'stamped';
  return 'stamped-unknown';
}

async function artifactFiles(root, directory = root) {
  const files = [];
  const entries = await fs.readdir(directory, {withFileTypes: true});
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await artifactFiles(root, file));
    } else if (entry.isFile() && path.relative(root, file) !== PROVENANCE_FILE) {
      files.push(file);
    }
  }
  return files;
}

async function sha256(file) {
  const hash = createHash('sha256');
  hash.update(await fs.readFile(file));
  return hash.digest('hex');
}

// A field is either resolved, or explicitly not applicable, or unresolved. The
// old code wrote the bare string `unknown` for two very different situations —
// "looked and could not find it" (BUILT_BY_CJC probes the compiler binary) and
// "never looked" (BUILT_WITH_SDK only read an environment variable) — and a
// reader cannot tell them apart. That is the same collapse release-manifest.mjs
// stopped doing in cc41c37d; this brings the build side to the same contract.
export const STD_PROVENANCE_RESOLVED = 'resolved';
export const STD_PROVENANCE_NOT_APPLICABLE = 'not-applicable';
export const STD_PROVENANCE_UNRESOLVED = 'unresolved';

// One switch. Report-only writes the same reasons and names every unresolved
// field on stderr, it just does not fail the build; every current caller relies
// on the defaults for buildSdk/coloured/preflightC2, so failing closed today
// would turn every std build red. Flip this to true once the callers supply
// them (see REPORT-emitpop.md for the list of five call sites).
export const STD_PROVENANCE_FAIL_CLOSED_DEFAULT = false;

function resolved(value) {
  return {status: STD_PROVENANCE_RESOLVED, value: String(value)};
}

function unresolved(reason) {
  return {status: STD_PROVENANCE_UNRESOLVED, value: `${STD_PROVENANCE_UNRESOLVED}: ${reason}`, reason};
}

function notApplicable(reason) {
  return {status: STD_PROVENANCE_NOT_APPLICABLE, value: `${STD_PROVENANCE_NOT_APPLICABLE}: ${reason}`, reason};
}

// Supplied by the caller, or unresolved with the reason it is missing. These
// are never probed, so "not supplied" is the whole truth about them.
function fromCaller(value, envName) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text) return resolved(text);
  return unresolved(`caller supplied neither the argument nor ${envName}; this field is never probed`);
}

// Which way the generational post barrier was decided. It used to have two
// sources that disagreed -- the cjcj driver passed
// -cj-generational-post-barrier=true itself while an older pinned llc defaulted
// it off -- so recording which one won turned an afternoon of digging into
// reading one line.
//
// Only the backend decides now. The switch is gone from CJBarrierLowering
// (the colour test on scalar heap ref writes is unconditional), and the driver
// passes no barrier switch at all. So a compiler that srcbuild stamped was
// built against ci/llvm_pin.env and has the barrier on; anything else could
// have been built against an llc old enough to still carry the switch, and
// only its identity can say.
function barrierMode(builtBy, supplied) {
  const text = typeof supplied === 'string' ? supplied.trim() : '';
  if (text) return resolved(text);
  if (builtBy.status === STD_PROVENANCE_RESOLVED) {
    return resolved('backend-on (pinned llc; the cjcj driver passes no barrier switch)');
  }
  return unresolved(
    'compiler carries no CJCJ-COMMIT stamp, so which llc decided the barrier is unknown; '
      + 'supply barrierMode (or CJSTD_BARRIER_MODE) with the llc identity that decided it');
}

export async function writeStdProvenance({
  sourceDir,
  installPrefix,
  compiler,
  buildSdk = process.env.CANGJIE_HOME || '',
  coloured = process.env.CJSTD_COLOURED || '',
  preflightC2 = process.env.CJSTD_PREFLIGHT_C2 || '',
  barrier = process.env.CJSTD_BARRIER_MODE || '',
  note = process.env.CJSTD_PROVENANCE_NOTE || 'not supplied',
  failClosed = process.env.CJSTD_PROVENANCE_FAIL_CLOSED === '1' || STD_PROVENANCE_FAIL_CLOSED_DEFAULT,
  now = new Date(),
}) {
  const stdCommit = sourceCommit(sourceDir);
  const probedCommit = await compilerCommit(compiler);
  const probedState = classifyStamp(probedCommit);
  // Three states, three sentences. Collapsing the middle one into the first is
  // what this change removes: "never stamped" and "stamped with a word instead
  // of an identity" need different follow-up actions.
  const builtBy = probedState === 'stamped'
    ? resolved(probedCommit)
    : probedState === 'absent'
      // Probed and found nothing: the binary carries no CJCJ-COMMIT stamp, which
      // srcbuild injects (srcbuild.yml, "Inject selfhost compiler version"). So the
      // compiler is not an srcbuild product — that is a fact worth saying out loud.
      ? unresolved(`compiler ${path.basename(compiler)} carries no CJCJ-COMMIT stamp (not an srcbuild product)`)
      : unresolved(`compiler ${path.basename(compiler)} is stamped CJCJ-COMMIT:${probedCommit}, `
        + 'which is not a commit SHA (stamped-unknown): the stamping step ran but had no identity to write');
  const fields = {
    BUILT_BY_CJC: builtBy,
    BUILT_WITH_SDK: fromCaller(buildSdk, 'CANGJIE_HOME'),
    COLOURED: fromCaller(coloured, 'CJSTD_COLOURED'),
    PREFLIGHT_C2: fromCaller(preflightC2, 'CJSTD_PREFLIGHT_C2'),
    GENERATIONAL_POST_BARRIER: barrierMode(builtBy, barrier),
  };
  const missing = Object.entries(fields)
    .filter(([, field]) => field.status === STD_PROVENANCE_UNRESOLVED)
    .map(([name, field]) => `${name} (${field.reason})`);
  if (missing.length) {
    const summary = `std provenance unresolved: ${missing.join('; ')}`;
    if (failClosed) throw new Error(summary);
    console.error(`[provenance] WARNING ${summary}`);
    console.error('[provenance] report-only: set CJSTD_PROVENANCE_FAIL_CLOSED=1 to make this fail the build');
  }

  const files = (await artifactFiles(installPrefix))
    .sort((left, right) => path.relative(installPrefix, left).localeCompare(path.relative(installPrefix, right)));
  if (!files.length) throw new Error(`std install prefix has no artifacts: ${installPrefix}`);

  const lines = [
    // The compact first line stays whitespace-free so tools/provenance.sh keeps
    // matching it, but it no longer says `unknown` either: `unstamped` and
    // `stamped-unknown` say which of the three situations produced it.
    `CJSTD-COMMIT:${stdCommit} BUILT-BY:${
      probedState === 'stamped' ? probedCommit
        : probedState === 'absent' ? 'unstamped' : 'stamped-unknown'}`,
    `STD_SOURCE_COMMIT = ${stdCommit}`,
    `BUILT_BY_CJC = ${fields.BUILT_BY_CJC.value}`,
    `BUILT_WITH_SDK = ${fields.BUILT_WITH_SDK.value}`,
    `COLOURED = ${fields.COLOURED.value}`,
    `PREFLIGHT_C2 = ${fields.PREFLIGHT_C2.value}`,
    `GENERATIONAL_POST_BARRIER = ${fields.GENERATIONAL_POST_BARRIER.value}`,
    `NOTE = ${note}`,
    `BUILD-TIME-UTC:${now.toISOString()}`,
    'ARTIFACT-SHA256:',
  ];
  for (const file of files) {
    lines.push(`${await sha256(file)}  ${path.relative(installPrefix, file)}`);
  }
  const destination = path.join(installPrefix, PROVENANCE_FILE);
  await fs.writeFile(destination, `${lines.join('\n')}\n`);
  return destination;
}
