# Signed minimum remainder through the compiler CLI

Run `zx run.mjs /absolute/install/bin/cjc /absolute/host-sdk /absolute/results [candidate|cut|restored]`.
Use a compiler built from the recorded candidate, with its matching host SDK and backend.
The runner uses the ordinary driver to parse, typecheck, optimize, emit, assemble and link real programs,
then runs the generated executables. No private checker is the test subject.

Int8, Int16, Int32, Int64 and native signed width (64 bits on the admitted x86_64 host) each cover
constant and argv-derived dynamic operands under throwing, wrapping and saturating modes at O2.
Remainder must produce zero; division must continue diagnosing/throwing, wrapping to minimum,
or saturating to maximum respectively. Ordinary arithmetic is the independent control.
The cut changes only the real `IsSignedModOverflow` return to its frozen-baseline value;
the throwing constant-remainder compile must then reject with an arithmetic overflow diagnostic.
The cut arm records that expected observation and the failed acceptance invariant separately.
Each process rc and command, source identity and produced ELF identity is retained.

Specification: upstream 2a5ac6dcfb6563b8f8c36db1868dd3ed9645eba1.
