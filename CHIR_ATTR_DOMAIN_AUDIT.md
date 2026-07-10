# L11 — CHIR Attribute runtime 扩展域审计

## 结论

审计基线为 selfhost `5b9ccacd` 与本机 C++ 源树 `/root/cj_build/cangjie_compiler`。C++ `CHIR::Attribute` 有 38 个终点属性，连续占用 `0..37`，`ATTR_END` 的值为 38；selfhost 有 42 项。共同的 38 项名称、顺序和显式序号全部一致，没有少项或序号错位。selfhost 多出四项：`FAST_NATIVE=71`、`NO_HEAP_ALLOC=76`、`NO_WRITE_BARRIER_REC=77`、`NO_STACK_GROW=78`。

裁决如下：

1. `FAST_NATIVE` 应迁出 `Attribute`，回到 C++ 已有的 `Function::isFastNative` 专字段通道。它在 C++ 从来不是 `CHIR::Attribute`。
2. `NO_HEAP_ALLOC`、`NO_WRITE_BARRIER_REC`、`NO_STACK_GROW` 在所审 C++ 树内没有同名注解、字段、CHIR 属性或 checker，不能声称可迁移到一个现存 C++ 通道；保留为明确的 selfhost runtime-spec 扩展。
3. 扩展 wire ID `76..78` 必须冻结，不能压紧到 `38..40`，也不能复用。它们只能作为 selfhost 文本 CHIR wire 扩展；C++ FlatBuffer `attributes:uint64` 和 `AttributeInfo::bitset<64>` 无法承载位 76..78。
4. `FAST_NATIVE=71` 在迁移时也不能直接改号或静默删除：先为 selfhost 文本 function record 增加/保留独立布尔字段，过渡 reader 可继续接受旧 wire 的 71，writer 再停止把 71 写进属性列表。

逐项机械清单见 `CHIR_ATTR_DOMAIN_AUDIT.tsv`。

## 1. 终点全集与序号

### C++ 终点

`include/cangjie/CHIR/IR/AttributeInfo.h:16-71` 定义 `enum class Attribute`。真实属性从 `STATIC` 到 `PREVIOUSLY_DESERIALIZED` 共 38 项；`ATTR_END` 是哨兵，不是属性。`AttributeInfo.h:92` 固定 `ATTR_SIZE = 64`，`AttributeInfo.h:104-116` 直接用枚举值索引 `std::bitset<64>`。

### selfhost 终点

`packages/chir/src/Enums.cj:104-116` 定义 42 项，`Enums.cj:118-162` 显式给出序号。共同域为：

```text
0 STATIC                         19 INTERNAL
1 PUBLIC                         20 COMPILER_ADD
2 PRIVATE                        21 NO_REFLECT_INFO
3 PROTECTED                      22 NO_INLINE
4 ABSTRACT                       23 NON_RECOMPILE
5 VIRTUAL                        24 UNREACHABLE
6 OVERRIDE                       25 NO_SIDE_EFFECT
7 REDEF                          26 COMMON
8 SEALED                         27 SPECIFIC
9 FOREIGN                        28 SKIP_ANALYSIS
10 MUT                           29 DESERIALIZED
11 FINAL                         30 INITIALIZER
12 OPERATOR                      31 UNSAFE
13 READONLY                      32 JAVA_MIRROR
14 CONST                         33 JAVA_IMPL
15 IMPORTED                      34 OBJ_C_MIRROR
16 GENERIC_INSTANTIATED          35 HAS_INITED_FIELD
17 NO_DEBUG_INFO                 36 JAVA_HAS_DEFAULT
18 GENERIC                       37 PREVIOUSLY_DESERIALIZED
```

差集只有：

```text
71 FAST_NATIVE
76 NO_HEAP_ALLOC
77 NO_WRITE_BARRIER_REC
78 NO_STACK_GROW
```

selfhost `AttributeInfo.cj:4-35` 用两个 `UInt64` 字组成 128 位属性容器，因此稀疏位不会在 selfhost 内越界；这同时是与 C++ 64 位容器的 ABI 边界。

### wire 事实

