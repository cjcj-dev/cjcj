#!/usr/bin/env zx
// Compile and run the young-collection corpus against the installed runtime.
// Counts young collections from MRT_REPORT ("Start Smooth Collector young").
// Fail-closed: young count must be >= MIN_YOUNG (default 20).

import fs from 'node:fs/promises'
import {existsSync} from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const here = import.meta.dirname
const minYoung = Number(process.env.GC_YOUNG_MIN || '20')
const youngBytes = process.env.MRT_STICKY_MINOR_YOUNG_BYTES || String(1 * 1024 * 1024)
const heap = process.env.cjHeapSize || process.env.CJ_HEAP_SIZE || '2GB'
const compiler = process.env.GC_YOUNG_COMPILER || process.env.CJC || 'cjc'
const src = process.env.GC_YOUNG_SRC || path.join(here, 'young_alloc.cj')
const work = process.env.GC_YOUNG_WORK || await fs.mkdtemp(path.join(os.tmpdir(), 'gc-young-'))
const reportPath = path.join(work, 'mrt.report.log')
const exe = path.join(work, 'young_alloc')
const buildLog = path.join(work, 'build.log')
const runLog = path.join(work, 'run.log')

await fs.mkdir(work, {recursive: true})

function log(msg) {
  console.log(`[gc-young] ${msg}`)
}

async function run(cmd, args, env, logFile) {
  const t0 = performance.now()
  const out = await $({nothrow: true, quiet: true, env})`${cmd} ${args}`
  const ms = Math.round(performance.now() - t0)
  const body = [
    `rc=${out.exitCode ?? 1} signal=${out.signal ?? 'none'} ms=${ms}`,
    '--- stdout ---',
    out.stdout || '',
    '--- stderr ---',
    out.stderr || '',
  ].join('\n')
  await fs.writeFile(logFile, body)
  return {exitCode: out.exitCode ?? 1, stdout: out.stdout || '', stderr: out.stderr || '', ms}
}

if (!existsSync(src)) {
  log(`FATAL: corpus missing: ${src}`)
  process.exit(2)
}

log(`compiler=${compiler}`)
log(`src=${src}`)
log(`work=${work}`)
log(`min_young=${minYoung} young_bytes=${youngBytes} heap=${heap}`)

const build = await run(compiler, [src, '-o', exe], process.env, buildLog)
log(`compile rc=${build.exitCode} ms=${build.ms}`)
if (build.exitCode !== 0) {
  console.log(build.stderr || build.stdout)
  process.exit(build.exitCode)
}

// Official cjc binaries lack the sticky barrier consumer symbol, so the pin
// runtime disables sticky minor unless FORCE_SLOW_PATH keeps it on. That path
// still executes real young collections (counted below) — enough for platform
// evidence, not a full sticky-closure product acceptance.
const runEnv = {
  ...process.env,
  cjHeapSize: heap,
  MRT_STICKY_MINOR: '1',
  MRT_STICKY_MINOR_FORCE_SLOW_PATH: '1',
  MRT_STICKY_MINOR_YOUNG_BYTES: youngBytes,
  MRT_REPORT: reportPath,
}

await fs.rm(reportPath, {force: true})
const ran = await run(exe, [], runEnv, runLog)
log(`run rc=${ran.exitCode} ms=${ran.ms}`)
if (ran.stdout) console.log(ran.stdout.trimEnd())
if (ran.stderr) console.log(ran.stderr.trimEnd())

let reportText = ''
if (existsSync(reportPath)) {
  reportText = await fs.readFile(reportPath, 'utf8')
} else {
  log(`WARN: MRT_REPORT missing at ${reportPath}`)
}

// Pin runtime logs: "[GC] Start Smooth Collector young gcIndex= ..."
const youngRe = /Start Smooth Collector young/g
const youngCount = (reportText.match(youngRe) || []).length
const majorRe = /Start Smooth Collector (?:heuristic|force|oom|user|backup|native_alloc)/g
const otherCount = (reportText.match(majorRe) || []).length

log(`YOUNG_COUNT=${youngCount} OTHER_GC_COUNT=${otherCount} report_bytes=${reportText.length}`)
log(`report_path=${reportPath}`)

if (process.env.GITHUB_STEP_SUMMARY) {
  const lines = [
    '### GC young corpus',
    '',
    `| Field | Value |`,
    `|---|---|`,
    `| platform | ${process.env.RUNNER_OS || os.platform()}/${process.env.RUNNER_ARCH || os.arch()} |`,
    `| compiler | ${compiler} |`,
    `| young_count | ${youngCount} |`,
    `| min_young | ${minYoung} |`,
    `| other_gc_count | ${otherCount} |`,
    `| compile_ms | ${build.ms} |`,
    `| run_ms | ${ran.ms} |`,
    `| run_rc | ${ran.exitCode} |`,
    `| young_bytes | ${youngBytes} |`,
    `| heap | ${heap} |`,
    '',
  ]
  await fs.appendFile(process.env.GITHUB_STEP_SUMMARY, lines.join('\n'))
}

if (ran.exitCode !== 0) {
  log(`FAIL: corpus process rc=${ran.exitCode}`)
  process.exit(ran.exitCode)
}
if (youngCount < minYoung) {
  log(`FAIL: young_count ${youngCount} < min ${minYoung}`)
  process.exit(3)
}
log(`PASS: young_count=${youngCount} >= ${minYoung}`)
process.exit(0)
