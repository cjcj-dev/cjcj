#!/usr/bin/env zx
import path from 'node:path';
import {buildIosRuntime, iosTargets} from '../lib/ios-runtime.mjs';
import {probeRequirement} from '../../release/platform-matrix.mjs';
$.stdio = 'inherit';
const required = name => {
  if (!process.env[name]) throw new Error(`${name} is required`);
  return process.env[name];
};
const source = path.join(path.resolve(required('CANGJIE_WORKSPACE')), 'cangjie_runtime');
const runtimeRef = required('RUNTIME_REF');
const actual = (await $({stdio: 'pipe'})`git -C ${source} rev-parse HEAD`).stdout.trim();
if (actual !== runtimeRef) throw new Error(`runtime source mismatch: ${actual} != ${runtimeRef}`);
const target = iosTargets.find(entry => entry.target === required('IOS_TARGET'));
if (!target) throw new Error('unknown iOS target');
const probe = probeRequirement('xcode-ios');
if (!probe.present) throw new Error(probe.detail);
const sysroot = (await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --show-sdk-path`).stdout.trim();
const toolBin = path.dirname((await $({stdio: 'pipe'})`xcrun --sdk ${target.sdk} --find clang`).stdout.trim());
const root = await buildIosRuntime({source, target, sysroot, toolBin, version: required('RUNTIME_VERSION'), runtimeRef});
await $`file ${root}/runtime/lib/${target.tuple}/libcangjie-runtime.dylib ${root}/runtime/lib/${target.tuple}/libboundscheck.dylib`;
await $`shasum -a 256 ${root}/runtime/lib/${target.tuple}/libcangjie-runtime.dylib ${root}/runtime/lib/${target.tuple}/libboundscheck.dylib`;
