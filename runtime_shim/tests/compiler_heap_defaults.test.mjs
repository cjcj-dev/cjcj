import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';

test('compiler init defaults are local, respect explicit sources, and survive retained naming', () => {
  assert.equal(process.platform, 'linux', 'this native --wrap contract requires Linux');
  const dir = fs.mkdtempSync(path.join(process.env.CJCJ_NATIVE_TEST_DIR ?? os.tmpdir(), 'compiler-heap-'));
  const shim = path.resolve(import.meta.dirname, '..');
  const records = [];
  function run(name, argv, env = process.env) {
    const started = new Date().toISOString();
    const r = spawnSync(argv[0], argv.slice(1), {env, encoding:'utf8', timeout:30000});
    fs.writeFileSync(path.join(dir, name + '.stdout'), r.stdout ?? '');
    fs.writeFileSync(path.join(dir, name + '.stderr'), r.stderr ?? '');
    records.push({name, argv, started, ended:new Date().toISOString(), rc:r.status,
      signal:r.signal, error:r.error?.message ?? null});
    fs.writeFileSync(path.join(dir, 'commands.json'), JSON.stringify(records, null, 2));
    assert.equal(r.error, undefined, name); assert.equal(r.status, 0, name + ': ' + r.stderr);
    return r.stdout;
  }
  // Separate translation units exercise real GNU link wrapping, not a direct
  // call to __wrap. The stand-in records exactly the existing V1 runtime ABI.
  fs.writeFileSync(path.join(dir, 'runtime.c'), `
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
typedef struct {const char* name; const char* value;} Entry;
const char* seen;
void CJ_MRT_CjRuntimeInitWithConfigV1(const Entry* e, size_t n) {
    seen = getenv("cjSoftMaxHeapSize");
    for (size_t i=0; i<n; ++i) if (!seen && !strcmp(e[i].name,"cjSoftMaxHeapSize")) seen=e[i].value;
}
void CJ_MRT_CjRuntimeInit(void) {CJ_MRT_CjRuntimeInitWithConfigV1(NULL,0);}
`);
  fs.writeFileSync(path.join(dir, 'main.c'), `
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
typedef struct {const char* name; const char* value;} Entry;
extern const char* seen;
extern void CJ_MRT_CjRuntimeInit(void);
extern void CJ_MRT_CjRuntimeInitWithConfigV1(const Entry*, size_t);
int main(int argc,char** argv) {
    assert(argc==2);
    if (!strcmp(argv[1],"child")) {
        assert(!getenv("cjSoftMaxHeapSize"));
        CJ_MRT_CjRuntimeInit(); assert(!seen); puts("CHILD_LOW_HARD_OK"); return 0;
    }
    const char* expected=NULL;
    if (!strcmp(argv[1],"linked-soft")) {
        const Entry entries[]={{"cjSoftMaxHeapSize","12GB"}};
        CJ_MRT_CjRuntimeInitWithConfigV1(entries,1); expected="12GB";
    } else if (!strcmp(argv[1],"linked-octal-hard")) {
        const Entry entries[]={{"cjHeapSize","010000MB"}};
        CJ_MRT_CjRuntimeInitWithConfigV1(entries,1);
    } else if (!strcmp(argv[1],"linked-hard")) {
        const Entry entries[]={{"cjHeapSize","16GB"}};
        CJ_MRT_CjRuntimeInitWithConfigV1(entries,1); expected="8GB";
    } else {
        CJ_MRT_CjRuntimeInit();
        if (!strcmp(argv[1],"default") || !strcmp(argv[1],"parent")) expected="8GB";
        if (!strcmp(argv[1],"explicit")) expected="12GB";
    }
    assert((!expected&&!seen)||(expected&&seen&&!strcmp(expected,seen)));
    if (strcmp(argv[1],"explicit")) assert(!getenv("cjSoftMaxHeapSize"));
    if (!strcmp(argv[1],"parent")) {
        pid_t child=fork(); assert(child>=0);
        if (!child) {assert(!setenv("cjHeapSize","2GB",1)); execl(argv[0],argv[0],"child",NULL); _exit(99);}
        int status; assert(waitpid(child,&status,0)==child); assert(WIFEXITED(status)&&WEXITSTATUS(status)==0);
    }
    printf("CONFIG %s soft=%s\\n",argv[1],seen?seen:"unset"); return 0;
}
`);
  const cc = process.env.CC ?? 'cc';
  const flags = ['-std=c11','-O2','-D_POSIX_C_SOURCE=200809L','-Wall','-Wextra','-Werror'];
  for (const [name, src] of [['main',dir+'/main.c'],['runtime',dir+'/runtime.c'],
    ['config',shim+'/cjc_runtime_config.c'],['defaults',shim+'/cjc_heap_defaults.c']])
    run('cc-'+name,[cc,...flags,'-c',src,'-o',dir+'/'+name+'.o']);
  const exe=dir+'/cjcj-stage1';
  run('link',[cc,dir+'/main.o',dir+'/runtime.o',dir+'/config.o',dir+'/defaults.o','-pthread',
    '-Wl,--wrap=CJ_MRT_CjRuntimeInit','-Wl,--wrap=CJ_MRT_CjRuntimeInitWithConfigV1','-o',exe]);
  const env={...process.env,cjHeapSize:'16GB'}; delete env.cjSoftMaxHeapSize;
  for (const mode of ['default','linked-soft','parent']) run(mode,[exe,mode],env);
  run('explicit',[exe,'explicit'],{...env,cjSoftMaxHeapSize:'12GB'});
  run('low',[exe,'low'],{...env,cjHeapSize:'2GB'});
  const linked={...env}; delete linked.cjHeapSize;
  run('linked-hard',[exe,'linked-hard'],linked);
  // The consumed runtime parses this legal leading-zero hard as 4096 MiB.
  // Neither environment nor embedded-table selection may add an 8 GiB soft.
  run('octal-hard',[exe,'low'],{...env,cjHeapSize:'010000MB'});
  run('linked-octal-hard',[exe,'linked-octal-hard'],linked);
  console.log('COMPILER_HEAP_DEFAULTS_EVIDENCE '+dir);
});
