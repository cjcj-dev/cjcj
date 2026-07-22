#!/usr/bin/env bash
# Build the native llc and cjselfhost LLVM shim from pinned source trees.
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
    MINGW*|MSYS*) exe=.exe; pic_flag= ;;
    *)            exe=;     pic_flag=-fPIC ;;
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
cmake --build "$llvm_build" --target llc --parallel 3

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

mkdir -p "$root/verify"
gunzip -c "$output/llc.gz" > "$root/verify/llc$exe"
chmod 0755 "$root/verify/llc$exe"
"$root/verify/llc$exe" --version | head -n 5
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
sha256sum "$output/llc.gz" "$output/cjselfhost_llvmshim.o"
