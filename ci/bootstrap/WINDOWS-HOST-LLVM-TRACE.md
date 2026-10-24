# Windows native host LLVM execution evidence

TASK19:06 interface investigation, following the Python19:00 experiment.
No Windows trace has run. No `loaded` field or platform PASS is produced by
this document. CI owns `select-native-host.mjs` and its shared caller; the
platform producer owns the native observation implementation and dependencies.
Its current unsupported-platform rejection remains until that implementation
has actual native evidence.

## Existing caller and concrete native entry

CI's `select-native-host.mjs` executes the original selected host's
`bin/cjc.exe host-llvm.cj --output-type=staticlib -o libhostprobe.a`, then
`third_party/llvm/bin/llc.exe --version` separately. The LLVM attribution is to
that llc process, not automatically to cjc or its subprocesses. Keep both actual
command results and the compiler output identity. Resolve the expected DLL from
`sdkPlatform(...).llvmDirectory/llvmLibrary` and hash the actual selected file.
PE imports only establish static dependencies; they do not populate `loaded`.

For an unmodified, short-lived llc, use Windows ETW image-load events. Ordinary
module-list polling can miss the whole process and cannot close this edge.
A separate Python LoadLibrary process would establish only that Python process's
load, not the llc invocation's load. No debugger attach, injected DLL or compiler
patch is needed for ETW; if a later failure needs a debugger, preserve it and
hand it to the existing Grok route.

## Native platform dependencies and capture sequence

Windows x64, the actual fixed official host, paired N/AST inputs for the caller,
an admitted official runner, writable private evidence directory, and an
existing elevated ETW-capable execution context are required. No request to
change account identity, enable a service, change tracing privileges or start a
runner is implied. A refused trace is a recorded failure, not a fallback to an
expected path. The original organization larger-runner 404 remains final.

Microsoft documents these built-in tools and the kernel image-load provider:

```
logman query providers "Windows Kernel Trace"
logman start "NT Kernel Logger" -p "Windows Kernel Trace" (process,img) -o <private>/host-llvm.etl -ets
<original-host>/third_party/llvm/bin/llc.exe --version
logman stop "NT Kernel Logger" -ets
tracerpt <private>/host-llvm.etl -o <private>/host-llvm.xml -of XML -summary <private>/host-llvm-summary.txt
```

These are native command specifications, NOT executions or verified command
results. The producer must pass the parenthesized flags as one literal argument
rather than unquoted shell syntax. It must start tracing before creating llc,
record the actual spawned PID/argv/start/exit/rc, and stop only the session that
this invocation successfully created. An already-running kernel logger or
permission refusal must leave the other session intact. No unqualified
`logman stop`, no global cleanup, and no automatic identity change.

The built-in CLI is sufficient for a first native capture, while the decoder
must use the actual emitted schema. ETW's StartTrace/ControlTrace and TDH event
metadata provide the normal native API route if the CLI summary does not expose
loss counters or payload fields reliably. No success parser has been invented
from hand-written XML. Capture original ETL/XML/summary before implementing an
adapter against the admitted host's actual output.

## Raw capture implementation

`node ci/bootstrap/native-windows-llvm-trace.mjs config.json` now provides the
native command capture sequence above. CI may import `captureWindowsHostLlvm`
for the observation attempt, with its existing `cleanSdkEnvironment` result:

```json
{
  "host": "C:/private/official-host",
  "work": "C:/private/evidence/host-trace-attempt-1",
  "tools": {
    "logman": "C:/Windows/System32/logman.exe",
    "tracerpt": "C:/Windows/System32/tracerpt.exe"
  }
}
```

The work parent must exist; the attempt directory must not. Each native command
has separate `.stdout`, `.stderr` and `.json` files with actual argv, spawned
PID, time bounds, own rc/signal and preparation/spawn failures. `capture.json`
references originals relatively and binds tool/executable hashes. A nonzero llc
rc remains a failure even when stop/export succeeds. A failed session start
never leads to stopping someone else's session. Only a successful owned start
permits stop; cancellation stops our session without reusing the aborted signal.

The exported result has `captureRc` and `observation.status=NOT_DECODED`, no
`loaded`. Even a successful raw capture makes the CLI exit **2**, explicitly
`WINDOWS_LLVM_LOAD_EVIDENCE_NOT_DECODED`; it cannot masquerade as a successful
selection. This is the first native evidence collector, not the completed
loader verifier. Once a permitted native run supplies ETL/XML/summary, this
same producer owner implements the actual metadata/path/loss decoder and
validates it; CI owns only the shared selection/caller composition. Until then,
CI must keep its Windows rejection. Do not read a raw capture as validation.

## Facts delivered to the existing caller

Keep `hostLlvm.execution.argv/rc/executableSha256/stdout/loaded` semantics.
Add ordinary original-file references under that same execution to ETL,
decoded events, command results and trace-loss facts. No receipt or permission
field. `loaded` is derived only after all of the following hold:

- Actual process start/exit matches the spawned llc PID and executable during
  this capture. Bind the lifetime, not an unbounded PID match that allows reuse.
- Image provider GUID `2cb15d1d-5fc1-11d2-abe1-00a0c911f518`, Load opcode10,
  payload ProcessId (not the event-header PID), FileName and event timestamp
  identify a load into that process. DCStart/DCEnd rundown and other processes
  do not substitute for the load. Preserve raw payload and decoded record.
- Convert the observed NT-device path using the capture host's real DOS-device
  mapping, then resolve/case-normalize it. Do not invent a C: prefix or replace
  it with the selected expected path. Hash the observed on-disk DLL and compare
  against the selected host's DLL; reject foreign LLVM paths.
- Query/retain actual EventsLost and LogBuffersLost and require zero; missing
  loss metadata is incomplete evidence. A zero loss counter alone is not a
  positive load observation. Keep provider/start/stop/decoder rc separately.

The native validation must include an actual positive llc load, an unrelated
process or non-LLVM load control, and a controlled omission of the image-load
provider or actual event consumption that makes the target invariant fail,
followed by restoration. This remains NOT_RUN with the current Linux fixture
budget; serialized events cannot stand in for native load evidence.

## Primary references read

- [Microsoft Image provider](https://learn.microsoft.com/en-us/windows/win32/etw/image): image-load enable flag, load opcode versus rundown.
- [Microsoft Image_Load payload](https://learn.microsoft.com/en-us/windows/win32/etw/image-load): ProcessId and FileName fields.
- [Microsoft kernel ETW CLI example](https://learn.microsoft.com/ko-kr/archive/msdn-magazine/2009/september/core-os-events-in-windows-7-part-1): logman provider flags and payload/header PID distinction.
- [Microsoft tracerpt](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/tracerpt): ETL to XML and summary output.
- [Microsoft trace properties](https://learn.microsoft.com/en-us/windows/desktop/ETW/event-trace-properties): EventsLost and LogBuffersLost output semantics.

The API and command facts support this proposed native route. Current runner
privileges, actual XML schema, observed library paths and capture resource peak
are not inferred from those documents and remain unmeasured.
