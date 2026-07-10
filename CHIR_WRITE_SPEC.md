# CHIR 二进制序列化写侧移植开工规格

## 1. 盘点边界与结论

本规格只盘点 C++ CHIR FlatBuffers 写路径，没有修改 `packages/`，也没有运行构建。基线为 `master`/`74d4fe37`。C++ 入口与实现分别是：

- `CHIRSerializer::Serialize`：`/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializer.cpp:31-38`
- 写侧状态：`/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializerImpl.h:34-97`
- 全部写函数：`/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializer.cpp:42-1557`
- 权威 schema：`/root/cj_build/cangjie_compiler/schema/PackageFormat.fbs:7-1249`
- flatc 生成写 API（构建产物，仅用于核对）：`/root/cj_build/cangjie_compiler/build/build/schema/flatbuffers/PackageFormat_generated.h:2767-8542`

结论：schema 的 **74 张 table 全部已有 selfhost 读侧 schema 对应物**，字段名、vtable slot、union tag 和 enum ordinal 都可复用；对应物是 74 个 `PackageFormat_* <: Table`（Core 32、Value 17、Expression 24、Package 1）。但这些都是只读 accessor/`Verify`，不是写 binding。二进制 writer 仍需 generated `Start/Add/End/Create/CreateDirect` 层和 CHIR 对象图遍历层。

现有 `packages/chir/src/CHIRSerializerImpl.cj` 是另一套文本格式 writer，不对应 `PackageFormat.fbs`，不能替代本清单中的二进制函数。

函数级依赖、预计行数和 `≤40` 标记见 [CHIR_WRITE_FUNCTIONS.tsv](CHIR_WRITE_FUNCTIONS.tsv)。该 TSV 枚举了 C++ 文件中的全部 89 个实现实体（含 2 个静态 helper、模板重载/特化和所有 overload；不把 `:306` 的前置声明重复计数）。

## 2. 文件头、版本、压缩与对齐

### 2.1 实际落盘头

schema 声明 `file_identifier "CHIR"`（`PackageFormat.fbs:9`），flatc 也生成了带 identifier 的 `FinishCHIRPackageBuffer`（`PackageFormat_generated.h:8509-8536`）。但是生产 writer 在 `CHIRSerializer.cpp:1523` 调用的是：

```cpp
builder.Finish(serializedPackage);
```

因此忠实输出是：

1. 非 size-prefixed FlatBuffer；
2. 开头只有 32-bit little-endian root table 相对偏移（以及 builder 为整体对齐可能插入的 padding）；
3. **不写四字节 `CHIR` identifier**；
4. **没有独立版本号/版本头**。兼容性只由 schema 和编译器版本约定承担；C++ reader 的报错文案提版本，但 verifier 调用也不带 identifier（`CHIRDeserializer.cpp:60-70`）。

不得改成 `Finish(root, "CHIR")`、`FinishCHIRPackageBuffer` 或 size-prefixed 变体，否则字节格式与 C++ writer 不同。

### 2.2 压缩与外层封装

没有压缩、校验和、分块或额外 envelope。`Save` 直接取 `GetBufferPointer/GetSize`，用 binary `ofstream` 原样写出（`CHIRSerializer.cpp:1523-1529`）。

### 2.3 FlatBuffers 对齐/布局约定

- 所有 scalar 按 FlatBuffers little-endian 写入；`PushElement` 先按 scalar 大小对齐再做 endian scalar 写入（`flatbuffer_builder.h:308-314`）。
- builder 向下构造 buffer；table 在 `StartTable/EndTable` 之间记录字段位置并生成 16-bit vtable slot（`flatbuffer_builder.h:407-483`）。默认值字段可完全省略，所以字段没有固定连续物理偏移；**schema 字段序号/vtable slot 才是稳定布局**。
- `EndTable` 默认进行相同 vtable 去重（`flatbuffer_builder.h:453-472`）。
- vector 先写元素再写 32-bit 长度；元素按自身 alignment 对齐。此 schema 最大 scalar alignment 为 8（`uint64/int64/double`）。
- `Finish` 按已观察到的最大 alignment 对齐整个 buffer，再写 32-bit root offset；本 writer 不写 identifier 和 size prefix（`flatbuffer_builder.h:1224-1229,1258-1282`）。
- schema 标为 `string(shared)` 的字段通过 generated `Create*Direct` 或显式 `CreateSharedString` 去重；`[string]` 的 `CreateVectorOfStrings` 不共享字符串（`flatbuffer_builder.h:597-624,855-892`）。
- pool ID 是 `uint32`，0 表示 invalid/null，合法 ID 从 1 开始（`PackageFormat.fbs:11-12`）。四个 union root pool 都用平行的 tag vector + offset vector，长度与索引必须一致。

