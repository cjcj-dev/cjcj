The input is the actual `std.core` LLVM IR produced by compiling this lane's
complete std.core sources with `--no-prelude --lto=full -O0 --dump-ir`.
Run `python3 check.py path/to/0-std.core.ll` after a successful compiler exit.

These checks cover emitted layout, FINAL kind, inherited referent access,
volatile queue fields, and callback publication. They do not establish runtime
lifecycle behavior. Mutation evidence must rebuild the real compiler and run
the same source input and checker; editing IR or assertions is not a red arm.
