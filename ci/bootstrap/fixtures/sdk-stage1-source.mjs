#!/usr/bin/env zx
// Minimal real cjpm workspace. The executable consumes the product codegen
// link-option directly, so a second package cannot mask a broken link recipe.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const repository = fileURLToPath(new URL('../../..', import.meta.url));
export async function prepareStage1Source(source) {
  const write = async (rel, text) => {
    const file = path.join(source, rel);
    await fs.mkdir(path.dirname(file), {recursive: true});
    await fs.writeFile(file, text);
  };
  await write('cjpm.toml', `[workspace]
  members = ["packages/codegen"]
  build-members = ["packages/codegen"]
  compile-option = ""
  override-compile-option = ""
  link-option = ""
  target-dir = ""
`);
  const recipe = await fs.readFile(path.join(repository, 'packages/codegen/cjpm.toml'), 'utf8');
  // Only this fixture's package kind/name/dependencies change. Its link-option
  // remains the production string, expanded by real cjpm using CANGJIE_HOME.
  const metadata = recipe.split('[dependencies]')[0]
    .replace(/^\s*name = "codegen"$/m, '  name = "cjc"')
    .replace(/^\s*output-type = "static"$/m, '  output-type = "executable"');
  await write('packages/codegen/cjpm.toml', metadata);
  await write('packages/codegen/src/main.cj', `package cjcj::cjc
foreign {
    func fixture_observe_target(): Int32
    func fixture_shim(): Int32
}
main(): Int64 {
    let domain = unsafe { fixture_observe_target() }
    let shim = unsafe { fixture_shim() }
    println("TARGET_FFI_RESULT domain=\${domain} shim=\${shim}")
    if (domain != 53 || shim != 53) { return 1 }
    return 0
}
`);
  await write('runtime_shim/cjc_runtime_config.c', 'int fixture_config(void){return 1;}\n');
  // The controlled native device is part of the same real Git input as the
  // Cangjie project. Its source tuple is a fixture identity, not qualification.
  await write('native-fixture/library.c', String.raw`#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
const char *fixture_llvm_domain(void){return "TARGET";}
int fixture_observe_target(void){Dl_info i;if(!dladdr(fixture_llvm_domain,&i))return 1;printf("DOMAIN value=%s origin=%s home=%s\n",fixture_llvm_domain(),i.dli_fname,getenv("CANGJIE_HOME"));return 53;}
`);
  await write('native-fixture/domain-probe.c', String.raw`#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
extern const char *fixture_llvm_domain(void);
int main(void){Dl_info i;dladdr(fixture_llvm_domain,&i);printf("DOMAIN value=%s origin=%s home=%s\n",fixture_llvm_domain(),i.dli_fname,getenv("CANGJIE_HOME"));return 0;}
`);
  await write('native-fixture/entry-probe.c', String.raw`#include <stdio.h>
#include <string.h>
extern const char *fixture_llvm_domain(void);
int main(int argc,char **argv){printf("ENTRY_DOMAIN=%s\n",fixture_llvm_domain());for(int i=0;i<argc;i++){printf("ARGV_HEX=");for(const unsigned char *p=(unsigned char*)argv[i];*p;p++)printf("%02x",*p);puts("");}return argc>1&&!strcmp(argv[1],"--exit=37")?37:0;}
`);
  await write('native-fixture/shim.c', 'int fixture_shim(void){return 53;}\n');
  await write('native-fixture/fixture.h', '// target include fixture\n');

}