## 3. 74 张 table：字段顺序、C++ 写点与 selfhost 读面

下表字段顺序就是 schema/vtable slot 顺序。union 字段会由 flatc 展开成相邻的 `<field>_type`、`<field>` 两个 slot；例如 `Base.annos` 和根表四个 pool。`已有`表示对应 read class 和全部字段 accessor/Verify 已落面，并非已有 write API。

| # | table（schema 行） | schema 字段顺序 | C++ 写点 | selfhost 读绑定 |
|---:|---|---|---|---|
| 1 | Type (`102-105`) | kind; argTys | `CHIRSerializer.cpp:333-338` | Core:4，已有 |
| 2 | RawArrayType (`107-110`) | base; dims | `:341-346` | Core:27，已有 |
| 3 | VArrayType (`112-115`) | base; size | `:349-354` | Core:50，已有 |
| 4 | FuncType (`117-121`) | base; isCFuncType=false; hasVarArg=false | `:357-363` | Core:73，已有 |
| 5 | CustomType (`123-126`) | base; customTypeDef | `:366-371` | Core:101，已有 |
| 6 | GenericType (`128-133`) | base; identifier(shared); srcCodeIdentifier(shared); upperBounds | `:374-382` | Core:124，已有 |
| 7 | Pos (`143-146`) | line; column | `:144-145`（DebugLocation 内） | Core:160，已有 |
| 8 | DebugLocation (`148-154`) | filePath(shared); fileId; beginPos; endPos; scope | `:141-149` | Core:182，已有 |
| 9 | LinkTypeInfo (`156-158`) | linkage | `:202-208`（Base annotation） | Core:223，已有 |
| 10 | SkipCheck (`167-169`) | skipKind | `:210-216` | Core:240，已有 |
| 11 | NeedCheckArrayBound (`171-173`) | need=true | `:178-184` | Core:257，已有 |
| 12 | NeedCheckCast (`175-177`) | need=true | `:186-192` | Core:274，已有 |
| 13 | NeverOverflowInfo (`187-189`) | neverOverflow=false | `:230-236` | Core:291，已有 |
| 14 | GeneratedFromForIn (`191-193`) | value=false | `:238-244` | Core:308，已有 |
| 15 | IsAutoEnvClass (`195-197`) | value=false | `:246-252` | Core:325，已有 |
| 16 | IsCapturedClassInCC (`199-201`) | value=false | `:254-260` | Core:342，已有 |
| 17 | EnumCaseIndex (`203-205`) | index=-1 | `:262-271` | Core:359，已有 |
| 18 | VirMethodOffset (`207-209`) | offset=-1 | `:273-282` | Core:376，已有 |
| 19 | WrappedRawMethod (`211-213`) | rawMethod | `:218-229` | Core:393，已有 |
| 20 | OverrideSrcFuncType (`215-217`) | type | `:284-289` | Core:410，已有 |
| 21 | Base (`235-239`) | annos_type; annos; loc; attributes | `:172-303` | Core:427，已有 |
| 22 | Value (`251-256`) | base; type; identifier(shared); kind | `:385-419` | Value:4，已有 |
| 23 | LiteralValue (`269-272`) | base; literalKind | `:531-536` | Value:38，已有 |
| 24 | BoolLiteral (`274-277`) | base; val | `:540-545` | Value:61，已有 |
| 25 | StringLiteral (`279-282`) | base; val(shared) | `:556-562` | Value:84，已有 |
| 26 | RuneLiteral (`284-287`) | base; val | `:548-553` | Value:108，已有 |
| 27 | IntLiteral (`289-292`) | base; val | `:565-570` | Value:131，已有 |
| 28 | FloatLiteral (`294-297`) | base; val=1.0 | `:573-578` | Value:154，已有 |
| 29 | UnitLiteral (`299-301`) | base | `:581-585` | Value:177，已有 |
| 30 | NullLiteral (`303-305`) | base | `:588-592` | Value:195，已有 |
| 31 | Parameter (`307-313`) | base; ownedFunc; ownedLambda; srcCodeIdentifier(shared); annoInfo | `:422-431` | Value:213，已有 |
| 32 | LocalVar (`315-320`) | base; associatedExpr; isRetVal=false; srcCodeIdentifier(shared) | `:434-441` | Value:253，已有 |
| 33 | GlobalValue (`322-330`) | base; srcCodeIdentifier(shared); rawMangledName(shared); packageName(shared); declaredParent; features; annoInfo | `:444-456` | Value:287，已有 |
| 34 | GlobalVar (`332-336`) | base; initializer | `:459-464` | Value:341，已有 |
| 35 | FuncSigInfo (`356-360`) | funcName(shared); funcType; genericTypeParams | `:830-835`；另见 `:503-510` | Value:364，已有 |
| 36 | Function (`362-378`) | base; genericDecl; funcKind; isFastNative; isCFFIWrapper; originalLambdaInfo; genericTypeParams; paramDftValHostFunc; body; params; retVal; propLoc; localId; blockId; blockGroupId | `:492-528` | Value:393，已有 |
| 37 | Block (`380-387`) | base; parentGroup; exprs; predecessors; isLandingPadBlock; exceptionCatchList | `:466-476` | Value:485，已有 |
| 38 | BlockGroup (`389-395`) | base; entryBlock; blocks; ownedFunc; ownedExpression | `:479-489` | Value:531，已有 |
| 39 | CustomAnnoInstance (`404-408`) | annoClassName(shared); argValues; loc | `:154-163`（AnnoInfo 内） | Core:463，已有 |
| 40 | AnnoInfo (`410-413`) | mangledName(shared); annoInstances | `:152-166` | Core:494，已有 |
| 41 | MemberVarInfo (`415-424`) | name(shared); rawMangledName(shared); type; attributes; loc; annoInfo; initializerFunc; outerDef | `:309-322` | Core:519，已有 |
| 42 | VirtualMethodInfo (`426-437`) | funcName(shared); sigType; methodGenericTypeParams; instance; attributes; originalType; parentType; returnType | `:1091-1108` | Core:575，已有 |
| 43 | VTableInType (`439-444`) | srcParentType; virtualMethods | `:1110-1120` | Core:629，已有 |
| 44 | CustomTypeDef (`446-462`) | base; kind; customTypeDefID; srcCodeIdentifier(shared); identifier(shared); packageName(shared); type; genericDecl; methods; implementedInterfaces; instanceMemberVars; staticMemberVars; annoInfo; vtable; instanceVarInitFunc | `:1123-1147` | Core:653，已有 |
| 45 | EnumCtorInfo (`464-469`) | srcCodeName(shared); mangledName(shared); funcType; annoInfo | `:325-329` | Core:752，已有；C++ 未传 annoInfo |
| 46 | EnumDef (`471-475`) | base; ctors; nonExhaustive | `:1150-1156` | Core:787，已有 |
| 47 | StructDef (`477-480`) | base; isCStruct=false | `:1159-1164` | Core:817，已有 |
| 48 | ExtendDef (`482-486`) | base; extendedType; genericParams | `:1182-1189` | Core:840，已有 |
| 49 | ClassDef (`488-494`) | base; isClass; isAnnotation; annotationTargets; superClass | `:1167-1179` | Core:869，已有 |
| 50 | Expression (`1030-1038`) | base; kind; operands; blockGroups; owner; resultLocalVar; resultTy | `:693-705` | Expression:4，已有 |
| 51 | UnaryExpressionBase (`1040-1043`) | base; overflowStrategy | `:708-723` | Expression:54，已有 |
| 52 | BinaryExpressionBase (`1045-1048`) | base; overflowStrategy | `:726-741` | Expression:77，已有 |
| 53 | AllocateBase (`1050-1053`) | base; allocatedType | `:744-758` | Expression:100，已有 |
| 54 | FuncCall (`1055-1059`) | base; instantiatedTypeArgs; objType | `:797-1041` 的 Apply/Invoke/Intrinsic 内层 | Expression:123，已有 |
| 55 | ApplyBase (`1061-1064`) | base; isSuperCall | `:797-827` | Expression:152，已有 |
| 56 | InvokeBase (`1066-1069`) | base; virMethodCtx | `:838-913` | Expression:175，已有 |
| 57 | IntrinsicBase (`1071-1074`) | base; intrinsicKind | `:1011-1041` | Expression:199，已有 |
| 58 | NumericCastBase (`1076-1079`) | base; overflowStrategy | `:916-930` | Expression:222，已有 |
| 59 | Branch (`1081-1084`) | base; sourceExpr | `:941-946` | Expression:245，已有 |
| 60 | MultiBranch (`1086-1089`) | base; caseValues | `:949-954` | Expression:268，已有 |
| 61 | GetElementRef (`1091-1094`) | base; path | `:761-767` | Expression:292，已有 |
| 62 | GetElementByName (`1096-1099`) | base; fieldNames | `:770-776` | Expression:316，已有 |
| 63 | StoreElementRef (`1101-1104`) | base; path | `:779-785` | Expression:341，已有 |
| 64 | StoreElementByName (`1106-1109`) | base; fieldNames | `:788-794` | Expression:365，已有 |
| 65 | InstanceOf (`1111-1114`) | base; targetType | `:933-938` | Expression:390，已有 |
| 66 | Field (`1116-1119`) | base; path | `:976-981` | Expression:413，已有 |
| 67 | FieldByName (`1121-1124`) | base; fieldNames | `:984-990` | Expression:437，已有 |
| 68 | RawArrayAllocateBase (`1126-1129`) | base; elementType | `:993-1008` | Expression:462，已有 |
| 69 | Debug (`1131-1134`) | base; srcCodeName(shared) | `:1044-1050` | Expression:485，已有 |
| 70 | SpawnBase (`1136-1139`) | base; executeClosure | `:1053-1067` | Expression:509，已有 |
| 71 | Lambda (`1141-1152`) | base; funcTy; isLocalFunc; identifier(shared); srcCodeName(shared); params; genericTypeParams; body; retVal; isCompileTimeValue=false | `:1070-1087` | Expression:532，已有 |
| 72 | GetInstantiateValue (`1154-1157`) | base; instantiateTypes | `:957-964` | Expression:599，已有 |
| 73 | GetRTTIStatic (`1159-1162`) | base; rttiType | `:967-973` | Expression:623，已有 |
| 74 | CHIRPackage (`1236-1247`) | name(shared); path(shared); pkgAccessLevel; types_type; types; values_type; values; exprs_type; exprs; defs_type; defs; packageInitFunc; phase; packageLiteralInitFunc | `:1514-1523` | Package:4，已有 |

