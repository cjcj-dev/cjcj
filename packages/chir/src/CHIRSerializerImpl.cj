package cangjie_compiler::chir

import std.collection.*

class CHIRSerializerImpl {
    private let serializedBlockGroups: HashSet<Int64> = HashSet<Int64>()
    private let serializedLiteralValues: HashSet<Int64> = HashSet<Int64>()

    public init() {}

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
