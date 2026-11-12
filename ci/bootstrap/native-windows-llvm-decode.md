# Windows host LLVM event evidence

`native-windows-llvm-trace.mjs CONFIG.json` runs the actual host `llc.exe
--version` under the existing kernel Process/Image ETW session. It preserves
ETL, tracerpt XML/summary, each child PID/rc/stdout/stderr, the actual DOS-device
mapping, parsed payloads and the resulting capture record. The session is
stopped only after this invocation successfully started it. A refused start
does not stop someone else's logger.

The collector calls `native-windows-llvm-decode.mjs`. Python's standard XML
parser reads tracerpt output; no Windows executable is simulated. Only Image
Load opcode 10, the payload ProcessId, the unique Process Start/End pair and
the recorded spawn interval contribute load evidence. Header PID, PE imports,
rundown events and the requested DLL path do not contribute. EventsLost and
BuffersLost must be zero in a finalized log header. Unknown or incomplete
schemas remain failures. NT paths use the same capture's QueryDosDevice data;
the observed DLL is resolved and hashed only after attribution succeeds.

On success `captureWindowsHostLlvm` returns `observation.status=DECODED`,
`execution.loaded` containing observed real paths, and `library.path/sha256`.
The shared selector owner must consume this result and retain its independent
compiler probe and source/installation checks. This producer change does not
edit or relax the selector. On failure capture.json retains NOT_DECODED,
original command outcomes and diagnostics; it does not manufacture loaded.

The offline public decoder takes `{xml,eventsFile,python,execution,executable,
library,devices,parentPid,output}`. `execution` is the actual collector command
record in production. Tests supply explicitly synthetic XML and command
records to exercise the real parser and CLI on Linux. They prove only parser
and attribution behavior, not Windows capture or a usable Windows SDK.

Finite gate: `node --test ci/bootstrap/native-windows-llvm-decode.test.mjs
ci/bootstrap/native-windows-llvm-trace.test.mjs`. A product cut of the observed
DLL-path comparison must fail the wrong-path negative while the positive,
other-PID and event-loss controls retain their outcomes. Restore the decoder
before the final gate. Native Windows logman/tracerpt/QueryDosDevice execution
and real DLL attribution remain NOT_RUN until the standard runner is admitted.

Schema references: [Image Load](https://learn.microsoft.com/en-us/windows/win32/etw/image-load),
[Process events](https://learn.microsoft.com/en-us/windows/win32/etw/process-typegroup1),
[log header](https://learn.microsoft.com/en-us/windows/win32/etw/eventtrace-header),
[tracerpt](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/tracerpt).

The kernel tracerpt XML uses System/Provider GUID
`9e814aad-3204-11d2-9a82-006008a86939` and a separate
`ExtendedTracingInfo/EventGuid` for Header, Process and Image event classes.
Both identities are retained; only kernel-provider events with the relevant
class/opcode can qualify. Numeric padding is trimmed only while parsing numbers;
raw payloads remain intact. Timestamp offsets and up to nine fractional digits
are compared without losing precision. Other Process opcodes (rundown and
performance metadata) cannot supply the Start/End lifetime.

`native-windows-llvm-replay.test.mjs` replays seven byte-preserved events from
run 43236671148 and tests loss, missing header/logs, GUID confusion, wrong loaded
path and rundown rejection through the public decoder. Set
`TRACE_REPLAY_ORIGINAL` to the original windows-llvm-trace directory to replay
the complete XML with the same original capture record. This is offline replay;
it does not execute the recorded Windows commands or qualify the native entry.
See [Microsoft's tracerpt XML example](https://learn.microsoft.com/en-us/archive/msdn-magazine/2009/september/core-os-events-in-windows-7-part-1#event-tracing-for-windows).