绑定文件简称：`Core` = `packages/chir/src/CHIRFlatBufferBindingsCore.cj`，`Value`、`Expression`、`Package` 同理。字段 slot 常量集中于 `packages/chir/src/CHIRFlatBufferSchema.cj:868-1139`；共 234 个 `*_VT_*` 常量。

### 3.1 四个 union 与 tag 顺序

- `Annotation`：13 个 payload，schema `219-233`；C++ handler 注册/写 tag 见 `178-289`。`AnnoFactoryInfo` 明确不写；无 handler 的 annotation 直接 abort（`291-299`）。
- `TypeElem`：`Type, RawArrayType, VArrayType, FuncType, CustomType, GenericType`，schema `1164-1171`；C++ dispatch `1193-1243`。
- `CustomTypeDefElem`：`EnumDef, StructDef, ClassDef, ExtendDef`，schema `1173-1178`；C++ dispatch `1463-1482`。
- `ExpressionElem`：23 个 payload，schema `1180-1204`；C++ dispatch `1306-1461`。多个具体 ExprKind 共用一个 payload table。
- `ValueElem`：13 个 payload，schema `1206-1220`；literal dispatch `1245-1275` 与 value dispatch `1277-1304`。

tag 数组与 payload 数组的索引严格成对。selfhost 已有四类 vector verifier：Core `:921-1018`、Value `:570-610`、Expression `:651-698`，可作为写后结构约束的镜像。

