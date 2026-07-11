# fbwriter：FlatBuffers 公共写 runtime

## 结论与范围

`FlatBufferBuilder` 已从 `cjcj::modules` 收敛到 `packages/flatbuffers/src/FlatBufferBuilder.cj`，与已共享的读 runtime 同属 `cjcj::flatbuffers`。modules、frontend、macro、CHIR 的既有写调用面均已切换到公共包；没有复制第二份 builder。

本轮按生产使用面移植 32-bit、non-size-prefixed 子集，不移植 64-bit-aware builder、mutation、native struct packing、release allocator 与 size-prefixed 输出。清点命令：

```text
rg -o 'builder\.[A-Za-z_][A-Za-z_0-9]*' src/Modules/ASTSerialization/ASTWriter.cpp | sort -u
rg -o 'builder\.[A-Za-z_][A-Za-z_0-9]*' src/CHIR/Serializer/CHIRSerializer.cpp | sort -u
```

ASTWriter/CHIRSerializer 的直接 runtime API 子集为：

- `CreateString`、`CreateSharedString`；
- `CreateVector<T>`（selfhost 按实际元素类型展开为 `CreateVectorOffsets/CreateVectorU8/CreateVectorU32/CreateVectorI32/CreateVectorBool/CreateVectorU64/CreateVectorOfStructs`）与 `CreateVectorOfStrings`；
- `Finish`（带/不带 4-byte identifier，均非 size-prefixed）；
- `GetBufferPointer`、`GetSize`。

flatc generated binding 所需底层子集为：

- `StartTable`、`AddOffset`、`AddStruct`、`EndTable`；
- `AddElement<T>` 的实际 scalar 实例：bool/u8/i8/u16/i16/u32/i32/u64/i64/f64；selfhost public 名为对应 `AddBool/AddU8/AddI8/.../AddFloat64`；
- offset 回填、little-endian scalar 写、alignment/padding、shared string pool、vtable 构造与默认去重。

## 逐符号 C++ 锚点

权威头：`/root/cj_build/cangjie_compiler/third_party/flatbuffers/include/flatbuffers/flatbuffer_builder.h`。

| selfhost 实体 | C++ signature / 关键体 | 锚点 |
|---|---|---|
| `FlatBufferBuilder.init/Clear/GetSize/GetBufferPointer` | `FlatBufferBuilderImpl(...)`; `void Clear()`; `SizeT GetSize() const`; `uint8_t *GetBufferPointer() const` | `flatbuffer_builder.h:95-112,168-180,208-211` |
| `CreateString` | `OffsetT<String> CreateString(const std::string &str)` → `CreateString(str.c_str(), str.length())` | `:530-563,1375-1385` |
| `CreateSharedString` | `Offset<String> CreateSharedString(const char*, size_t)`；lazy pool、先写、命中则 `buf_.pop(...)`、否则记录 offset | `:597-624` |
| `CreateVector*` scalar/offset | `OffsetT<VectorT<T>> CreateVector(const T*, size_t)`；`CreateVector(const Offset<T>*, size_t)` | `:727-761,785-800` |
| `CreateVectorBool` | `Offset<Vector<uint8_t>> CreateVector(const std::vector<bool>&)` | `:809-817` |
| `CreateVectorOfStrings` | `Offset<Vector<Offset<String>>> CreateVectorOfStrings(It, It)` | `:855-897` |
| `CreateVectorOfStructs` | `OffsetT<VectorT<const T *>> CreateVectorOfStructs(const T*, size_t)` | `:900-918` |
| `StartTable` | `uoffset_t StartTable()`，记录当前向下 buffer size | `:407-413` |
| `AddOffset` | `template<typename T> void AddOffset(voffset_t, Offset<T>)`，null 不写，否则 `ReferTo` 后 AddElement | `:343-346` |
| `AddBool/AddU8/AddI8/AddU16/AddI16/AddU32/AddI32/AddU64/AddI64/AddFloat64` | `template<typename T> void AddElement(voffset_t field, T e, T def)`，默认值省略，否则 `TrackField(field, PushElement(e))` | `:308-341` |
| `AddStruct` | `template<typename T> void AddStruct(voffset_t, const T*)` | `:353-358` |
| `EndTable/Slot/VTableEquals/PatchI32/AppendU16` | `uoffset_t EndTable(uoffset_t start)`：占位 soffset、生成 voffset 表、memcmp 去重、pop 新表、回填 soffset | `:415-483`；`base.h:441-444` |
| `StartVector` | `void StartVector(size_t len, size_t elemsize, size_t alignment)`，先 length 对齐、再 element 对齐 | `:676-684` |
| `Prep` | `Align/PreAlign` + `PaddingBytes` | `:285-291,514-520`；`base.h:458-461` |
| `PrependUOffset` | `PushElement(OffsetT<T>)` → `PushElement(ReferTo(off.o))`; `ReferTo` | `:317-321,364-390` |
| `Prepend*` scalar/raw | `PushElement<T>` + `EndianScalar/WriteScalar<T>` | `:308-315`；`base.h:416-422,441-444` |
| `PrependRawByte/PopBytes` | `vector_downward::push_small/pop` | `vector_downward.h:185-189,204-207` |
| `Finish` | `void Finish(Offset<T>, const char*)`; internal non-size-prefixed path `PreAlign`、identifier、root `ReferTo` | `flatbuffer_builder.h:1224-1229,1258-1282` |
| `CheckFinishState` | `NotNested()` + internal `Finish` 的 `!finished`/`clear_scratch` 前置约束 | `flatbuffer_builder.h:393-405,1258-1263` |

