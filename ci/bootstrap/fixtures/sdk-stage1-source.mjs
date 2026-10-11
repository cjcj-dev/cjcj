#!/usr/bin/env zx
// Minimal real cjpm workspace. Keep the product package metadata/link recipes;
// replace only their dependency graph and Cangjie bodies for this loader fixture.
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
  members = ["packages/codegen", "packages/cjc"]
  build-members = ["packages/codegen", "packages/cjc"]
  compile-option = ""
  override-compile-option = ""
  link-option = ""
  target-dir = ""
`);
  for (const name of ['codegen', 'cjc']) {
    const recipe = await fs.readFile(path.join(repository, 'packages', name, 'cjpm.toml'), 'utf8');
    // The codegen link-option is copied verbatim from the production recipe.
    const metadata = recipe.split('[dependencies]')[0];
    await write(`packages/${name}/cjpm.toml`, metadata + (name === 'cjc'
      ? '[dependencies]\n  "cjcj::codegen" = { path = "../codegen" }\n' : ''));
  }
  await write('packages/codegen/src/fixture.cj', `package cjcj::codegen
foreign {
    func fixture_observe_target(): Int32
    func fixture_shim(): Int32
}
public func observeTarget(): Int32 {
    let domain = unsafe { fixture_observe_target() }
    let shim = unsafe { fixture_shim() }
    println("TARGET_FFI_RESULT domain=\${domain} shim=\${shim}")
    if (domain != 53 || shim != 53) { return 1 }
    return 0
}
`);
  await write('packages/cjc/src/main.cj', `package cjcj::cjc
import cjcj::codegen.observeTarget
main(): Int64 {
    return Int64(observeTarget())
}
`);
  await write('runtime_shim/cjc_runtime_config.c', 'int fixture_config(void){return 1;}\n');
}
