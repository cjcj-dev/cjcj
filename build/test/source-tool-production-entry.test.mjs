#!/usr/bin/env zx
import test from 'node:test';import assert from 'node:assert/strict';
import fs from 'node:fs/promises';import path from 'node:path';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
import {GATING,REGISTERED} from '../../ci/test-manifest.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const integration='build/test/source-tool-install-contract.integration.test.mjs';
test('SDK integration has an automatic production consumer while ordinary CI owns the controlled interfaces',async()=>{
 assert.ok(GATING.includes('build/test/source-tool-install-interface.test.mjs'));assert.ok(!GATING.includes(integration));
 const entry=REGISTERED.find(row=>row.file===integration);assert.equal(entry.executor,'workflow');
 const workflow=await fs.readFile(path.join(root,entry.workflow),'utf8');
 assert.ok(workflow.includes('run: node '+integration));
 const section=workflow.slice(workflow.indexOf('- name: Test real SDK source-tool installation'),workflow.indexOf('- name: Capture G2 SDK identity'));
 assert.match(section,/CJCJ_SRCBUILD_CONSUMER_SDK:/);assert.match(section,/RELEASE_EVIDENCE_TEST_ROOT:/);
 const code=await fs.readFile(path.join(root,integration),'utf8');
 assert.match(code,/await packageStage\.run\(config\)/);assert.match(code,/before/);assert.match(code,/tar/);assert.match(code,/cjcov/);
 assert.doesNotMatch(code,/hlePayloadFixture|cjcov:42|skip:/);
});
test('missing production SDK input exits nonzero before any target starts',()=>{
 const env={...process.env};for(const key of ['RELEASE_EVIDENCE_TEST_ROOT','CJCJ_SRCBUILD_CONSUMER_SDK','CANGJIE_WORKSPACE','CJCJ_OFFICIAL_SDK_ROOT','CJCJ_SRCBUILD_HOST_SDK'])delete env[key];
 const r=spawnSync(process.execPath,[path.join(root,integration)],{env,encoding:'utf8'});
 assert.equal(r.status,1,r.stderr);assert.match(r.stderr,/SOURCE_TOOL_SDK_INPUT_REQUIRED/);assert.doesNotMatch(r.stdout,/A8_PACKAGE_TARGET_ASSERTION_REACHED/);
 console.log('PRODUCTION_INPUT_REQUIRED_ASSERTION_REACHED');
});
