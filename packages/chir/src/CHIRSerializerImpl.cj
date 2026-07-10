package cjcj::chir

import std.collection.*
import std.reflect.TypeInfo
import cjcj::basic.Linkage as BasicLinkage
import cjcj::basic.LinkageToInt
import cjcj::modules.{FlatBufferBuilder, FlatBufferOffset}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

class CHIRSerializerImpl {
    private let builder: FlatBufferBuilder = FlatBufferBuilder()
    private let valueQueue: ArrayList<Value> = ArrayList<Value>()
    private let typeQueue: ArrayList<Type> = ArrayList<Type>()
    private let exprQueue: ArrayList<Expression> = ArrayList<Expression>()
    private let defQueue: ArrayList<CustomTypeDef> = ArrayList<CustomTypeDef>()

    private var typeCount: UInt32 = 0u32
    private var valueCount: UInt32 = 0u32
    private var exprCount: UInt32 = 0u32
    private var defCount: UInt32 = 0u32

    private let type2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let value2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let expr2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()
    private let def2Id: HashMap<Int64, UInt32> = HashMap<Int64, UInt32>()

    private let typeKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let valueKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let exprKind: ArrayList<UInt8> = ArrayList<UInt8>()
    private let defKind: ArrayList<UInt8> = ArrayList<UInt8>()

    private let allType: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allValue: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allExpression: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()
    private let allCustomTypeDef: ArrayList<FlatBufferOffset> = ArrayList<FlatBufferOffset>()

    private let serializedBlockGroups: HashSet<Int64> = HashSet<Int64>()
    private let serializedLiteralValues: HashSet<Int64> = HashSet<Int64>()

    public init() {}

    private func GetId(obj: Value): UInt32 {
        if (!value2Id.contains(obj.nodeId)) {
            valueCount++
            value2Id[obj.nodeId] = valueCount
            allValue.add(0u32)
            valueKind.add(0u8)
            valueQueue.add(obj)
        }
        return value2Id[obj.nodeId]
    }

    private func GetId(obj: Type): UInt32 {
        if (!type2Id.contains(obj.objectId)) {
            typeCount++
            type2Id[obj.objectId] = typeCount
            allType.add(0u32)
            typeKind.add(0u8)
            typeQueue.add(obj)
        }
        return type2Id[obj.objectId]
    }

    private func GetId(obj: Expression): UInt32 {
        if (!expr2Id.contains(obj.nodeId)) {
            exprCount++
            expr2Id[obj.nodeId] = exprCount
            allExpression.add(0u32)
            exprKind.add(0u8)
            exprQueue.add(obj)
        }
        return expr2Id[obj.nodeId]
    }

    private func GetId(obj: CustomTypeDef): UInt32 {
        if (!def2Id.contains(obj.nodeId)) {
            defCount++
            def2Id[obj.nodeId] = defCount
            allCustomTypeDef.add(0u32)
            defKind.add(0u8)
            defQueue.add(obj)
        }
        return def2Id[obj.nodeId]
    }

