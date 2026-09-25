#!/bin/bash
# Link the regression suite against normal product archives, not --test codegen.
set -euo pipefail
ulimit -c 0
product=${1:?normal cjpm product tree}
output=${2:?output ELF}
llvm=${3:?Assertions libLLVM-15.so}
shim=${4:?LLVM shim object built with the Assertions library headers}
source_dir=$(cd "$(dirname "$0")" && pwd)
args=()
libs=()
while IFS= read -r -d '' dir; do
  args+=(--import-path "$dir" -L "$dir")
done < <(find "$product/target/release" -mindepth 1 -maxdepth 1 -type d -print0)
while IFS= read -r -d '' archive; do libs+=("$archive"); done < <(find "$product/target/release" -name '*.a' -type f -print0 | sort -z)
link="--export-dynamic --start-group ${libs[*]} --end-group $shim $product/runtime_shim/cjc_runtime_config.o $llvm -lstdc++"
"$CANGJIE_HOME/bin/cjc" --test -O1 "${args[@]}" "$source_dir/NamedStructFactory_test.cj" --link-options "$link" -o "$output"
sha256sum "$output" "$llvm" "$shim" "${libs[@]}" > "$output.sha256"
