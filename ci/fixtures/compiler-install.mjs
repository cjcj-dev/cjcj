// Nonproduction bytes for handoff/cross transport tests, assembled by the
// product's installation transaction. This fixture grants no SDK qualification.
import {installRecipe} from '../bootstrap/sdk-flow.mjs';
import {verifyCompiler} from '../bootstrap/compiler_identity.mjs';
export async function installCompiler(sdk,product) {
  await installRecipe({root:sdk,recipe:{copies:[{from:product,to:'bin/cjcj-stage1'}],
    links:{'bin/cjc':'cjcj-stage1','bin/cjc-frontend':'cjcj-stage1'},
    metadata:{compilerFile:'bin/cjcj-stage1'}}});
  return verifyCompiler(sdk);
}
