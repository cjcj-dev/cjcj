// The single installer. Keeps the three runtime roles apart: product runtime/lib/<target>,
// compiler execution .compiler-exec/, and the untouched official host .host/runtime/lib/<host>.
import fs from 'node:fs';
import path from 'node:path';
import {verifyLayout} from './verify.mjs';

export function installDescriptor({label, work, install, selection, tools, production, buildJavaInterop, javaJdk}) {
  if (!path.isAbsolute(install) || !path.isAbsolute(work)) throw new Error('INSTALL_ABSOLUTE_PATHS');
  return {work: path.join(work, `${label}-work`), install, selection, tools, production,
    ...(buildJavaInterop ? {buildJavaInterop: true, javaJdk} : {})};
}

// Runs the established installer once; on failure the partial destination is removed so no half
// product survives. The final (non-stage) install must pass the role-layout check.
export async function installSdk({runner, label, descriptor, evidence, cli, finalAsset}) {
  const file = path.join(evidence, `${label}.descriptor.json`);
  if (fs.existsSync(descriptor.install)) throw new Error(`INSTALL_DESTINATION_EXISTS ${descriptor.install}`);
  fs.writeFileSync(file, JSON.stringify(descriptor, null, 2) + '\n');
  try {
    runner.run(label, [process.execPath, cli, 'install', '--inputs', file, '--no-package']);
    if (finalAsset) return verifyLayout(descriptor.install, finalAsset);
    return null;
  } catch (error) {
    fs.rmSync(descriptor.install, {recursive: true, force: true});
    throw error;
  }
}
