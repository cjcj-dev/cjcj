import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
const managed=['run_finalizer_trigger.sh','run_phase_entry_trigger.sh','run_segmented_array_managed.sh'];
function required(root,member){const file=path.join(root,member);if(!fs.statSync(file).isFile())throw Error('missing runtime language input '+file);return file;}
export function languageSourceInputs(runtime,{installed=false}={}) {
  const unit=path.join(runtime,'tests/gc_unit');
  const entry=fs.readFileSync(required(unit,'gate_gc_unit.sh'),'utf8');
  const modern=entry.includes('gate_gc_unit.mjs');
  if(!modern&&!entry.includes('run_language_tests()'))throw Error('unsupported runtime language entry '+unit);
  const common=['gate_gc_unit.sh','run_finalizer_trigger.sh','finalizer_trigger.cj','run_phase_entry_trigger.sh',
    'phase_entry_trigger.cj','phase_entry_major.cj','run_so_reentry_bounded.sh','so_reentry_probe.cpp',
    'run_segmented_array_managed.sh','segmented_array_managed.cj'];
  for(const member of [...common,...(modern?['gate_gc_unit.mjs','language_toolchain.mjs','product_test_configuration.mjs']:
    ['language_toolchain.sh','language_toolchain.py','testable_product_hooks.py'])])required(unit,member);
  required(runtime,'build/resolve_runtime_headers.py');
  if(modern)required(runtime,'build/resolve_runtime_headers.mjs');
  if(installed&&!modern)for(const member of ['installed-language-entry.mjs','installed-language-inputs.mjs'])required(unit,member);
  return {modern,unit};
}

// Only the copied installed scripts are prepared. The selected producer source,
// its native gate, and all language payload/assertion bodies remain untouched.
// Three-line shell admission and compiler-call substitutions are thin wiring;
// orchestration and input handling live in zx mjs (migration tracking: cjcj#883).
export function prepareInstalledLanguage(runtime) {
  const {modern,unit}=languageSourceInputs(runtime);
  if(modern)return;
  for(const member of ['installed-language-entry.mjs','installed-language-inputs.mjs'])
    fs.copyFileSync(path.join(here,member),path.join(unit,member));
  for(const member of managed) {
    const file=path.join(unit,member),text=fs.readFileSync(file,'utf8');
    const block=/^source [^\n]*language_toolchain\.sh"\ngc_unit_language_admit\ngc_unit_language_environment$/gm;
    const expected=member==='run_phase_entry_trigger.sh'?2:1;
    const admission='LANGUAGE_INPUT_SHELL="$(zx "$(dirname "$0")/installed-language-inputs.mjs" --shell)"\neval "$LANGUAGE_INPUT_SHELL"';
    const compile='zx "$(dirname "$0")/installed-language-inputs.mjs" --compile';
    const preparedRuntime='SDK_RUNTIME="${GC_UNIT_SDK_RUNTIME_DIR:?}"';
    const count=value=>text.split(value).length-1;
    const sourceBlocks=[...text.matchAll(block)].length;
    // Runtime installations already carry these same prepared scripts. A
    // subsequent SDK install consumes them without repeating substitutions.
    if(sourceBlocks===0) {
      if(count(admission)!==1||/\bgc_unit_language_(?:admit|environment|compile)\b/.test(text)
          ||text.includes('language_toolchain.sh'))throw Error('unsupported runtime language admission '+member);
      if(count(compile)!==expected)throw Error('unsupported runtime compiler calls '+member);
      if(count(preparedRuntime)!==1)throw Error('unsupported runtime library input '+member);
      continue;
    }
    if(sourceBlocks!==1||count(admission)!==0||count(compile)!==0)
      throw Error('unsupported runtime language admission '+member);
    if((text.match(/\bgc_unit_language_compile\b/g)||[]).length!==expected)throw Error('unsupported runtime compiler calls '+member);
    const sourceRuntime='SDK_RUNTIME="${CANGJIE_HOME:-}/runtime/lib/linux_x86_64_cjnative"';
    if(count(sourceRuntime)!==1||count(preparedRuntime)!==0)throw Error('unsupported runtime library input '+member);
    const prepared=text.replace(block,admission).replaceAll('gc_unit_language_compile',compile)
      .replace(sourceRuntime,preparedRuntime);
    fs.writeFileSync(file,prepared);
  }
}
export function installedLanguageCommand(runtime) {
  const {modern,unit}=languageSourceInputs(runtime,{installed:true});
  return modern?['bash',path.join(unit,'gate_gc_unit.sh')]:['zx',path.join(unit,'installed-language-entry.mjs')];
}