    private func GetId(obj: Option<Value>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<Type>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<Expression>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(obj: Option<CustomTypeDef>): UInt32 {
        return if (let Some(value) <- obj) { GetId(value) } else { 0u32 }
    }

    private func GetId(objs: ArrayList<Type>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<Value>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<Expression>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: ArrayList<CustomTypeDef>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func GetId(objs: HashSet<Value>): ArrayList<UInt32> {
        let indices = ArrayList<UInt32>()
        for (obj in objs) { indices.add(GetId(obj)) }
        return indices
    }

    private func Serialize(obj: DebugLocation): FlatBufferOffset {
        let beginPos = CreatePos(builder, obj.GetBeginPos().line, obj.GetBeginPos().column)
        let endPos = CreatePos(builder, obj.GetEndPos().line, obj.GetEndPos().column)
        let scope = obj.GetScopeInfo()
        return CreateDebugLocationDirect(
            builder, Some(obj.GetAbsPath()), obj.GetFileID(), beginPos, endPos, Some(scope))
    }

    private func Serialize(obj: AnnoInfo): FlatBufferOffset {
        let instances = ArrayList<FlatBufferOffset>()
        for (instance in obj.GetCustomAnnoInstances()) {
            let argStrings = ArrayList<FlatBufferOffset>()
            for (arg in instance.GetArgValues()) {
                argStrings.add(builder.CreateSharedString(arg))
            }
            let location = Serialize(instance.GetDebugLocation())
            instances.add(CreateCustomAnnoInstanceDirect(builder, Some(instance.GetAnnoClassName()),
                if (argStrings.isEmpty()) { None } else { Some(argStrings) }, location))
        }
        return CreateAnnoInfoDirect(builder, Some(obj.GetAnnoFactoryFuncMangledName()),
            if (instances.isEmpty()) { None } else { Some(instances) })
    }

    private func Serialize(obj: Base): FlatBufferOffset {
        let annoTypes = ArrayList<UInt8>()
        let annos = ArrayList<FlatBufferOffset>()
        for ((annotationType, annotation) in obj.GetAnno().GetAnnos()) {
            if (annotationType == TypeInfo.of<NeedCheckArrayBound>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEED_CHECK_ARRAY_BOUND)
                let value = NeedCheckArrayBound.Extract(
                    (annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeedCheckArrayBound(builder, value))
            } else if (annotationType == TypeInfo.of<NeedCheckCast>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEED_CHECK_CAST)
                let value = NeedCheckCast.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeedCheckCast(builder, value))
            } else if (annotationType == TypeInfo.of<DebugLocationInfoForWarning>()) {
                annoTypes.add(CHIRFB_ANNOTATION_DEBUG_LOCATION_INFO_FOR_WARNING)
                let location = DebugLocationInfoForWarning.Extract(
                    (annotation as Annotation<DebugLocation>).getOrThrow())
                annos.add(Serialize(location))
            } else if (annotationType == TypeInfo.of<LinkTypeInfo>()) {
                annoTypes.add(CHIRFB_ANNOTATION_LINK_TYPE_INFO)
                let linkage = LinkTypeInfo.Extract(
                    (annotation as Annotation<BasicLinkage>).getOrThrow())
                annos.add(CreateLinkTypeInfo(builder, Int16(LinkageToInt(linkage))))
            } else if (annotationType == TypeInfo.of<SkipCheck>()) {
                annoTypes.add(CHIRFB_ANNOTATION_SKIP_CHECK)
                let skipKind = SkipCheck.Extract((annotation as Annotation<SkipKind>).getOrThrow())
                annos.add(CreateSkipCheck(builder, UInt8(SkipKindIndex(skipKind))))
            } else if (annotationType == TypeInfo.of<WrappedRawMethod>()) {
                let rawMethod = WrappedRawMethod.Extract(
                    (annotation as Annotation<Option<Function>>).getOrThrow())
                if (let Some(method) <- rawMethod) {
                    if (method.GetBody().isNone()) { continue }
                }
                annoTypes.add(CHIRFB_ANNOTATION_WRAPPED_RAW_METHOD)
                let rawMethodId = if (let Some(method) <- rawMethod) {
                    GetId((method as Value).getOrThrow())
                } else {
                    0u32
                }
                annos.add(CreateWrappedRawMethod(builder, rawMethodId))
            } else if (annotationType == TypeInfo.of<NeverOverflowInfo>()) {
                annoTypes.add(CHIRFB_ANNOTATION_NEVER_OVERFLOW_INFO)
                let value = NeverOverflowInfo.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateNeverOverflowInfo(builder, value))
            } else if (annotationType == TypeInfo.of<GeneratedFromForIn>()) {
                annoTypes.add(CHIRFB_ANNOTATION_GENERATED_FROM_FOR_IN)
                let value = GeneratedFromForIn.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateGeneratedFromForIn(builder, value))
            } else if (annotationType == TypeInfo.of<IsAutoEnvClass>()) {
                annoTypes.add(CHIRFB_ANNOTATION_IS_AUTO_ENV_CLASS)
                let value = IsAutoEnvClass.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateIsAutoEnvClass(builder, value))
            } else if (annotationType == TypeInfo.of<IsCapturedClassInCC>()) {
                annoTypes.add(CHIRFB_ANNOTATION_IS_CAPTURED_CLASS_IN_CC)
                let value = IsCapturedClassInCC.Extract((annotation as Annotation<Bool>).getOrThrow())
                annos.add(CreateIsCapturedClassInCC(builder, value))
            } else if (annotationType == TypeInfo.of<EnumCaseIndex>()) {
                annoTypes.add(CHIRFB_ANNOTATION_ENUM_CASE_INDEX)
                let index = EnumCaseIndex.Extract(
                    (annotation as Annotation<Option<Int64>>).getOrThrow())
                annos.add(CreateEnumCaseIndex(builder, if (let Some(value) <- index) { value } else { -1 }))
            } else if (annotationType == TypeInfo.of<VirMethodOffset>()) {
                annoTypes.add(CHIRFB_ANNOTATION_VIR_METHOD_OFFSET)
                let offset = VirMethodOffset.Extract(
                    (annotation as Annotation<Option<Int64>>).getOrThrow())
                annos.add(CreateVirMethodOffset(builder, if (let Some(value) <- offset) { value } else { -1 }))
            } else if (annotationType == TypeInfo.of<OverrideSrcFuncType>()) {
                annoTypes.add(CHIRFB_ANNOTATION_OVERRIDE_SRC_FUNC_TYPE)
                let funcType = OverrideSrcFuncType.Extract(
                    (annotation as Annotation<Option<FuncType>>).getOrThrow())
                let typeId = if (let Some(value) <- funcType) {
                    GetId((value as Type).getOrThrow())
                } else {
                    0u32
                }
                annos.add(CreateOverrideSrcFuncType(builder, typeId))
            } else if (annotationType == TypeInfo.of<AnnoFactoryInfo>()) {
                continue
            } else {
                CJC_ABORT()
            }
        }
        let location = Serialize(GetDebugLocation(obj))
        return CreateBaseDirect(builder, Some(annoTypes), Some(annos), location, obj.GetAttributeInfo().GetRawAttrs())
    }

    private func Serialize(obj: MemberVarInfo): FlatBufferOffset {
        let initializerFunc = if (let Some(value) <- obj.initializerFunc) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let outerDef = if (let Some(value) <- obj.outerDef) { GetId(value) } else { 0u32 }
        return CreateMemberVarInfoDirect(builder, Some(obj.name), Some(obj.rawMangledName), GetId(obj.ty),
            obj.attributeInfo.GetRawAttrs(), Serialize(obj.loc), Serialize(obj.annoInfo), initializerFunc, outerDef)
    }

    private func Serialize(obj: EnumCtorInfo): FlatBufferOffset {
        let funcType = if (let Some(value) <- obj.funcType) {
            GetId((value as Type).getOrThrow())
        } else {
            0u32
        }
        return CreateEnumCtorInfoDirect(builder, Some(obj.name), Some(obj.mangledName), funcType, 0u32)
    }

    private func Serialize(obj: Type): FlatBufferOffset {
        let kind = UInt8(TypeKindIndex(obj.GetTypeKind()))
        let argTys = GetId(obj.GetTypeArgs())
        return CreateTypeDirect(builder, kind, if (argTys.isEmpty()) { None } else { Some(argTys) })
    }

    private func Serialize(obj: RawArrayType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateRawArrayType(builder, base, UInt32(obj.GetDims()))
    }

    private func Serialize(obj: VArrayType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateVArrayType(builder, base, Int64(obj.GetSize()))
    }

    private func Serialize(obj: FuncType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateFuncType(builder, base, obj.IsCFunc(), obj.HasVarArg())
    }

    private func Serialize(obj: CustomType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        return CreateCustomType(builder, base, GetId(obj.GetCustomTypeDef()))
    }

    private func Serialize(obj: GenericType): FlatBufferOffset {
        let base = Serialize((obj as Type).getOrThrow())
        let upperBounds = GetId(obj.GetUpperBounds())
        return CreateGenericTypeDirect(builder, base, Some(obj.GetIdentifier()), Some(obj.GetSrcCodeIdentifier()),
            if (upperBounds.isEmpty()) { None } else { Some(upperBounds) })
    }

    private func Serialize(obj: Value): FlatBufferOffset {
        let base = Serialize((obj as Base).getOrThrow())
        let kind = match (obj.GetValueKind()) {
            case ValueKind.KIND_LITERAL => 0u8
            case ValueKind.KIND_GLOBALVAR => 1u8
            case ValueKind.KIND_PARAMETER => 2u8
            case ValueKind.KIND_LOCALVAR => 3u8
            case ValueKind.KIND_FUNC => 4u8
            case ValueKind.KIND_BLOCK => 5u8
            case ValueKind.KIND_BLOCK_GROUP => 6u8
        }
        return CreateValueDirect(builder, base, GetId(obj.GetType()), Some(obj.GetIdentifier()), kind)
    }

    private func Serialize(obj: Parameter): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let ownedFunc = if (let Some(value) <- obj.GetOwnerFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let ownedLambda = if (let Some(value) <- obj.GetOwnerLambda()) {
            GetId((value as Expression).getOrThrow())
        } else {
            0u32
        }
        return CreateParameterDirect(builder, base, ownedFunc, ownedLambda,
            Some(obj.GetSrcCodeIdentifier()), Serialize(obj.GetAnnoInfo()))
    }

    private func Serialize(obj: LocalVar): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        return CreateLocalVarDirect(builder, base, GetId(obj.GetExpr()), obj.IsRetValue(),
            Some(obj.GetSrcCodeIdentifier()))
    }

    private func Serialize(obj: GlobalValue): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let declaredParent = GetId(obj.GetParentCustomTypeDef())
        let features = ArrayList<FlatBufferOffset>()
        for (name in obj.GetFeatures()) {
            features.add(builder.CreateSharedString(name))
        }
        return CreateGlobalValueDirect(builder, base, Some(obj.GetSrcCodeIdentifier()),
            Some(obj.GetRawMangledName()), Some(obj.GetPackageName()), declaredParent,
            if (features.isEmpty()) { None } else { Some(features) }, Serialize(obj.GetAnnoInfo()))
    }

    private func Serialize(obj: GlobalVar): FlatBufferOffset {
        let base = Serialize((obj as GlobalValue).getOrThrow())
        return CreateGlobalVar(builder, base, GetId(obj.GetInitializerValue()))
    }

    private func Serialize(obj: Block): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        let parentGroup = if (let Some(value) <- obj.GetParentBlockGroup()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let exprs = GetId(obj.GetExpressions())
        let predecessors = ArrayList<UInt32>()
        for (predecessor in obj.GetPredecessors()) {
            predecessors.add(GetId((predecessor as Value).getOrThrow()))
        }
        let exceptionCatchList = ArrayList<UInt32>()
        if (obj.IsLandingPadBlock()) {
            for (exception in obj.GetExceptions()) {
                exceptionCatchList.add(GetId((exception as Type).getOrThrow()))
            }
        }
        return CreateBlockDirect(builder, base, parentGroup,
            if (exprs.isEmpty()) { None } else { Some(exprs) },
            if (predecessors.isEmpty()) { None } else { Some(predecessors) }, obj.IsLandingPadBlock(),
            if (exceptionCatchList.isEmpty()) { None } else { Some(exceptionCatchList) })
    }

    private func Serialize(obj: BlockGroup): FlatBufferOffset {
        CJC_ASSERT(obj.GetOwnerFunc().isSome() || obj.GetOwnerExpression().isSome())
        let base = Serialize((obj as Value).getOrThrow())
        let entryBlock = if (let Some(value) <- obj.GetEntryBlock()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let blocks = ArrayList<UInt32>()
        for (block in obj.GetBlocks()) {
            blocks.add(GetId((block as Value).getOrThrow()))
        }
        let ownedFunc = if (let Some(value) <- obj.GetOwnerFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        let ownedExpression = if (let Some(value) <- obj.GetOwnerExpression()) {
            GetId(value)
        } else {
            0u32
        }
        return CreateBlockGroupDirect(builder, base, entryBlock,
            if (blocks.isEmpty()) { None } else { Some(blocks) }, ownedFunc, ownedExpression)
    }

    private func Serialize(obj: Function): FlatBufferOffset {
        let base = Serialize((obj as GlobalValue).getOrThrow())
        var genericDecl = 0u32
        if (let Some(genericFunction) <- obj.GetGenericDecl()) {
            if (genericFunction.IsFuncWithBody()) {
                genericDecl = GetId((genericFunction as Value).getOrThrow())
            }
        }
        var originalLambdaInfo = 0u32
        if (obj.GetFuncKind() == FuncKind.LAMBDA) {
            if (let Some(info) <- obj.originalLambdaInfo) {
                let genericTypeParams = ArrayList<UInt32>()
                for (param in info.genericTypeParams) {
                    genericTypeParams.add(GetId((param as Type).getOrThrow()))
                }
                originalLambdaInfo = CreateFuncSigInfoDirect(builder, Some(info.funcName),
                    GetId((info.funcType as Type).getOrThrow()),
                    if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) })
            }
        }
        let genericTypeParams = ArrayList<UInt32>()
        for (param in obj.GetGenericTypeParams()) {
            genericTypeParams.add(GetId((param as Type).getOrThrow()))
        }
        let paramDftValHostFunc = if (let Some(value) <- obj.GetParamDftValHostFunc()) {
            GetId((value as Value).getOrThrow())
        } else {
            0u32
        }
        var body = 0u32
        let params = ArrayList<UInt32>()
        for (param in obj.GetParams()) {
            params.add(GetId((param as Value).getOrThrow()))
        }
        var retVal = 0u32
        let propLoc = Serialize(obj.GetPropLocation())
        if (obj.IsFuncWithBody()) {
            body = GetId((obj.GetBody().getOrThrow() as Value).getOrThrow())
            if (let Some(value) <- obj.GetReturnValue()) {
                retVal = GetId((value as Value).getOrThrow())
            }
        }
        return CreateFunctionDirect(builder, base, genericDecl, UInt8(FuncKindIndex(obj.GetFuncKind())),
            obj.IsFastNative(), obj.IsCFFIWrapper(), originalLambdaInfo,
            if (genericTypeParams.isEmpty()) { None } else { Some(genericTypeParams) }, paramDftValHostFunc, body,
            if (params.isEmpty()) { None } else { Some(params) }, retVal, propLoc,
            obj.localId, obj.blockId, obj.blockGroupId)
    }

    private func Serialize(obj: LiteralValue): FlatBufferOffset {
        let base = Serialize((obj as Value).getOrThrow())
        return CreateLiteralValue(builder, base, UInt8(LiteralKindIndex(obj.literalKind)))
    }

    private func Serialize(obj: BoolLiteral): FlatBufferOffset {
        return CreateBoolLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetVal())
    }

    private func Serialize(obj: RuneLiteral): FlatBufferOffset {
        return CreateRuneLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), UInt32(obj.GetVal()))
    }

    private func Serialize(obj: StringLiteral): FlatBufferOffset {
        let base = Serialize((obj as LiteralValue).getOrThrow())
        return CreateStringLiteral(builder, base, builder.CreateSharedString(obj.GetVal()))
    }

    private func Serialize(obj: IntLiteral): FlatBufferOffset {
        return CreateIntLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetUnsignedVal())
    }

    private func Serialize(obj: FloatLiteral): FlatBufferOffset {
        return CreateFloatLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()), obj.GetVal())
    }

    private func Serialize(obj: UnitLiteral): FlatBufferOffset {
        return CreateUnitLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()))
    }

    private func Serialize(obj: NullLiteral): FlatBufferOffset {
        return CreateNullLiteral(builder, Serialize((obj as LiteralValue).getOrThrow()))
    }

    public func SerializePackage(pkg: Package): String {
        return serializePackage(pkg, None)
    }

    public func SerializePackage(pkg: Package, context: CHIRContext): String {
        return serializePackage(pkg, context)
    }

    private func serializePackage(pkg: Package, context: Option<CHIRContext>): String {
        let lines = ArrayList<String>()
        lines.add(CHIR_TEXT_HEADER_V2)
        appendPackage(lines, pkg)
        if (let Some(chirContext) <- context) {
            appendSourceFiles(lines, chirContext)
        }
        appendCustomDefs(lines, "local", pkg.GetStructs(), pkg.GetClasses(), pkg.GetEnums(), pkg.GetExtends())
        appendCustomDefs(lines, "import", pkg.GetImportedStructs(), pkg.GetImportedClasses(), pkg.GetImportedEnums(),
            pkg.GetImportedExtends())
        if (let Some(chirContext) <- context) {
            for (value in chirContext.GetAllocatedValues()) {
                if (let Some(literal) <- (value as LiteralValue)) {
                    Dispatch(lines, literal)
                }
            }
        }
        for (globalVar in pkg.GetGlobalVars()) {
            if (let Some(literal) <- globalVar.GetInitializer()) {
                Dispatch(lines, literal)
            }
        }
        for (globalVar in pkg.GetGlobalVars()) {
            appendGlobalVar(lines, globalVar)
        }
        for (fn in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            appendFunction(lines, fn)
        }
        for (fnBody in pkg.GetGlobalFunctions(includePureAbstract: true)) {
            if (let Some(body) <- fnBody.GetBody()) {
                appendBlockGroup(lines, body)
            }
        }
        return JoinStrings(lines, "\n")
    }

    private func appendSourceFiles(lines: ArrayList<String>, context: CHIRContext): Unit {
        let fileIds = ArrayList<UInt32>()
        let fileNameMap = context.GetFileNameMap()
        for ((fileId, _) in fileNameMap) {
            insertSortedFileId(fileIds, fileId)
        }
        for (fileId in fileIds) {
            let fields = CHIRLineFields("sourceFile")
            fields.add(fileId.toString())
            fields.add(fileNameMap[fileId])
            lines.add(CHIRWireJoinFields(fields))
        }
    }

    private func insertSortedFileId(fileIds: ArrayList<UInt32>, fileId: UInt32): Unit {
        var idx: Int64 = 0
        while (idx < fileIds.size) {
            if (fileIds[idx] == fileId) {
                return
            }
            if (fileId < fileIds[idx]) {
                fileIds.add(fileId, at: idx)
                return
            }
            idx++
        }
        fileIds.add(fileId)
    }

    private func appendPackage(lines: ArrayList<String>, pkg: Package): Unit {
        let fields = CHIRLineFields("package")
        fields.add(pkg.GetName())
        fields.add(AccessLevelIndex(pkg.GetPackageAccessLevel()).toString())
        fields.add(if (let Some(initFn) <- pkg.GetPackageInitFunc()) { CHIRValueId(initFn) } else { "" })
        fields.add(if (let Some(literalInitFn) <- pkg.GetPackageLiteralInitFunc()) {
            CHIRValueId(literalInitFn)
        } else {
            ""
        })
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendCustomDefs(lines: ArrayList<String>, scope: String, structs: ArrayList<StructDef>,
        classes: ArrayList<ClassDef>, enums: ArrayList<EnumDef>, extends: ArrayList<ExtendDef>): Unit {
        for (def in structs) {
            appendCustomDef(lines, scope, def)
        }
        for (def in classes) {
            appendCustomDef(lines, scope, def)
        }
        for (def in enums) {
            appendCustomDef(lines, scope, def)
        }
        for (def in extends) {
            appendCustomDef(lines, scope, def)
        }
    }

    private func appendCustomDef(lines: ArrayList<String>, scope: String, def: CustomTypeDef): Unit {
        let fields = CHIRLineFields("custom")
        fields.add(CHIRBaseId(def))
        fields.add(CHIRCustomTypeKindName(def))
        fields.add(scope)
        fields.add(def.GetPackageName())
        fields.add(def.GetIdentifier())
        fields.add(serializeGenericParams(def.genericTypeParams))
        fields.add(serializeMemberVars(def.GetDirectInstanceVars()))
        fields.add(serializeFunctionRefs(def.GetMethods()))
        fields.add(serializeEnumCtors(def))
        fields.add(serializeSuperClass(def))
        fields.add(serializeInterfaces(def))
        fields.add(serializeExtends(def.GetExtends()))
        fields.add(serializeExtendedType(def))
        fields.add(CHIRSerializeDebugLocation(def.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(def))
        fields.add(CHIRSerializeBaseAnnotations(def))
        fields.add(def.GetSrcCodeIdentifier())
        fields.add(CHIRSerializeAnnoInfo(def.GetAnnoInfo()))
        fields.add(serializeGlobalVarRefs(def.GetStaticMemberVars()))
        fields.add(if (let Some(initFn) <- def.GetVarInitializationFunc()) { CHIRValueId(initFn) } else { "" })
        fields.add(if (let Some(genericDecl) <- def.GetGenericDecl()) { CHIRBaseId(genericDecl) } else { "" })
        fields.add(serializeInterfaceTypes(def))
        fields.add(serializeSuperClassType(def))
        fields.add(if (let Some(structDef) <- (def as StructDef)) { CHIRBoolToWire(structDef.IsCStruct()) } else { "" })
        fields.add(if (let Some(enumDef) <- (def as EnumDef)) { CHIRBoolToWire(!enumDef.IsExhaustive()) } else { "" })
        fields.add(SerializeVTable(def.GetDefVTable()))
        fields.add(if (let Some(ty) <- def.GetType()) { CHIRSerializeType(ty) } else { "" })
        lines.add(CHIRWireJoinFields(fields))
    }

    private func Dispatch(lines: ArrayList<String>, literal: LiteralValue): Unit {
        if (serializedLiteralValues.contains(literal.nodeId)) {
            return
        }
        serializedLiteralValues.add(literal.nodeId)
        Serialize(lines, literal)
    }

    private func Serialize(lines: ArrayList<String>, literal: LiteralValue): Unit {
        let fields = CHIRLineFields("literal")
        fields.add(CHIRValueId(literal))
        fields.add(if (let Some(ty) <- literal.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(LiteralKindIndex(literal.literalKind).toString())
        var payload = ""
        if (let Some(boolLit) <- (literal as BoolLiteral)) {
            payload = CHIRBoolToWire(boolLit.GetVal())
        }
        if (let Some(intLit) <- (literal as IntLiteral)) {
            payload = intLit.GetUnsignedVal().toString()
        }
        if (let Some(floatLit) <- (literal as FloatLiteral)) {
            payload = floatLit.GetVal().toString()
        }
        if (let Some(runeLit) <- (literal as RuneLiteral)) {
            payload = runeLit.GetVal().toString()
        }
        if (let Some(stringLit) <- (literal as StringLiteral)) {
            payload = stringLit.GetVal()
        }
        fields.add(payload)
        fields.add(CHIRSerializeDebugLocation(literal.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(literal))
        fields.add(CHIRSerializeBaseAnnotations(literal))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendGlobalVar(lines: ArrayList<String>, globalVar: GlobalVar): Unit {
        let fields = CHIRLineFields("global")
        fields.add(CHIRValueId(globalVar))
        fields.add(globalVar.GetIdentifier())
        fields.add(globalVar.GetSrcCodeIdentifier())
        fields.add(globalVar.GetRawMangledName())
        fields.add(globalVar.GetPackageName())
        fields.add(if (let Some(ty) <- globalVar.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(if (let Some(initValue) <- globalVar.GetInitializerValue()) {
            CHIRValueId(initValue)
        } else if (let Some(initFunc) <- globalVar.GetInitFunc()) {
            CHIRValueId(initFunc)
        } else {
            ""
        })
        fields.add(CHIRWireJoinList(globalVar.GetFeatures()))
        fields.add(if (let Some(parentDef) <- globalVar.GetParentCustomTypeDef()) { CHIRBaseId(parentDef) } else { "" })
        fields.add(CHIRSerializeAnnoInfo(globalVar.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(globalVar.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(globalVar))
        fields.add(CHIRSerializeBaseAnnotations(globalVar))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendFunction(lines: ArrayList<String>, fn: Function): Unit {
        let fields = CHIRLineFields("function")
        fields.add(CHIRValueId(fn))
        fields.add(fn.GetIdentifier())
        fields.add(fn.GetSrcCodeIdentifier())
        fields.add(fn.GetRawMangledName())
        fields.add(fn.GetPackageName())
        fields.add(FuncKindIndex(fn.GetFuncKind()).toString())
        fields.add(if (let Some(funcTy) <- fn.GetFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(serializeParameters(fn.GetParams()))
        fields.add(if (let Some(body) <- fn.GetBody()) { CHIRValueId(body) } else { "" })
        fields.add(if (let Some(ret) <- fn.GetReturnValue()) { CHIRValueId(ret) } else { "" })
        fields.add(if (let Some(parentDef) <- fn.GetParentCustomTypeDef()) { CHIRBaseId(parentDef) } else { "" })
        fields.add(CHIRWireJoinList(fn.GetFeatures()))
        fields.add(if (let Some(genericDecl) <- fn.GetGenericDecl()) { CHIRValueId(genericDecl) } else { "" })
        fields.add(if (let Some(hostFunc) <- fn.GetParamDftValHostFunc()) { CHIRValueId(hostFunc) } else { "" })
        fields.add(CHIRSerializeDebugLocation(fn.GetPropLocation()))
        fields.add(CHIRSerializeAnnoInfo(fn.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(fn.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(fn))
        fields.add(CHIRSerializeBaseAnnotations(fn))
        fields.add(if (let Some(rawMethod) <- fn.GetWrappedRawMethod()) {
            if (rawMethod.GetBody().isSome()) { CHIRValueId(rawMethod) } else { "" }
        } else {
            ""
        })
        fields.add(if (let Some(funcTy) <- fn.GetOverrideSrcFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(LinkTypeInfo(fn.GetLinkTypeInfo()).ToString())
        fields.add(CHIRBoolToWire(fn.IsCFFIWrapper()))
        lines.add(CHIRWireJoinFields(fields))
    }

    private func appendBlockGroup(lines: ArrayList<String>, group: BlockGroup): Unit {
        if (serializedBlockGroups.contains(group.nodeId)) {
            return
        }
        serializedBlockGroups.add(group.nodeId)
        let fields = CHIRLineFields("blockGroup")
        fields.add(CHIRValueId(group))
        fields.add(group.GetIdentifier())
        fields.add(if (let Some(ownerFn) <- group.GetOwnerFunc()) { CHIRValueId(ownerFn) } else { "" })
        fields.add(if (let Some(ownerExpr) <- group.GetOwnerExpression()) { CHIRBaseId(ownerExpr) } else { "" })
        fields.add(if (let Some(entry) <- group.GetEntryBlock()) { CHIRValueId(entry) } else { "" })
        fields.add(serializeBlockRefs(group.GetBlocks()))
        fields.add(CHIRSerializeDebugLocation(group.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(group))
        fields.add(CHIRSerializeBaseAnnotations(group))
        lines.add(CHIRWireJoinFields(fields))
        for (block in group.GetBlocks()) {
            appendBlock(lines, group, block)
        }
    }

    private func appendBlock(lines: ArrayList<String>, group: BlockGroup, block: Block): Unit {
        let fields = CHIRLineFields("block")
        fields.add(CHIRValueId(block))
        fields.add(CHIRValueId(group))
        fields.add(block.GetIdentifier())
        fields.add(serializeClassTypes(block.GetExceptions()))
        fields.add(CHIRSerializeDebugLocation(block.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(block))
        fields.add(serializeBlockRefs(block.GetPredecessors()))
        fields.add(CHIRSerializeBaseAnnotations(block))
        lines.add(CHIRWireJoinFields(fields))
        var index: Int64 = 0
        for (expr in block.GetExpressions()) {
            appendExpression(lines, block, index, expr)
            index++
        }
    }

    private func appendExpression(lines: ArrayList<String>, block: Block, index: Int64, expr: Expression): Unit {
        let fields = CHIRLineFields("expression")
        fields.add(CHIRBaseId(expr))
        fields.add(CHIRValueId(block))
        fields.add(index.toString())
        fields.add(ExprKindIndex(expr.GetExprKind()).toString())
        fields.add(if (let Some(result) <- expr.GetResult()) { CHIRValueId(result) } else { "" })
        fields.add(if (let Some(result) <- expr.GetResult()) { result.GetIdentifier() } else { "" })
        fields.add(if (let Some(resultTy) <- expr.GetResultType()) { CHIRSerializeType(resultTy) } else { "" })
        fields.add(serializeValueRefs(expr.GetOperands()))
        fields.add(serializeBlockRefs(if (let Some(term) <- expr.AsTerminator()) {
            term.GetSuccessors()
        } else {
            ArrayList<Block>()
        }))
        fields.add(serializeLiteral(expr))
        fields.add(CHIRSerializeDebugLocation(expr.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(expr))
        fields.add(serializeBlockGroupRefs(expr.GetBlockGroups()))
        fields.add(CHIRSerializeBaseAnnotations(expr))
        fields.add(serializeResultSrcCodeIdentifier(expr))
        fields.add(serializeResultIsRetValue(expr))
        fields.add(serializeResultDebugLocation(expr))
        fields.add(serializeResultAttributes(expr))
        fields.add(serializeResultBaseAnnotations(expr))
        fields.add(serializeLambdaParams(expr))
        fields.add(serializeExpressionPayload(expr))
        lines.add(CHIRWireJoinFields(fields))
        for (group in expr.GetBlockGroups()) {
            appendBlockGroup(lines, group)
        }
    }

    private func serializeGenericParams(params: ArrayList<GenericType>): String {
        let out = ArrayList<String>()
        for (param in params) {
            out.add(CHIRSerializeType(param))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeMemberVars(vars: ArrayList<MemberVarInfo>): String {
        let out = ArrayList<String>()
        for (memberVar in vars) {
            let fields = ArrayList<String>()
            fields.add(memberVar.name)
            fields.add(CHIRSerializeType(memberVar.ty))
            fields.add(CHIRBoolToWire(memberVar.isStatic))
            fields.add(CHIRBoolToWire(memberVar.isReadOnly))
            fields.add(memberVar.rawMangledName)
            fields.add(CHIRSerializeAttributeInfo(memberVar.attributeInfo))
            fields.add(CHIRSerializeDebugLocation(memberVar.loc))
            fields.add(CHIRSerializeAnnoInfo(memberVar.annoInfo))
            fields.add(if (let Some(initFn) <- memberVar.initializerFunc) { CHIRValueId(initFn) } else { "" })
            fields.add(if (let Some(outerDef) <- memberVar.outerDef) { CHIRBaseId(outerDef) } else { "" })
            out.add(CHIRWireJoinFields(fields))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeFunctionRefs(values: ArrayList<Function>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func SerializeVTable(vtable: VTableInDef): String {
        let out = ArrayList<String>()
        for (vtableInType in vtable.GetTypeVTables()) {
            let srcParentType = vtableInType.GetSrcParentType() ?? continue
            let fields = ArrayList<String>()
            fields.add(CHIRSerializeType(srcParentType))
            let virtualMethods = ArrayList<String>()
            for (info in vtableInType.GetVirtualMethods()) {
                let methodFields = ArrayList<String>()
                methodFields.add(info.GetMethodName())
                methodFields.add(CHIRSerializeType(info.GetMethodSigType()))
                methodFields.add(CHIRSerializeGenericTypeList(info.GetGenericTypeParams()))
                methodFields.add(if (let Some(fn) <- info.GetVirtualMethod()) { CHIRValueId(fn) } else { "" })
                methodFields.add(CHIRSerializeAttributeInfo(info.GetAttributeInfo()))
                methodFields.add(CHIRSerializeType(info.GetOriginalFuncType()))
                methodFields.add(CHIRSerializeType(info.GetInstParentType()))
                methodFields.add(CHIRSerializeType(info.GetMethodInstRetType()))
                virtualMethods.add(CHIRWireJoinFields(methodFields))
            }
            fields.add(CHIRWireJoinList(virtualMethods))
            out.add(CHIRWireJoinFields(fields))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeGlobalVarRefs(values: ArrayList<GlobalVar>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeBlockRefs(values: ArrayList<Block>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeBlockGroupRefs(values: ArrayList<BlockGroup>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeResultSrcCodeIdentifier(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return result.GetSrcCodeIdentifier()
        }
        return ""
    }

    private func serializeResultIsRetValue(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRBoolToWire(result.IsRetValue())
        }
        return ""
    }

    private func serializeResultDebugLocation(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeDebugLocation(result.GetDebugLocation())
        }
        return ""
    }

    private func serializeResultAttributes(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeAttributes(result)
        }
        return ""
    }

    private func serializeResultBaseAnnotations(expr: Expression): String {
        if (let Some(result) <- expr.GetResult()) {
            return CHIRSerializeBaseAnnotations(result)
        }
        return ""
    }

    private func serializeLambdaParams(expr: Expression): String {
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            return serializeParameterRecords(lambdaExpr.GetParams())
        }
        return ""
    }

    private func serializeValueRefs(values: ArrayList<Value>): String {
        let out = ArrayList<String>()
        for (value in values) {
            out.add(CHIRValueId(value))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeClassTypes(types: ArrayList<ClassType>): String {
        let out = ArrayList<String>()
        for (ty in types) {
            out.add(CHIRSerializeType(ty))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeEnumCtors(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        if (let Some(enumDef) <- (def as EnumDef)) {
            for (ctor in enumDef.GetCtors()) {
                let fields = ArrayList<String>()
                fields.add(ctor.name)
                let payloadTypes = ArrayList<String>()
                for (payloadTy in ctor.payloadTypes) {
                    payloadTypes.add(CHIRSerializeType(payloadTy))
                }
                fields.add(CHIRWireJoinList(payloadTypes))
                out.add(CHIRWireJoinFields(fields))
            }
        }
        return CHIRWireJoinList(out)
    }

    private func serializeSuperClass(def: CustomTypeDef): String {
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superDef) <- classDef.GetSuperClassDef()) {
                return CHIRBaseId(superDef)
            }
        }
        return ""
    }

    private func serializeInterfaces(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        if (let Some(classDef) <- (def as ClassDef)) {
            for (interfaceDef in classDef.GetImplementedInterfaceDefs()) {
                out.add(CHIRBaseId(interfaceDef))
            }
        }
        return CHIRWireJoinList(out)
    }

    private func serializeInterfaceTypes(def: CustomTypeDef): String {
        let out = ArrayList<String>()
        for (interfaceTy in def.GetImplementedInterfaceTys()) {
            out.add(CHIRSerializeType(interfaceTy))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeSuperClassType(def: CustomTypeDef): String {
        if (let Some(classDef) <- (def as ClassDef)) {
            if (let Some(superTy) <- classDef.GetSuperClassTy()) {
                return CHIRSerializeType(superTy)
            }
        }
        return ""
    }

    private func serializeExtends(extends: ArrayList<ExtendDef>): String {
        let out = ArrayList<String>()
        for (extendDef in extends) {
            out.add(CHIRBaseId(extendDef))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeExtendedType(def: CustomTypeDef): String {
        if (let Some(extendDef) <- (def as ExtendDef)) {
            if (let Some(extendedTy) <- extendDef.extendedType) {
                return CHIRSerializeType(extendedTy)
            }
        }
        return ""
    }

    private func serializeParameters(params: ArrayList<Parameter>): String {
        return serializeParameterRecords(params)
    }

    private func serializeParameterRecords(params: ArrayList<Parameter>): String {
        let out = ArrayList<String>()
        for (param in params) {
            out.add(serializeParameterRecord(param))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeParameterRecord(param: Parameter): String {
        let fields = ArrayList<String>()
        fields.add(CHIRValueId(param))
        fields.add(param.GetIdentifier())
        fields.add(param.GetSrcCodeIdentifier())
        fields.add(if (let Some(ty) <- param.GetType()) { CHIRSerializeType(ty) } else { "" })
        fields.add(CHIRSerializeAnnoInfo(param.GetAnnoInfo()))
        fields.add(CHIRSerializeDebugLocation(param.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(param))
        fields.add(CHIRSerializeBaseAnnotations(param))
        return CHIRWireJoinFields(fields)
    }

    private func serializeLiteral(expr: Expression): String {
        if (let Some(constant) <- (expr as Constant)) {
            let fields = ArrayList<String>()
            let literal = constant.literal
            fields.add(LiteralKindIndex(literal.literalKind).toString())
            if (let Some(boolLit) <- (literal as BoolLiteral)) {
                fields.add(CHIRBoolToWire(boolLit.GetVal()))
            } else if (let Some(intLit) <- (literal as IntLiteral)) {
                fields.add(intLit.GetUnsignedVal().toString())
            } else if (let Some(floatLit) <- (literal as FloatLiteral)) {
                fields.add(floatLit.GetVal().toString())
            } else if (let Some(runeLit) <- (literal as RuneLiteral)) {
                fields.add(runeLit.GetVal().toString())
            } else if (let Some(stringLit) <- (literal as StringLiteral)) {
                fields.add(stringLit.GetVal())
            } else {
                fields.add("")
            }
            return CHIRWireJoinFields(fields)
        }
        return ""
    }

    private func serializeExpressionPayload(expr: Expression): String {
        if (let Some(branch) <- (expr as Branch)) {
            return expressionPayload("branch", [SourceExprIndex(branch.GetSourceExpr()).toString()])
        }
        if (let Some(multiBranch) <- (expr as MultiBranch)) {
            return expressionPayload("multiBranch", [CHIRSerializeUInt64List(multiBranch.GetCaseVals())])
        }
        if (let Some(intOp) <- (expr as IntOpWithException)) {
            return expressionPayload("intOpWithException", [ExprKindIndex(intOp.GetOpKind()).toString()])
        }
        if (let Some(allocateWithException) <- (expr as AllocateWithException)) {
            return expressionPayload("allocate", [CHIRSerializeType(allocateWithException.GetType())])
        }
        if (let Some(allocate) <- (expr as Allocate)) {
            return expressionPayload("allocate", [CHIRSerializeType(allocate.GetType())])
        }
        if (let Some(getElementRef) <- (expr as GetElementRef)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(getElementRef.GetPath())])
        }
        if (let Some(getElementByName) <- (expr as GetElementByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(getElementByName.GetNames())])
        }
        if (let Some(storeElementRef) <- (expr as StoreElementRef)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(storeElementRef.GetPath())])
        }
        if (let Some(storeElementByName) <- (expr as StoreElementByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(storeElementByName.GetNames())])
        }
        if (let Some(applyWithException) <- (expr as ApplyWithException)) {
            return serializeFuncCallPayload("apply", applyWithException.GetInstantiatedTypeArgs(),
                applyWithException.GetThisType(), false)
        }
        if (let Some(apply) <- (expr as Apply)) {
            return serializeFuncCallPayload("apply", apply.GetInstantiatedTypeArgs(), apply.GetThisType(),
                apply.IsSuperCall())
        }
        if (let Some(invokeStaticWithException) <- (expr as InvokeStaticWithException)) {
            return serializeInvokePayload(invokeStaticWithException.GetInstantiatedTypeArgs(),
                invokeStaticWithException.GetThisType(), invokeStaticWithException.GetMethodName(),
                invokeStaticWithException.GetMethodType(), invokeStaticWithException.GetGenericTypeParams(),
                invokeStaticWithException.GetVirtualMethodOffset())
        }
        if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
            return serializeInvokePayload(invokeWithException.GetInstantiatedTypeArgs(),
                invokeWithException.GetThisType(), invokeWithException.GetMethodName(),
                invokeWithException.GetMethodType(), invokeWithException.GetGenericTypeParams(),
                invokeWithException.GetVirtualMethodOffset())
        }
        if (let Some(invokeStatic) <- (expr as InvokeStatic)) {
            return serializeInvokePayload(invokeStatic.GetInstantiatedTypeArgs(), invokeStatic.GetThisType(),
                invokeStatic.GetMethodName(), invokeStatic.GetMethodType(), invokeStatic.GetGenericTypeParams(),
                invokeStatic.GetVirtualMethodOffset())
        }
        if (let Some(invoke) <- (expr as Invoke)) {
            return serializeInvokePayload(invoke.GetInstantiatedTypeArgs(), invoke.GetThisType(),
                invoke.GetMethodName(), invoke.GetMethodType(), invoke.GetGenericTypeParams(),
                invoke.GetVirtualMethodOffset())
        }
        if (let Some(instanceOf) <- (expr as InstanceOf)) {
            return expressionPayload("instanceOf", [CHIRSerializeType(instanceOf.GetType())])
        }
        if (let Some(getInstantiateValue) <- (expr as GetInstantiateValue)) {
            return expressionPayload("instantiate", [CHIRSerializeTypeList(getInstantiateValue.GetInstantiateTypes())])
        }
        if (let Some(getRTTIStatic) <- (expr as GetRTTIStatic)) {
            return expressionPayload("rttiStatic", [CHIRSerializeType(getRTTIStatic.GetRTTIType())])
        }
        if (let Some(field) <- (expr as Field)) {
            return expressionPayload("indexPath", [CHIRSerializeUInt64List(field.GetPath())])
        }
        if (let Some(fieldByName) <- (expr as FieldByName)) {
            return expressionPayload("namePath", [CHIRWireJoinList(fieldByName.GetNames())])
        }
        if (let Some(rawArrayAllocateWithException) <- (expr as RawArrayAllocateWithException)) {
            return expressionPayload("rawArrayAllocate", [CHIRSerializeType(rawArrayAllocateWithException.GetElementType())])
        }
        if (let Some(rawArrayAllocate) <- (expr as RawArrayAllocate)) {
            return expressionPayload("rawArrayAllocate", [CHIRSerializeType(rawArrayAllocate.GetElementType())])
        }
        if (let Some(intrinsicWithException) <- (expr as IntrinsicWithException)) {
            return expressionPayload("intrinsic", [IntrinsicKindName(intrinsicWithException.GetIntrinsicKind()),
                CHIRSerializeTypeList(intrinsicWithException.GetInstantiatedTypeArgs())])
        }
        if (let Some(intrinsic) <- (expr as Intrinsic)) {
            return expressionPayload("intrinsic", [IntrinsicKindName(intrinsic.GetIntrinsicKind()),
                CHIRSerializeTypeList(intrinsic.GetInstantiatedTypeArgs())])
        }
        if (let Some(debugExpr) <- (expr as Debug)) {
            return expressionPayload("debug", [debugExpr.GetSrcCodeIdentifier()])
        }
        if (let Some(spawnWithException) <- (expr as SpawnWithException)) {
            return expressionPayload("spawn", [if (let Some(fn) <- spawnWithException.GetExecuteClosure()) {
                CHIRValueId(fn)
            } else {
                ""
            }])
        }
        if (let Some(spawnExpr) <- (expr as Spawn)) {
            return expressionPayload("spawn", [if (let Some(fn) <- spawnExpr.GetExecuteClosure()) {
                CHIRValueId(fn)
            } else {
                ""
            }])
        }
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            return serializeLambdaPayload(lambdaExpr)
        }
        return ""
    }

    private func serializeFuncCallPayload(tag: String, instTypeArgs: ArrayList<Type>, thisType: Option<Type>,
        isSuperCall: Bool): String {
        let fields = ArrayList<String>()
        fields.add(CHIRSerializeTypeList(instTypeArgs))
        fields.add(if (let Some(ty) <- thisType) { CHIRSerializeType(ty) } else { "" })
        fields.add(CHIRBoolToWire(isSuperCall))
        return expressionPayload(tag, fields)
    }

    private func serializeInvokePayload(instTypeArgs: ArrayList<Type>, thisType: Option<Type>, methodName: String,
        methodType: FuncType, genericTypeParams: ArrayList<GenericType>, virtualMethodOffset: Option<UInt64>): String {
        let fields = ArrayList<String>()
        fields.add(CHIRSerializeTypeList(instTypeArgs))
        fields.add(if (let Some(ty) <- thisType) { CHIRSerializeType(ty) } else { "" })
        fields.add(methodName)
        fields.add(CHIRSerializeType(methodType))
        fields.add(CHIRSerializeGenericTypeList(genericTypeParams))
        fields.add(if (let Some(offset) <- virtualMethodOffset) { offset.toString() } else { "" })
        return expressionPayload("invoke", fields)
    }

    private func serializeLambdaPayload(lambdaExpr: Lambda): String {
        let fields = ArrayList<String>()
        fields.add(if (let Some(funcTy) <- lambdaExpr.GetFuncType()) { CHIRSerializeType(funcTy) } else { "" })
        fields.add(CHIRBoolToWire(lambdaExpr.IsLocalFunc()))
        fields.add(lambdaExpr.GetIdentifier())
        fields.add(lambdaExpr.GetSrcCodeIdentifier())
        fields.add(CHIRSerializeGenericTypeList(lambdaExpr.GetGenericTypeParams()))
        fields.add(if (let Some(retValue) <- lambdaExpr.GetReturnValue()) { CHIRValueId(retValue) } else { "" })
        fields.add(CHIRBoolToWire(lambdaExpr.IsCompileTimeValue()))
        fields.add(if (let Some(hostFunc) <- lambdaExpr.GetParamDftValHostFunc()) {
            CHIRBaseId(hostFunc)
        } else {
            ""
        })
        return expressionPayload("lambda", fields)
    }

    private func expressionPayload(tag: String, values: ArrayList<String>): String {
        let fields = CHIRLineFields(tag)
        for (value in values) {
            fields.add(value)
        }
        return CHIRWireJoinFields(fields)
    }

    private func expressionPayload(tag: String, values: Array<String>): String {
        let fields = CHIRLineFields(tag)
        for (value in values) {
            fields.add(value)
        }
        return CHIRWireJoinFields(fields)
    }
}
