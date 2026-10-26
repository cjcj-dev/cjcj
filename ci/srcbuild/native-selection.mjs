// Planning selects a real input route. It is not evidence that a downloaded
// artifact, native installation or SDK has passed its consuming gates.
import {nativePair} from '../runtime-pin.mjs';
export function nativeSourceRoute(env=process.env) {
  const pair=nativePair(env,{requireHost:Boolean(env.CJCJ_NATIVE_RUNTIME_ARTIFACT||env.CJCJ_NATIVE_BUILD_INPUTS_ARTIFACT)});
  const runtime=env.CJCJ_NATIVE_RUNTIME_ARTIFACT||'';
  const build=env.CJCJ_NATIVE_BUILD_INPUTS_ARTIFACT||'';
  if(!runtime&&!build&&!env.CJCJ_NATIVE_INPUTS_ARTIFACT)return false;
  if(!pair||!runtime)throw Error('SOURCE_NATIVE_PAIR_AND_RUNTIME_REQUIRED');
  for(const [artifact,run] of [
    [runtime,env.CJCJ_NATIVE_RUNTIME_RUN_ID],
    [env.CJCJ_NATIVE_INPUTS_ARTIFACT,env.CJCJ_NATIVE_INPUTS_RUN_ID],
    ...(build?[[build,env.CJCJ_NATIVE_BUILD_INPUTS_RUN_ID]]:[]),
  ])if(!artifact||!/^[1-9][0-9]*$/.test(run||''))throw Error('SOURCE_NATIVE_ARTIFACT_RUN_REQUIRED');
  if(!build&&env.CJCJ_NATIVE_BUILD_INPUTS_RUN_ID)throw Error('SOURCE_NATIVE_BUILD_ARTIFACT_REQUIRED');
  return true;
}
