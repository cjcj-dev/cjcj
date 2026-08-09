#!/usr/bin/env bash
# Build the native llc, opt, and cjselfhost LLVM shim from pinned source trees.
set -euo pipefail

root="${TUPLE_ROOT:?TUPLE_ROOT is required}"
platform="${TUPLE_PLATFORM:?TUPLE_PLATFORM is required}"
targets="${LLVM_TARGETS:?LLVM_TARGETS is required}"
llvm_src="$root/llvm-project"
llvm_build="$root/llvm-build"
flatbuffers_src="$root/flatbuffers"
flatbuffers_build="$root/flatbuffers-build"
generated="$root/shim-generated"
output="fixed-toolchain/$platform"
log_dir="$root/logs"
mkdir -p "$log_dir" "$output"
exec > >(tee "$log_dir/tuple-build.log") 2>&1

case "$(uname -s)" in
    MINGW*|MSYS*) exe=.exe; pic_flag=;     bundle_static_llvm=1 ;;
    *)            exe=;     pic_flag=-fPIC; bundle_static_llvm=0 ;;
esac

cmake -G Ninja -S "$llvm_src/llvm" -B "$llvm_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLLVM_ENABLE_RTTI=OFF \
    -DLLVM_ENABLE_ZLIB=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_TARGETS_TO_BUILD="$targets" \
    -DLLVM_ENABLE_PROJECTS= \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_FLAGS="-gline-tables-only -include cstdint -include unordered_map -include map -include vector -include string"
cmake --build "$llvm_build" --target llc opt llvm-config --parallel 3

cmake -G Ninja -S "$flatbuffers_src" -B "$flatbuffers_build" \
    -DFLATBUFFERS_BUILD_TESTS=OFF \
    -DFLATBUFFERS_BUILD_FLATLIB=OFF \
    -DFLATBUFFERS_BUILD_SHAREDLIB=OFF \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++
cmake --build "$flatbuffers_build" --target flatc --parallel 3
mkdir -p "$generated/flatbuffers"
"$flatbuffers_build/flatc$exe" --no-warnings -c -o "$generated/flatbuffers" \
    "$root/cangjie-compiler/schema/ModuleFormat.fbs"

clang++ -std=c++17 -O2 ${pic_flag:+"$pic_flag"} -fno-rtti -fno-exceptions \
    -I"$llvm_src/llvm/include" -I"$llvm_build/include" \
    -I"$flatbuffers_src/include" -I"$generated" \
    -c runtime_shim/cjselfhost_llvmshim.cpp \
    -o "$output/cjselfhost_llvmshim.o"
gzip -n -c -9 "$llvm_build/bin/llc$exe" > "$output/llc.gz"
gzip -n -c -9 "$llvm_build/bin/opt$exe" > "$output/opt.gz"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

llc_sha="$(sha256_file "$llvm_build/bin/llc$exe")"
opt_sha="$(sha256_file "$llvm_build/bin/opt$exe")"
{
    printf 'LLVM_SHA=%s\n' "${LLVM_SHA:?LLVM_SHA is required}"
    printf 'LLC_SHA256=%s\n' "$llc_sha"
    printf 'OPT_SHA256=%s\n' "$opt_sha"
} > "$output/llvm-tools.manifest"

mkdir -p "$root/verify"
for tool in llc opt; do
    gunzip -c "$output/$tool.gz" > "$root/verify/$tool$exe"
    chmod 0755 "$root/verify/$tool$exe"
    "$root/verify/$tool$exe" --version | head -n 5
done
llc_version="$("$root/verify/llc$exe" --version | head -n 5)"
opt_version="$("$root/verify/opt$exe" --version | head -n 5)"
test "$llc_version" = "$opt_version"
grep -Fx "LLVM_SHA=$LLVM_SHA" "$output/llvm-tools.manifest"
grep -Fx "LLC_SHA256=$(sha256_file "$root/verify/llc$exe")" "$output/llvm-tools.manifest"
grep -Fx "OPT_SHA256=$(sha256_file "$root/verify/opt$exe")" "$output/llvm-tools.manifest"
node ci/llvm-tools-manifest.mjs validate core "$output/llvm-tools.manifest"
file "$output/cjselfhost_llvmshim.o"

if command -v llvm-nm >/dev/null 2>&1; then
    nm_tool=llvm-nm
else
    nm_tool=nm
fi
shim_exports="$($nm_tool -C "$output/cjselfhost_llvmshim.o" \
    | grep -cE ' [Tt] _?(LLVMGlobalObjectAddStringAttribute|LLVMSelfhost|CJOF)')"
test "$shim_exports" -ge 90
echo "shim exported symbols: $shim_exports"

if [[ "$bundle_static_llvm" == 1 ]]; then
    # cjcj calls the LLVM C API directly in addition to the C++ API used by
    # the shim. Preserve archive extraction at the final PE link instead of
    # folding the libraries into one relocatable object.
    llvm_components=(
        core analysis bitreader bitwriter irreader passes support target transformutils
        aarch64 arm x86
    )
    llvm_config="$llvm_build/bin/llvm-config$exe"
    static_dir="$output/llvm-static"
    mkdir -p "$static_dir"
    # llvm-config rejects --libfiles while any archive in the transitive
    # closure is missing, so build every static LLVM library without linking
    # unrelated tools such as llvm-lto and bugpoint.
    mapfile -t llvm_static_targets < <(
        ninja -C "$llvm_build" -t targets all \
            | grep -oE '^lib/libLLVM[A-Za-z0-9_]+\.a'
    )
    test "${#llvm_static_targets[@]}" -gt 0
    ninja -C "$llvm_build" -j 3 llc "${llvm_static_targets[@]}"
    read -r -a llvm_libfiles <<< "$($llvm_config --link-static --libfiles "${llvm_components[@]}")"
    test "${#llvm_libfiles[@]}" -gt 0
    : > "$output/llvm-static-libs.txt"
    for libfile in "${llvm_libfiles[@]}"; do
        test -s "$libfile"
        libname="${libfile##*/}"
        cp "$libfile" "$static_dir/$libname"
        printf '%s\n' "$libname" >> "$output/llvm-static-libs.txt"
    done
    read -r -a llvm_system_libs <<< "$($llvm_config --link-static --system-libs "${llvm_components[@]}")"
    printf '%s\n' "${llvm_system_libs[@]}" > "$output/llvm-system-libs.txt"
    echo "LLVM static archives: ${#llvm_libfiles[@]}"
    du -ch "$static_dir"/*.a | tail -n 1
fi

while IFS= read -r -d '' artifact; do
    printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
done < <(find "$output" -type f -print0 | sort -z)
