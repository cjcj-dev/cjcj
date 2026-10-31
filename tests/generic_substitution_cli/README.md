# Generic substitution CLI coverage

Run `zx run.mjs /absolute/install/bin/cjc /absolute/host-sdk /absolute/results`.
The real candidate compiler builds and runs the nested generic enum/extension program and an
ordinary explicit-instantiation control. An incompatible explicit type argument must produce a
located type diagnostic. These tests supplement `test/reduce_multi_type_subst`'s exact multi-target
producer/consumer regression; they do not claim that the source program alone proves every mapping.
The implementation of upstream 15a1dfea7a4abf036182f1079922d7f9cdc57dbd already exists in the baseline.