## 4. C++ 写入/遍历顺序

### 4.1 初始编号

`Initialize`（`1532-1557`）按以下顺序种子化：

1. `package.GetGlobalVars()` 依次压入 `valueQueue`；
2. `package.GetGlobalFunctions()` 依次压入 `valueQueue`；
3. `package.GetAllCustomTypeDef()` 依次压入 `defQueue`；
4. 先为全部 def 预分配 1-based ID/tag/payload placeholder；
5. 再为全部初始 value 预分配 ID/tag/payload placeholder。

后续 `GetId` 首见某对象时同步分配 ID、扩展 tag/payload 平行数组并入队（`74-116`）。不能先序 DFS 直接输出，也不能按名称排序；ID 正是该发现顺序。

### 4.2 fixed-point dispatch

`Dispatch()`（`1484-1510`）外层一直循环到四个队列同时为空；每轮必须按：

1. type FIFO；
2. value deque FIFO；
3. expression FIFO；
4. def deque FIFO。

每个对象先写到其 `ID - 1` placeholder，因此序列化依赖新发现对象时仍保持稳定 pool 索引。全部队列清空后才读取 `packageInitFunc` 和 `packageLiteralInitFunc` 的 ID。

### 4.3 根表参数顺序

`CreateCHIRPackageDirect` 参数顺序（`1518-1521`）是：

