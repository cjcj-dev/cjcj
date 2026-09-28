# RawArray debug layout

Run `run.py --compiler <real-stage1> --source <arrays.cj-or-std.fs-directory>
--jobs <1-or-64> --out <arm-directory>` with the validated compiler host SDK and
LLVM libraries in `CANGJIE_HOME` / `LD_LIBRARY_PATH`. The driver compiles with
`--no-sub-pkg -g --apc=1 --output-type=staticlib -O2` and inspects emitted DWARF.

The assertions preserve the upstream split: unsized `RawArray<$G_T>` has only
`$ti` (CodeGen/DIBuilder.cpp:804-836), whereas sized `RawArray<Int64>` has `$ti`,
`size`, and `elements` at offsets 0, 8, and 16
(CodeGen/CJNative/CJNativeDIBuilder.cpp:144-171). Presence and layout assertions
are evaluated separately and always printed. Restoring the old
`CGType.GetLayoutType` fallback must fail `unsized_rawarray_ti_only` while the
sized-array assertion continues to pass. Compare the complete readelf output
between worker counts after removing only its archive filename header.