每个 production function 旁均有上述 file:line 注释；`GetBufferPointer` 以 `Array<UInt8>` 承载 C++ pointer+size，因为仓颉写文件 API 接收 byte array，不改变 wire bytes。

## 全分支与平台分支

已覆盖所移植子集的全部分支：

- `CreateSharedString`：2 个 `if`（lazy pool 创建、已有字符串复用）及复用时 pop early-return，来源 `flatbuffer_builder.h:606-623`；
- `AddElement/AddOffset`：默认值省略与 null offset 省略两个 early-return，来源 `:333-346`；
- `EndTable` 默认 dedup 路径：遍历历史 vtable、size/content mismatch continue、命中 pop+reuse、新表登记、soffset 回填，来源 `:453-481`；本任务未纳入未被生产调用的 `DedupVtables(false)` 配置 API；
- scalar `CreateVector`：空/非空及 little-/big-endian wire 写法均由显式 little-endian byte writer覆盖，来源 `:745-761`；
- `StartVector/Finish/GetBufferPointer`：nested object、重复 Finish、未 Finish 取 buffer 的 assert 分支均由同位置异常对位，来源 `:208-211,393-405,676-684,1258-1263`；
- `Finish`：生产使用的 identifier null/non-null 两支均覆盖；未纳入独立 API `FinishSizePrefixed`，来源 `:1224-1243,1258-1282`。

平台/条件分支机械清点原始输出：

```text
/root/cj_build/cangjie_compiler/third_party/flatbuffers/include/flatbuffers/flatbuffer_builder.h:566:  #ifdef FLATBUFFERS_HAS_STRING_VIEW
/root/cj_build/cangjie_compiler/third_party/flatbuffers/include/flatbuffers/flatbuffer_builder.h:626:#ifdef FLATBUFFERS_HAS_STRING_VIEW
```

这两处只是 C++ `string_view` 与 `const char*/std::string` overload 选择，两支最终都调用同一个 `CreateString(data,size)`/`CreateSharedString(data,size)`；仓颉 `String` 单一 overload 覆盖共同函数体。改动源无 `_WIN32/__APPLE__/__OHOS__/__linux__` 平台分支，因此无需 `@When`。

## Round-trip 与官方 byte 对照

测试 `packages/flatbuffers/src/FlatBufferBuilder_test.cj` 手工构造 3 类代表 table：

1. `Payload`：i64 payload（含正数 42 与负数 -7）；
2. `Item`：shared string、`vector<uint32>`、union tag + payload offset；构造两个实例；
3. `Root`：shared string 与 `vector<offset<Item>>`。

读回使用公共 `Table/Vector/FlatBufferString/ReadScalar`，逐字段断言 title/name、两个 vector 的 5 个元素、两个 union tag、两个 payload；另构造两个同布局空 table，断言 `GetVTable()` 返回相同地址，证明 vtable 实际共享。

官方对照程序为 `packages/flatbuffers/tests/official_wire_probe.cpp`，直接使用树内官方 `flatbuffers::FlatBufferBuilder` 构造同一对象图。原始输出末行：

```text
SIZE=192
```

其完整 192-byte 十进制序列固化为 selfhost test 的 `expected`；测试先执行 `bytes == expected`，再读回。因此 byte 对照是 192/192 相等，不是字段级近似。

定向测试原始输出：

```text
Summary: TOTAL: 1
    PASSED: 1, SKIPPED: 0, ERROR: 0
    FAILED: 0
cjpm test success
```

## 构建证据

按门策略未运行 `verify.sh` 全门；运行公共包、modules 与包含 macro/CHIR/frontend 全依赖闭包的 frontend build。各命令原始终行：

```text
cjpm build success
cjpm build success
cjpm build success
```

构建仅有当前树既有 unused/unreachable warnings，无新增 error。

## 交付自检

- 无任何 grep 不到 C++ 出处的新符号；round-trip 中的 `Payload/Item/Root` 是手工 schema 的测试 fixture，不进入 production API，测试入口对应官方 `third_party/flatbuffers/tests/test_builder.cpp:122-124` 的 `FlatBufferBuilderTest`。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代；本轮未撞到系统根或缺失 named 依赖。
- 已覆盖上列所移植 C++ API 子集的全部 branch/case/early-return；未声称移植整个 FlatBuffers 库。