`name, "", accessLevel, typeKind, allType, valueKind, allValue, exprKind, allExpression, defKind, allCustomTypeDef, packageInitFunc, phase, packageLiteralInitFunc`。

注意 path 被固定写成空串，不取 package path。生成的 `CreateCHIRPackage` 内部为了 FlatBuffers 构造和对齐以另一顺序 `Add*`（generated header `8098-8113`）；移植 generated binding 时应照 generated `Add*` 顺序，不能把 schema 参数顺序误解为物理 byte 顺序。

## 5. 写侧独有设施与差距

### 5.1 已存在、可直接依赖

- 74 张 read table 及其字段 accessor/Verify：四个 `CHIRFlatBufferBindings*.cj`。
- 全部 enum/union ordinal 与 234 个 vtable slot 常量：`CHIRFlatBufferSchema.cj`。
- read-side `Offset<T>`、`Vector<T>`、`Table`、little-endian scalar 和 verifier：`CHIRFlatBufferRuntime.cj:68-552`。
- 通用写 builder：`packages/modules/src/FlatBufferBuilder.cj:19-366`，且 chir 已依赖 modules（`packages/chir/cjpm.toml:16-20`）。它已有普通 string、offset/string/u32/bool/u64 vector、table、常用 scalar、带/不带 identifier 的 Finish。
- CHIR typed annotation map 已在当前基线（`Base`/`Annotation`），但 `LinkTypeInfo` 是 AGENTS.md 明列系统根，真正移植 `Serialize(Base)` 前必须单独确认其 selfhost API，而不能补偿模拟。

### 5.2 读侧没有照面的写设施

以下不是新 schema，而是 writer-only 状态机/API：

1. **generated write bindings（74 tables）**：每表 `Start/Add/End/Create/CreateDirect`，包括 union 平行 tag vector。读 binding 不能反向写。
2. **对象身份到 1-based ID 的四张 map**：C++ key 是 `Type*/Value*/Expression*/CustomTypeDef*` 裸指针身份（Impl.h `58-61`），不是结构相等、identifier 或 nodeId 的替代。按硬约束，这是实现 lane 的系统根；本盘点只记录，不提出平行实现。
3. **四队列 fixed-point 状态机**：type/expression 用 queue，value/def 用 deque；四个计数器、四个 tag vector、四个 payload placeholder vector（Impl.h `47-73`）。
4. **shared-string pool**：C++ `CreateSharedString` 会内容去重；modules builder 只有 `CreateString`，没有 shared-string cache。若要求字节级忠实，必须补上游同名语义，不能把普通 string 当作等价。
5. **vtable dedup**：C++ FlatBufferBuilder 默认去重相同 vtable；modules builder 的 `EndTable` 当前总是写新 vtable。语义可读不等于字节忠实。
6. **缺失 scalar/vector writer API**：modules builder 没有 `CreateVectorU8`（union tag）、`CreateVectorI32`（DebugLocation.scope）、`AddU64`（attributes/localId/blockId/blockGroupId/uint64 payload）、`AddI16`（Linkage）和 `AddFloat64`（FloatLiteral）。这些应以既有 `FlatBufferBuilder` named 设施补齐，不应在 chir 内自建 helper。
7. **空 vector/null 的精确选择**：C++ 有的调用传 `nullptr`（省略 field），有的无条件传 `&vector`（存在但长度 0）。逐函数差异已写入 TSV，不能统一“空即省略”。
8. **annotation handler 状态机**：13 个 union handler、bodyless `WrappedRawMethod` 忽略、`AnnoFactoryInfo` 忽略、未知 annotation abort、两个 optional index 的 `-1` sentinel。
9. **binary file sink**：需要与 `ofstream(binary)` 等价的整段 byte 写文件 API；read-side 只有读取入口。

