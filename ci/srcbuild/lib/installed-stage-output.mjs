// Read ordinary installed compiler and stage facts. No producer directory required.
import path from 'node:path';
import {readJson,fileDigest} from '../../bootstrap/sdk-flow.mjs';
import {sdkPlatform} from '../../bootstrap/sdk-platform.mjs';
export async function installedStageOutput(sdk,stage){
 const metadata=await readJson(path.join(sdk,'STAGE-INPUTS.json'));
 if(metadata.phase!==stage)throw new Error('STAGE_OUTPUT wrong installed stage');
 const platform=sdkPlatform(metadata.platform),product=path.join(sdk,metadata.compilerFile);
 const actual=await fileDigest(product);
 if(actual!==metadata.compilerSha256)throw new Error('STAGE_OUTPUT installed compiler differs from produced bytes');
 return {sdk,product,platform,lineage:{...metadata,compilerSha256:actual},std:{artifacts:sdk}};
}
