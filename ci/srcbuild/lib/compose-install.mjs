import path from 'node:path';
import {fileDigest} from '../../bootstrap/sdk-flow.mjs';
export async function consumeStage3Compiler({sdk,product,lineage}){
 if(!lineage?.compilerSha256||await fileDigest(product)!==lineage.compilerSha256)throw new Error('COMPOSE_STAGE3 compiler target identity differs');
 const suffix=product.endsWith('.exe')?'.exe':'';
 const entry=path.join(sdk,'bin','cjc'+suffix);
 return {sdk,product,lineage,entry};
}
