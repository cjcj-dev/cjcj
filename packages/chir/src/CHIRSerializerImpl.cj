package cangjie_compiler::chir

import std.collection.*

class CHIRSerializerImpl {
    private let serializedBlockGroups: HashSet<Int64> = HashSet<Int64>()

    public init() {}

    public func SerializePackage(pkg: Package): String {
        let lines = ArrayList<String>()
        lines.add(CHIR_TEXT_HEADER_V2)
        appendPackage(lines, pkg)
        appendCustomDefs(lines, "local", pkg.GetStructs(), pkg.GetClasses(), pkg.GetEnums(), pkg.GetExtends())
        appendCustomDefs(lines, "import", pkg.GetImportedStructs(), pkg.GetImportedClasses(), pkg.GetImportedEnums(),
            pkg.GetImportedExtends())
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
        fields.add(serializeMemberVars(def.GetInstanceVars()))
        fields.add(serializeFunctionRefs(def.GetMethods()))
        fields.add(serializeEnumCtors(def))
        fields.add(serializeSuperClass(def))
        fields.add(serializeInterfaces(def))
        fields.add(serializeExtends(def.GetExtends()))
        fields.add(serializeExtendedType(def))
        fields.add(CHIRSerializeDebugLocation(def.GetDebugLocation()))
        fields.add(CHIRSerializeAttributes(def))
        fields.add(CHIRSerializeBaseAnnotations(def))
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
        fields.add(if (let Some(initValue) <- globalVar.GetInitializerValue()) { CHIRValueId(initValue) } else { "" })
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
        let out = ArrayList<String>()
        for (param in params) {
            let fields = ArrayList<String>()
            fields.add(CHIRValueId(param))
            fields.add(param.GetIdentifier())
            fields.add(param.GetSrcCodeIdentifier())
            fields.add(if (let Some(ty) <- param.GetType()) { CHIRSerializeType(ty) } else { "" })
            fields.add(CHIRSerializeAnnoInfo(param.GetAnnoInfo()))
            fields.add(CHIRSerializeDebugLocation(param.GetDebugLocation()))
            fields.add(CHIRSerializeAttributes(param))
            fields.add(CHIRSerializeBaseAnnotations(param))
            out.add(CHIRWireJoinFields(fields))
        }
        return CHIRWireJoinList(out)
    }

    private func serializeLiteral(expr: Expression): String {
        if (let Some(constant) <- (expr as Constant)) {
            let fields = ArrayList<String>()
            let literal = constant.literal
            fields.add(LiteralKindIndex(literal.literalKind).toString())
            if (let Some(boolLit) <- (literal as BoolLiteral)) {
                fields.add(CHIRBoolToWire(boolLit.value))
            } else if (let Some(intLit) <- (literal as IntLiteral)) {
                fields.add(intLit.value.toString())
            } else if (let Some(floatLit) <- (literal as FloatLiteral)) {
                fields.add(floatLit.value.toString())
            } else if (let Some(runeLit) <- (literal as RuneLiteral)) {
                fields.add(runeLit.value.toString())
            } else if (let Some(stringLit) <- (literal as StringLiteral)) {
                fields.add(stringLit.value)
            } else {
                fields.add("")
            }
            return CHIRWireJoinFields(fields)
        }
        return ""
    }
}
