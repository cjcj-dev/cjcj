#!/usr/bin/env zx
// One release/archive/compiler contract for publisher and receipt consumers.
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {baseSdkDownload} from './release-component-provenance.mjs';
import {hostToolchainFromCjcVersion} from '../../ci/host-toolchain-pin.mjs';
import {getTarget} from './targets.mjs';

const execute = promisify(execFile);
const canonical = value => JSON.stringify(value, (_, row) => row && typeof row === 'object' && !Array.isArray(row)
  ? Object.fromEntries(Object.entries(row).sort(([a], [b]) => a.localeCompare(b))) : row);
async function digest(file) {
  const hash = crypto.createHash('sha256');
  const handle = await fs.open(file, 'r');
  try { for await (const chunk of handle.createReadStream()) hash.update(chunk); }
  finally { await handle.close(); }
  return hash.digest('hex');
}
// Read archives, never extract or execute archive scripts. Compare the complete
// logical payload, including contained directory aliases and read-only modes.
const archivePayload = String.raw`
import sys,os,json,tarfile,zipfile,hashlib,posixpath,stat
archive,root,readonly,compilerName=sys.argv[1:]
root=os.path.realpath(root); readonly=readonly=='1'
entries={}
def name(s):
    while s.startswith('./'): s=s[2:]
    s=s.rstrip('/')
    if not s or s.startswith('/') or any(p in ('..','') for p in s.split('/')) or '\\' in s:
        raise ValueError('unsafe archive member: '+s)
    return s
def put(n,row):
    n=name(n)
    if n in entries: raise ValueError('duplicate archive member: '+n)
    entries[n]=row
if archive.endswith('.zip'):
    with zipfile.ZipFile(archive) as z:
        for m in z.infolist():
            mode=m.external_attr>>16
            if m.is_dir(): row={'type':'directory','mode':mode&0o777}
            elif stat.S_ISLNK(mode): row={'type':'link','target':z.read(m).decode()}
            else: row={'type':'file','mode':mode&0o777,'sha256':hashlib.sha256(z.read(m)).hexdigest(),'size':m.file_size}
            put(m.filename,row)
else:
    with tarfile.open(archive,'r|gz') as t:
        for m in t:
            if m.isdir(): row={'type':'directory','mode':m.mode&0o777}
            elif m.isfile():
                h=hashlib.sha256(); f=t.extractfile(m)
                for b in iter(lambda:f.read(1048576),b''): h.update(b)
                row={'type':'file','mode':m.mode&0o777,'sha256':h.hexdigest(),'size':m.size}
            elif m.issym() or m.islnk(): row={'type':'link','target':m.linkname,'hard':m.islnk()}
            else: raise ValueError('special archive member: '+m.name)
            put(m.name,row)
compilerRel='bin/'+compilerName
prefixes=[n[:-len('/'+compilerRel)] for n in entries if n.endswith('/'+compilerRel)]
if len(prefixes)!=1: raise ValueError('archive requires one SDK root/bin/cjc')
prefix=prefixes[0]
if any(n!=prefix and not n.startswith(prefix+'/') for n in entries): raise ValueError('archive has unrelated roots')
def resolve(n,seen=()):
    if n in seen: raise ValueError('archive link cycle: '+n)
    if n not in entries:
        # A directory alias may occur in a path, not just at the leaf.
        parent,leaf=posixpath.split(n)
        if not parent or parent==n: raise ValueError('archive member missing: '+n)
        return resolve(resolve(parent,seen)[0]+'/'+leaf,seen+(n,))
    row=entries[n]
    if row['type']!='link': return n,row
    target=row['target']
    if target.startswith('/'): raise ValueError('absolute archive link: '+n)
    dest=posixpath.normpath(target if row.get('hard') else posixpath.dirname(n)+'/'+target)
    if dest!=prefix and not dest.startswith(prefix+'/'): raise ValueError('archive link escape: '+n)
    return resolve(dest,seen+(n,))
expected={}
def walk(logical,physical,ancestors):
    physical,row=resolve(physical)
    if physical in ancestors: raise ValueError('archive directory cycle: '+logical)
    if logical:
        expected[logical]=dict(row)
        if readonly: expected[logical]['mode'] &= ~0o222
    if row['type']=='directory':
        children=[n for n in entries if posixpath.dirname(n)==physical]
        for child in children:
            leaf=posixpath.basename(child)
            walk((logical+'/' if logical else '')+leaf,child,ancestors+(physical,))
walk('',prefix,())
actual={}
def scan(directory,logical,ancestors):
    for item in sorted(os.scandir(directory),key=lambda e:e.name):
        rel=(logical+'/' if logical else '')+item.name
        # Existing installer provenance is ancillary, never archive payload.
        if not logical and item.name in ('SDK.lock.json','MANIFEST.sha256','DONE','.cjv'): continue
        physical=os.path.realpath(item.path)
        if os.path.commonpath([root,physical])!=root: raise ValueError('SDK link escape: '+rel)
        s=os.stat(item.path)
        row={'type':'directory' if stat.S_ISDIR(s.st_mode) else 'file','mode':s.st_mode&0o777}
        if stat.S_ISREG(s.st_mode):
            h=hashlib.sha256()
            with open(item.path,'rb') as f:
                for b in iter(lambda:f.read(1048576),b''): h.update(b)
            row.update(sha256=h.hexdigest(),size=s.st_size)
        elif not stat.S_ISDIR(s.st_mode): raise ValueError('SDK special entity: '+rel)
        actual[rel]=row
        if row['type']=='directory':
            if physical in ancestors: raise ValueError('SDK directory cycle: '+rel)
            scan(item.path,rel,ancestors+(physical,))
scan(root,'',(root,))
if actual!=expected:
    keys=sorted(set(actual)|set(expected))
    bad=next(k for k in keys if actual.get(k)!=expected.get(k))
    wanted,found=expected.get(bad,{}),actual.get(bad,{})
    fields=sorted(k for k in set(wanted)|set(found) if wanted.get(k)!=found.get(k))
    detail=' '.join(k+' expected='+str(wanted.get(k))+' actual='+str(found.get(k)) for k in fields)
    raise ValueError('OFFICIAL_IDENTITY official archive payload mismatch: '+bad+' '+detail)
print(json.dumps(expected[compilerRel],sort_keys=True))
`;
export function validateOfficialSdkProof(proof, version) {
  if (proof?.schema !== 'official-sdk-identity-v1' || proof.requestedVersion !== version
    || proof.version !== version.replace(/^nightly-/, '') || proof.compiler?.version !== proof.version || proof.compiler?.rc !== 0
    || !/^[a-f0-9]{64}$/.test(proof.compiler?.sha256 || '')
    || hostToolchainFromCjcVersion(proof.compiler?.stdout || '') !== `nightly-${proof.version}`) {
    throw new Error('OFFICIAL_IDENTITY matching release/archive/compiler proof required');
  }
  const expected = baseSdkDownload(proof.platform, version);
  if (proof.archive?.sha256 !== expected.sha256 || proof.archive?.size !== expected.size
    || proof.archive?.repository !== expected.releaseRepository || proof.archive?.url !== expected.url
    || !path.isAbsolute(proof.archive?.path || '') || path.basename(proof.archive.path) !== expected.archive) {
    throw new Error('OFFICIAL_IDENTITY proof differs from pinned original release');
  }
  return proof;
}
export async function verifyOfficialSdkIdentity({root, version, archive, platform, readonly = false}) {
  // Keep the exact request: aliases cannot excuse a conflicting lock tag.
  const expected = baseSdkDownload(platform, version);
  if (version.replace(/^nightly-/, '') !== expected.version) throw new Error('OFFICIAL_IDENTITY requested version is not the release version');
  if (!archive || !path.isAbsolute(archive) || path.basename(archive) !== expected.archive) {
    throw new Error('OFFICIAL_IDENTITY original archive locator/name required');
  }
  const stat = await fs.stat(archive);
  if (!stat.isFile() || stat.size !== expected.size || await digest(archive) !== expected.sha256) {
    throw new Error('OFFICIAL_IDENTITY original archive differs from pinned release');
  }
  const {spec} = getTarget(platform);
  const payload = await execute('python3', ['-I', '-c', archivePayload, archive, root, readonly ? '1' : '0', `cjc${spec.exeSuffix}`],
    {maxBuffer: 1024 * 1024, timeout: 120000});
  const compiler = JSON.parse(payload.stdout);
  const environment = {...process.env, CANGJIE_HOME: root};
  for (const key of Object.keys(environment)) if (/^(LD_|DYLD_)/.test(key)) delete environment[key];
  const libraries = ['third_party/llvm/lib', `runtime/lib/${spec.runtimeTuple}`, 'tools/lib'].map(rel => path.join(root, rel)).join(path.delimiter);
  environment[spec.os === 'mac' ? 'DYLD_LIBRARY_PATH' : 'LD_LIBRARY_PATH'] = libraries;
  const result = await execute(path.join(root, 'bin', `cjc${spec.exeSuffix}`), ['--version'],
    {env: environment, timeout: 30000, maxBuffer: 1024 * 1024});
  if (await digest(path.join(root, 'bin', `cjc${spec.exeSuffix}`)) !== compiler.sha256) throw new Error('OFFICIAL_IDENTITY compiler changed during version verification');
  const actualVersion = hostToolchainFromCjcVersion(result.stdout).slice('nightly-'.length);
  if (actualVersion !== expected.version) throw new Error(`OFFICIAL_IDENTITY compiler mismatch: requested=${version} actual=${actualVersion}`);
  return {schema: 'official-sdk-identity-v1', platform, version: expected.version, requestedVersion: version,
    archive: {path: archive, sha256: expected.sha256, size: expected.size,
      repository: expected.releaseRepository, url: expected.url},
    compiler: {version: actualVersion, sha256: compiler.sha256, stdout: result.stdout, rc: 0}};
}
// Bind the complete policy implementation, including its existing pin/parser
// dependencies, rather than accepting a verifier nominated by an SDK lock.
export async function officialIdentityVerifier() {
  const files = ['build/lib/official-sdk-identity.mjs', 'build/lib/release-component-provenance.mjs',
    'build/lib/targets.mjs', 'build/lib/errors.mjs', 'ci/host-toolchain-pin.mjs',
    'ci/host_sdk_pin.env', 'ci/release/base-sdk-identities.json'];
  const repository = fileURLToPath(new URL('../..', import.meta.url));
  return {path: fileURLToPath(import.meta.url), files: Object.fromEntries(await Promise.all(files.map(async rel =>
    [rel, await digest(path.join(repository, rel))])))};
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const request = JSON.parse(await fs.readFile('/dev/stdin', 'utf8'));
    const verifier = await officialIdentityVerifier();
    if (canonical(request.verifier) !== canonical(verifier)) throw new Error('OFFICIAL_IDENTITY verifier policy changed');
    console.log(JSON.stringify(await verifyOfficialSdkIdentity(request.input)));
  } catch (error) { console.error(`OFFICIAL_IDENTITY ${error.message}`); process.exitCode = 1; }
}