### 5.3 已发现的上游特殊行为（必须照抄，不“修正”）

- `EnumCtorInfo` schema 有 `annoInfo`，但 writer `:327-328` 只传前三个业务参数，故该 field 缺省为空。
- `ApplyWithException` 的 `isSuperCall` 强制 false（`:825-826`）。
- Intrinsic 的 `FuncCall.objType` 强制 0（`:1017-1019,1034-1036`）。
- `Debug.srcCodeName` 实际取 `GetSrcCodeIdentifier()`（`:1047-1049`）。
- `Function.genericDecl` 仅在 generic decl 有 body 时写；body/retVal 也仅对有 body 的函数写（`:496-522`）。
- `ClassDef.annotationTargets` 仅 annotation class 创建 vector；否则为 null（`:1170-1178`）。
- `StoreElementRef` 无条件传 `&path`，而 `GetElementRef/Field` 对 empty path 传 null。
- `ConstantValueKind::KIND_FUNC` dispatch 返回空 offset，既不写 literal tag 也不 abort（`:1269-1270`）。

## 6. 按依赖拓扑的开工包

### Lane 0：先决系统根（不可由 CHIR lane 代偿）

1. 确认/提供 `Type/Value/Expression/CustomTypeDef` 的对象身份 key；C++ 锚：Impl.h `58-61`、GetId `74-116`。这是 hard blocker。
2. 确认 selfhost `LinkTypeInfo` 完整 API；C++ 锚：`Serialize(Base)` `202-208`。这是 hard blocker。

### Lane 1：补齐既有 FlatBufferBuilder named 设施

在 `packages/modules/src/FlatBufferBuilder.cj` 上游设施内补 shared string、vtable dedup、U8/I32 vectors、U64/I16/Float64 table scalar。具体 C++/FlatBuffers 锚见本规格 2.3 和 5.2。不要在 chir 内复制简版 builder。此 lane 是跨 package 依赖，按任务约束本次未修改。

### Lane 2：生成/移植 74 张 write bindings

以 `PackageFormat.fbs` 字段 slot 和 generated header `2767-8158` 为唯一来源。建议仍按现有四文件域拆分 Core/Value/Expression/Package；read class、slot 常量和 enum tag 直接复用。每个小 `Start/Add/End/Create` 通常 `≤40`，但 74 张表应作为机械生成的一致批次，不宜手工漏字段。

### Lane 3：ID/state 与 leaf serializer

先实现 Impl.h `44-96` 状态，再按 TSV topo `010-075`：GetId → generic vector helpers → Debug/Anno/Base → Type → Value → Literal。除 `Serialize(Base)` 外均预计 `≤40`。

### Lane 4：expression 与 def serializer

按 TSV topo `080-126`。先 `ToPackageExprKind` 和公共 `Expression/FuncCall/FuncSigInfo`，再 leaf expression；def 侧先 `VirtualMethodInfo/VTable`，再 `CustomTypeDef` 与四个具体 def。`ToPackageExprKind` 超 40，其余均 ≤40。

### Lane 5：dispatch、fixed point、root/save

按 TSV `130-141`：四类 typed dispatch → fixed-point `Dispatch()` → `Save` → public `Serialize`。Expression dispatch（156 行）和 Type dispatch（51 行）必须单独完整移植，不能按当前测试触发裁剪。

## 7. 覆盖性机械账

- schema table：`rg '^table ' PackageFormat.fbs` = 74；selfhost `rg '^class PackageFormat_.* <: Table' CHIRFlatBufferBindings*.cj` = 74。
- selfhost vtable slot 常量：`rg '^const CHIRFB_.*_VT_' CHIRFlatBufferSchema.cj` = 234。
- 平台分支：对 `CHIRSerializer.cpp`、`CHIRSerializerImpl.h`、`PackageFormat.fbs` 搜 `_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif` 无输出；写侧没有平台条件分支需要映射。
- 函数：TSV 覆盖 `CHIRSerializer.cpp:31-1557` 的全部定义；`:306` 只是 `Serialize(Expression)` 前置声明，定义在 `:693`。
- 未运行任何构建或 gate（任务明确“零构建”）。

盘点声明：无任何 grep 不到 C++/schema 出处的新编译器符号；未改业务源码绕过、未加 band-aid 吞 bug；盘点中识别出的 pointer identity 与 LinkTypeInfo 系统根已明确列为开工 blocker，未自行替代。
