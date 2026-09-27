#!/usr/bin/env zx
import path from 'node:path';
import {buildAndroidRuntime} from '../lib/android-runtime.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
const workspace = path.resolve(required('CANGJIE_WORKSPACE'));
if (workspace === path.parse(workspace).root) throw new Error('workspace must not be a filesystem root');
const probe = probeRequirement('android-ndk');
if (!probe.present) throw new Error(probe.detail);
const ndk = probe.detail.slice(probe.detail.indexOf('=') + 1);
const root = await buildAndroidRuntime({workspace, ndk, version: required('RUNTIME_VERSION'), runtimeRef: required('RUNTIME_REF')});
await $`file ${root}/runtime/lib/linux_android_aarch64_cjnative/libcangjie-runtime.so`;
await $`sha256sum ${root}/runtime/lib/linux_android_aarch64_cjnative/libcangjie-runtime.so ${root}/runtime/lib/linux_android_aarch64_cjnative/libboundscheck.so`;
