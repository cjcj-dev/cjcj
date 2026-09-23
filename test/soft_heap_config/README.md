# Soft heap configuration transport

Run `run.py --compiler /path/to/candidate/cjc --product-loader /path/to/paired/runtime/lib --out /path/to/evidence`.
The compiler host loader is supplied by the caller. Each generated program runs three times on the paired runtime; compilation must succeed for every input, and only valid inputs may reach main. Leading, trailing and internal whitespace are preserved for the runtime parser to reject. The explicit 64MB hard limit makes the 128M soft case exceed it independently of host memory.

The separate `test/runtime_param_layout/run.sh` compares the actual macro @C declarations against the paired Cangjie.h, including all three HeapParam origin/soft fields and the enclosing RuntimeParam offsets.

`check_transport.py --compiler /path/to/candidate/cjcj-stage1 --llvm-dis /path/to/llvm-dis --out /path/to/evidence` checks the actual emitted option constant. It distinguishes this producer-only result from startup validation; the known missing runtime entry (#115) does not become a successful startup result. Reverting the soft-specific whitespace preservation makes only the leading/trailing cases fail their IR text assertions.
