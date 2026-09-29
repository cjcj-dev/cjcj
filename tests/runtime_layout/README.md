Run `ci/test-codegen-runtime-layout.sh FRONTEND HOST_SDK PAIRED_LIBLLVM LLVM_REPO RUNTIME_REPO OUTPUT`.
The frontend must be the real candidate `cjc-frontend` entry. The two source repositories
must contain the commits named by the pins. The host SDK supplies its matching runtime
and std; the paired LLVM library must both produce and read the bitcode.

The object fixture compiles with debug information to reach boxed parameter stores.
The array fixture compiles together with the pinned std.core sources, because RawArray
is registered only for that package (TypeChecker.cj:1427). No compiler implementation
is rebuilt into the verifier. The verifier calls LLVM's C API on the resulting bitcode.
Presence and value assertions are independent. Missing witnesses are failures.

This checks frontend IR and numeric layout, not target execution or runtime build
qualification. Keep compilation errors separate from invariant failures. For controlled
faults use the real `GetSizeFromTypeInfo` index and `GetPayloadFromObject` slot step;
changing the verifier or rejecting bitcode during parsing is not a valid red arm.