- C++ `schema/PackageFormat.fbs:238,419,433` 的属性字段均为 `uint64`；`CHIRSerializer.cpp:300-302` 把 `GetRawAttrs().to_ulong()` 写入 wire，`CHIRDeserializer.cpp:1338-1342` 从单个 64 位字段恢复。
- selfhost 文本 wire 在 `CHIRSerializationFormat.cj:183-203` 把 `AttributeIndex` 作为十进制列表写入并读回；`CHIRSerializationFormat.cj:280-322,326-370` 明确包含 71、76、77、78。
- 因而共同的 `0..37` 可逐位对齐；`71,76,77,78` 不是 C++ FlatBuffer attribute ABI 的合法可表达域。文本格式能表达这些数字，不等于 C++ 二进制 wire 能表达。

## 2. 四项 producer / consumer 链

### FAST_NATIVE（建议迁移）

selfhost 源链并未闭合：

```text
@FastNative
  -> packages/parse/src/ParseDecl.cj:539-540 写 Ast FuncDecl.isFastNative
  -> [当前 FaithfulAST2CHIR 中没有 SetFastNative/isFastNative 的调用]
  -> Attribute.FAST_NATIVE 只能由文本 CHIR 属性反序列化或外部显式 SetFastNative 进入
  -> packages/chir/src/Value.cj:1136-1138 以 Attribute bit 71 实现 Is/SetFastNative
  -> packages/codegen/src/CGFunction.cj:235-239
  -> LLVM function attribute "gc-leaf-function"
```

这里的“没有调用”由全树 `rg -n "SetFastNative\\(" packages/chir/src` 得到：输出只有 `Value.cj:1137` 的方法定义，没有 AST→CHIR 调用点。因此 bit 71 不仅越出 C++ 属性域，还没有忠实复现 C++ producer。

C++ 的完整同语义通道是专字段：

```text
src/Parse/ParseDecl.cpp:877-878              FuncDecl::isFastNative = true
src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:662    chirFunc.SetFastNative(astFunc.isFastNative)
include/cangjie/CHIR/IR/Value/Value.h:544-545,701
src/CHIR/IR/Value/Value.cpp:1125-1132        Function::Is/SetFastNative
src/CHIR/Serializer/CHIRSerializer.cpp:524-527
src/CHIR/Serializer/CHIRDeserializer.cpp:641-645
src/CodeGen/CGFunction.cpp:164-171            emit FAST_NATIVE_ATTR
src/CodeGen/Utils/Constants.h:29-31           "gc-leaf-function"
```

这条通道把 `isFastNative` 作为 Function FlatBuffer 独立布尔值序列化，而不是放进 `Base.attributes`。因此迁移目标是 named C++ 设施 `Function::isFastNative`，不是另造一种属性。

wire 影响：当前 selfhost 文本 function record `CHIRSerializerImpl.cj:205-234` 只有通用属性列表承载 FastNative，没有独立 FastNative 布尔字段。迁移必须版本化或做兼容读取；直接删除 71 会让旧文本 CHIR 丢语义。

### NO_HEAP_ALLOC（建议保留扩展）

```text
@NoHeapAlloc
  -> ParserImpl.cj:583 解析为 AnnotationKind.NO_HEAP_ALLOC
  -> FaithfulAST2CHIR.cj:4272-4279 写 Function Attribute bit 76
  -> RuntimeConstraintCheck.cj:19-41 建立带约束 root 的静态调用闭包
  -> frontend/CodeGenBridge.cj:455-460 把 checker 注入 CodeGen
  -> codegen/IRBuilder.cj:441-450 及 2044,2055,4524,4607,4646 的分配发射点消费
  -> 违规时发出 chir_annotation_not_applicable
```

当前 C++ `include/` 与 `src/` 对 `NoHeapAlloc|NO_HEAP_ALLOC` 零命中，不存在可迁移的 C++ producer、CHIR 字段或 consumer。保留 bit 76 是 selfhost runtime-spec 的内部契约，但不能写入/假装兼容 C++ 64 位属性 ABI。

### NO_WRITE_BARRIER_REC（建议保留扩展）

```text
@NoWriteBarrierRec
  -> ParserImpl.cj:584 解析为 AnnotationKind.NO_WRITE_BARRIER_REC
  -> FaithfulAST2CHIR.cj:4276-4278 写 Function Attribute bit 77
  -> RuntimeConstraintCheck.cj:118-142 建立带约束 root 的静态调用闭包
  -> frontend/CodeGenBridge.cj:457-460 把 checker 注入 CodeGen
  -> codegen/IRBuilder.cj:452-460 及 2873,2884,2892,2949,2959,3059,3075；ArrayImpl.cj:644 的写屏障发射点消费
  -> 违规时发出 chir_annotation_not_applicable
```

