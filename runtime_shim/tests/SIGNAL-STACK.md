# Compiler alternate signal stack

`packages/utils/src/Signal.cj` calls `CJCJ_EnsureAltSignalStack` once through C2N.
The existing `cjc_runtime_config.o` carries the helper; the workspace link option
includes it for package consumers as well as the compiler executable. Windows
keeps its exception-handler path and compiles no pthread/sigaltstack helper.

The helper's stack_t records are native invocation locals. A pthread key owns an
allocated buffer, not a Cangjie coroutine. Existing active or sufficiently large
enabled stacks are retained, including host-runtime stacks. A thread-exit key
destructor restores its saved registration before freeing an installed buffer;
if another owner replaced the stack, that registration is preserved. Query or
restore failure retains the allocation with a diagnostic rather than freeing
registered memory. The process's main thread may terminate without pthread key
destructors; process teardown reclaims that allocation. No process-wide cleanup
frees live workers' stacks, and no new target-runtime interface is introduced.

Run the Linux native component checks with `zx runtime_shim/tests/run_signal_stack.mjs OUTPUT`
inside the approved resource scope. Two real pthreads remain alive while private
stack_t observations and native tids are checked for disjoint live ranges. The
same test verifies stable reentry and actual pthread-exit restoration/free.
Independent threads with preinstalled stacks retain their own registrations.
Link wrappers cover query/allocation/key/install errors and the active-stack
branch without delivering signals. These injected branches are separate from
the real pthread ownership/exit observations. A cut changes the production
allocation to one shared buffer; the overlap assertion must fail while the
preinstalled-stack control passes. The normal object is then consumed again.

The additional CLI wrapper is only a test link input: it observes the real
utils-to-native call and can return EIO to test the existing InternalError path.
It is never included in a production compiler. Actual Main/parser CLI evidence
is required separately; the native component checks alone do not grant it.
This defect is independent of the still-unattributed collection LTO SIGSEGV.
