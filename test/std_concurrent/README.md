# std.concurrent registration regression

Upstream 5e112d4acc86b6376635479a9e808c4f3e467785 adds the `std.concurrent`
library entry (`include/cangjie/Driver/Stdlib.inc:32`) and its `cr` symbol
code (`include/cangjie/Mangle/StdPkg.inc:80`, `demangler/Utils.h:142`).

`registration.cj` links the actual stage1 build's product archives. It checks
public library naming and symbol APIs, with `std.collection.concurrent` (`bh`)
and `std.binary` (`ar`) as independent controls. These are library API checks;
they do not claim that the alpha.06 concurrent library can be linked.

`concurrent.cj` and `collection_concurrent.cj` are compiled by the real stage1
compiler. The gate reads generated object symbols and LLVM IR, including the
file initializer produced by AST-to-CHIR and the compressed function name.
They define minimal packages and do not substitute implementations of compiler
components or the standard concurrent API.

Run `python3 scripts/std_concurrent_gate.py --help` for the explicit compiler,
product archive directory, and evidence directory inputs. Use a private SDK
and the matching host runtime/LLVM environment when running the compiler.