当前 C++ `include/` 与 `src/` 对 `NoWriteBarrierRec|NO_WRITE_BARRIER_REC` 零命中。C++ CodeGen 本身会生成写屏障，但没有这一“递归静态调用闭包禁止写屏障”的声明/检查通道；不能把普通 write-barrier emission 误报为对应 consumer。

### NO_STACK_GROW（建议保留扩展）

```text
@NoStackGrow
  -> ParserImpl.cj:585 解析为 AnnotationKind.NO_STACK_GROW
  -> FaithfulAST2CHIR.cj:4279 写 Function Attribute bit 78
  -> codegen/CGFunction.cj:241-243
  -> NO_STACK_GROW_ATTR
  -> "gc-leaf-function"
```

当前 C++ 对 `NoStackGrow|NO_STACK_GROW` 零命中；没有注解或 CHIR carrier。C++ 唯一相同的后端通道是 FastNative 最终写出的 `FAST_NATIVE_ATTR="gc-leaf-function"`（`CGFunction.cpp:164-168`、`Constants.h:29-31`）。这只能证明 LLVM consumer 相同，不能把 `NO_STACK_GROW` 迁成 `FAST_NATIVE`：二者前端契约不同，合并会丢失注解身份，也会把 FastNative 的其他语义与 runtime-spec 约束混为一谈。

LLVM IR 的字符串属性不改变 C/C++ 调用 ABI，但它改变 LLVM fork 的 stack-check 插入行为，属于 runtime codegen contract。bit 78 仍然不兼容 C++ CHIR 的 64 位 attributes wire。

## 3. 迁移与兼容顺序建议

本任务不改代码。后续若执行裁决，安全顺序是：

1. 为 selfhost `Function` 恢复 C++ `isFastNative` 同结构字段及 AST→CHIR 写入；文本 function wire 增加独立、版本化的布尔字段。
2. reader 同时接受新布尔字段与旧属性 71，并在内存中归一到专字段；writer 只写新字段。确认所有旧制品过渡完成后，从 `Attribute`/`CHIRKnownAttributes` 移除 `FAST_NATIVE`，但永久保留 71 为 retired wire ID，不复用。
3. 保留 76..78 及其 producer/consumer，不压号；在格式说明中标记为 selfhost text extension。若未来需要与 C++ `.chir` FlatBuffer 互通，必须先由共同 schema 增加 named Function 字段或扩展向量，不能截断到 `uint64`，也不能借用 0..63 的空洞位假装兼容。

## 4. 机械核验原始输出

枚举提取计数：

```text
CXX_COUNT=38
SELFHOST_COUNT=42
```

扩展名在 C++ 树的精确检索：

```text
$ rg -n "NoHeapAlloc|NO_HEAP_ALLOC|NoWriteBarrierRec|NO_WRITE_BARRIER_REC|NoStackGrow|NO_STACK_GROW" /root/cj_build/cangjie_compiler/include /root/cj_build/cangjie_compiler/src --glob '*.{h,cpp}'
<no output; exit 1>
```

所引用 C++ 源的平台条件检索：

```text
/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:880:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/CodeGen/CGFunction.cpp:149:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/CodeGen/CGFunction.cpp:199:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/CodeGen/CGFunction.cpp:219:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

这些是 backend feature guard，不是 `_WIN32/__APPLE__/__OHOS__/__linux__` 平台分支；审计对象没有 OS 分支需要映射。本任务按要求为 chore 零构建，未运行编译、bcgate 或 self-compile gate。

## 5. 交付自检

- 本次只新增审计文档与 TSV，没有新增/修改任何编译器函数、helper、类型、字段、分支或业务源码；逐符号 C++ 贴源要求不适用于代码 diff，文中已对每个裁决引用 named C++ 实体和 file:line。
- 本次不是函数移植，没有 branch/case/early-return 覆盖计数；属性终点全集已覆盖 C++ 全部 38 项与 selfhost 全部 42 项。
- 无任何 grep 不到 C++ 出处的新代码符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 未撞到并替代任何系统根；C++ 不存在的三项 runtime 扩展已明确裁决为保留扩展，没有伪造 C++ 通道。
