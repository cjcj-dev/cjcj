#!/usr/bin/env zx
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readJson} from '../../bootstrap/sdk-flow.mjs';
import {installedStageOutput} from '../lib/installed-stage-output.mjs';
import {produceFinalCompiler} from '../lib/final-compiler.mjs';
import {buildConfig} from '../../../build/lib/config.mjs';
import {packageStdx} from '../../../build/srcbuild/stages/package.mjs';
import {packageInstall} from '../lib/package-install.mjs';
const config=buildConfig({workspace:process.env.CANGJIE_WORKSPACE,targetKey:process.env.CJCJ_SRCBUILD_TARGET,
 cangjieVersion:process.env.SOURCE_SDK_VERSION,officialSdkRoot:process.env.CJCJ_OFFICIAL_SDK_ROOT});
const archive=path.join(config.softwareDir,`cangjie-sdk-${config.target.spec.sdkName}-${config.cangjieVersion}-cjcj.${config.target.spec.archiveFormat}`);
const targets=await readJson(process.env.CJCJ_SDK_TARGETS||path.join(config.workspace,'build-targets.json'));
const final=await installedStageOutput(path.join(config.softwareDir,'cangjie'),'stage3');
const compilerFacts=await readJson(path.join(targets.work,'build/stage3/compiler/compiler-inputs.json'));
const github=process.env.GITHUB_ACTIONS==='true';
const execute=promisify(execFile);
const git=async (...args)=>(await execute('git',args)).stdout.trim();
const actualCommit=await git('rev-parse','HEAD');
const selectedRepository=process.env.CJCJ_PACKAGE_SOURCE_REPOSITORY;
const selectedCommit=process.env.CJCJ_PACKAGE_SOURCE_COMMIT;
if(Boolean(selectedRepository)!==Boolean(selectedCommit))throw new Error('PACKAGE_SOURCE_SELECTION_REQUIRED');
if(selectedCommit&&(!/^[0-9a-f]{40}$/.test(selectedCommit)||selectedCommit!==actualCommit))
 throw new Error('PACKAGE_SOURCE_SELECTION_CHANGED');
let origin;
try{origin=await git('remote','get-url','origin');}catch(error){if(error.code!==2)throw error;}
if(selectedRepository&&origin&&selectedRepository!==origin)throw new Error('PACKAGE_SOURCE_REPOSITORY_CHANGED');
if(!github&&!selectedRepository&&!origin)throw new Error('PACKAGE_SOURCE_SELECTION_REQUIRED');
if(github&&process.env.GITHUB_SHA!==actualCommit)throw new Error('PACKAGE_SOURCE_SELECTION_CHANGED');
await produceFinalCompiler({binary:final.product,outdir:path.join(config.softwareDir,'final-compiler'),platform:config.target.spec.key,
 repository:github?`${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}.git`:selectedRepository||origin,
 commit:actualCommit,
 runId:github?process.env.GITHUB_RUN_ID:`local:${os.hostname()}:${crypto.randomUUID()}`,runAttempt:github?process.env.GITHUB_RUN_ATTEMPT:'1',
 std:targets.stages.find(s=>s.id==='stage3-std').output||path.join(targets.work,'targets/stage3-std'),lineage:compilerFacts});
await packageInstall({sdk:path.join(config.softwareDir,'cangjie'),target:config.target,version:config.cangjieVersion,
 officialSdkRoot:config.officialSdkRoot,archive});
await packageStdx(config);
