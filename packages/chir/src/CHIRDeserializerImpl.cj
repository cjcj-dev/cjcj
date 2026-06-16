package cangjie_compiler::chir

import std.collection.*
import std.convert.*

class CHIRDeserializerImpl {
    private let builder: CHIRBuilder
    private let customDefs: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    private let customDefsById: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    private let valuesById: HashMap<String, Value> = HashMap<String, Value>()
    private let expressionsById: HashMap<String, Expression> = HashMap<String, Expression>()
    private let customRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let globalRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let functionRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let blockGroupRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let blockRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let expressionRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private var packageRecord: Option<ArrayList<String>> = None

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func DeserializePackage(text: String): Package {
        let lines = text.split("\n")
        if (lines.isEmpty()) {
            return builder.CreatePackage("<deserialized>")
        }
        if (lines[0] == CHIR_TEXT_HEADER_V1) {
            return DeserializeV1(lines)
        }
        if (lines[0] != CHIR_TEXT_HEADER_V2) {
            let name = if (text.startsWith("package ")) { text[8..].split("\n")[0] } else { "<deserialized>" }
            return builder.CreatePackage(name)
        }
        parseRecords(lines)
        let pkg = createPackage()
        createCustomDefs(pkg)
        createGlobalVars(pkg)
        createFunctions(pkg)
        createBlockGroupsAndBlocks()
        configureCustomDefs()
        configureGlobalsAndFunctions()
        createExpressions()
        configureBlockGroups()
        configurePackageFunctions(pkg)
        return pkg
    }

    private func parseRecords(lines: Array<String>): Unit {
        var idx: Int64 = 1
        while (idx < lines.size) {
            let line = lines[idx]
            idx++
            if (line.isEmpty()) {
                continue
            }
            let fields = CHIRWireSplitFields(line)
            if (fields.isEmpty()) {
                continue
            }
            match (fields[0]) {
                case "package" => packageRecord = fields
                case "custom" => customRecords.add(fields)
                case "global" => globalRecords.add(fields)
                case "function" => functionRecords.add(fields)
                case "blockGroup" => blockGroupRecords.add(fields)
                case "block" => blockRecords.add(fields)
                case "expression" => expressionRecords.add(fields)
                case _ => ()
            }
        }
    }

    private func createPackage(): Package {
        if (let Some(fields) <- packageRecord) {
            let pkg = builder.CreatePackage(CHIRFieldAt(fields, 1))
            pkg.SetPackageAccessLevel(CHIRAccessLevelFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 2))))
            return pkg
        }
        return builder.CreatePackage("<deserialized>")
    }

    private func createCustomDefs(pkg: Package): Unit {
        for (fields in customRecords) {
            let id = CHIRFieldAt(fields, 1)
            let kind = CHIRFieldAt(fields, 2)
            let scope = CHIRFieldAt(fields, 3)
            let packageName = CHIRFieldAt(fields, 4)
            let identifier = CHIRFieldAt(fields, 5)
            let def = CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
            customDefsById[id] = def
            if (scope == "import") {
                addImportedDef(pkg, def)
            } else {
                addLocalDef(pkg, def)
            }
        }
    }

    private func addLocalDef(pkg: Package, def: CustomTypeDef): Unit {
        if (let Some(structDef) <- (def as StructDef)) {
            pkg.AddStruct(structDef)
        } else if (let Some(classDef) <- (def as ClassDef)) {
            pkg.AddClass(classDef)
        } else if (let Some(enumDef) <- (def as EnumDef)) {
            pkg.AddEnum(enumDef)
        } else if (let Some(extendDef) <- (def as ExtendDef)) {
            pkg.AddExtend(extendDef)
        }
    }

    private func addImportedDef(pkg: Package, def: CustomTypeDef): Unit {
        if (let Some(structDef) <- (def as StructDef)) {
            pkg.AddImportedStruct(structDef)
        } else if (let Some(classDef) <- (def as ClassDef)) {
            pkg.AddImportedClass(classDef)
        } else if (let Some(enumDef) <- (def as EnumDef)) {
            pkg.AddImportedEnum(enumDef)
        } else if (let Some(extendDef) <- (def as ExtendDef)) {
            pkg.AddImportedExtend(extendDef)
        }
    }

    private func createGlobalVars(pkg: Package): Unit {
        for (fields in globalRecords) {
            let globalTy = CHIRParseType(CHIRFieldAt(fields, 6), builder, customDefs)
            let ownerPackage = if (CHIRFieldAt(fields, 5).isEmpty()) { pkg.GetName() } else { CHIRFieldAt(fields, 5) }
            let globalVar = builder.CreateGlobalVar(globalTy, CHIRFieldAt(fields, 2),
                srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                packageName: ownerPackage)
            CHIRApplyAnnoInfo(globalVar.GetAnnoInfo(), CHIRFieldAt(fields, 10))
            CHIRApplyBaseInfo(globalVar, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12))
            for (feature in CHIRWireSplitList(CHIRFieldAt(fields, 8))) {
                if (!feature.isEmpty()) {
                    globalVar.AddFeature(feature)
                }
            }
            valuesById[CHIRFieldAt(fields, 1)] = globalVar
            pkg.AddGlobalVar(globalVar)
        }
    }

    private func createFunctions(pkg: Package): Unit {
        for (fields in functionRecords) {
            let parsedTy = CHIRParseType(CHIRFieldAt(fields, 7), builder, customDefs)
            let funcTy = if (let Some(found) <- (parsedTy as FuncType)) {
                found
            } else {
                builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetInvalidTy())
            }
            let ownerPackage = if (CHIRFieldAt(fields, 5).isEmpty()) { pkg.GetName() } else { CHIRFieldAt(fields, 5) }
            let fn = builder.CreateFunction(funcTy, CHIRFieldAt(fields, 2), srcCodeIdentifier: CHIRFieldAt(fields, 3),
                rawMangledName: CHIRFieldAt(fields, 4), packageName: ownerPackage)
            fn.SetFuncKind(CHIRFuncKindFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 6))))
            CHIRApplyAnnoInfo(fn.GetAnnoInfo(), CHIRFieldAt(fields, 16))
            CHIRApplyBaseInfo(fn, CHIRFieldAt(fields, 17), CHIRFieldAt(fields, 18))
            fn.SetPropLocation(CHIRParseDebugLocation(CHIRFieldAt(fields, 15)))
            for (feature in CHIRWireSplitList(CHIRFieldAt(fields, 12))) {
                if (!feature.isEmpty()) {
                    fn.AddFeature(feature)
                }
            }
            valuesById[CHIRFieldAt(fields, 1)] = fn
            createParameters(fn, CHIRFieldAt(fields, 8))
            if (fn.GetParams().isEmpty()) {
                synthesizeSignatureParameters(fn, funcTy)
            }
            pkg.AddGlobalFunc(fn)
        }
    }

    private func createParameters(fn: Function, value: String): Unit {
        for (item in CHIRWireSplitList(value)) {
            if (item.isEmpty()) {
                continue
            }
            let fields = CHIRWireSplitFields(item)
            let paramTy = CHIRParseType(CHIRFieldAt(fields, 3), builder, customDefs)
            let param = builder.CreateParameter(paramTy, CHIRFieldAt(fields, 1), fn)
            param.SetSrcCodeIdentifier(CHIRFieldAt(fields, 2))
            CHIRApplyAnnoInfo(param.GetAnnoInfo(), CHIRFieldAt(fields, 4))
            CHIRApplyBaseInfo(param, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6))
            valuesById[CHIRFieldAt(fields, 0)] = param
        }
    }

    private func synthesizeSignatureParameters(fn: Function, funcTy: FuncType): Unit {
        var index: Int64 = 0
        for (paramTy in funcTy.GetParamTypes()) {
            let param = builder.CreateParameter(paramTy, "%arg${index}", fn)
            valuesById[CHIRValueId(param)] = param
            index++
        }
    }

    private func createBlockGroupsAndBlocks(): Unit {
        for (fields in blockGroupRecords) {
            let group = builder.CreateBlockGroup(CHIRFieldAt(fields, 2))
            CHIRApplyBaseInfo(group, CHIRFieldAt(fields, 7), CHIRFieldAt(fields, 8))
            valuesById[CHIRFieldAt(fields, 1)] = group
        }
        for (fields in blockRecords) {
            if (let Some(groupValue) <- valuesById.get(CHIRFieldAt(fields, 2))) {
                if (let Some(group) <- (groupValue as BlockGroup)) {
                    let block = builder.CreateBlock(CHIRFieldAt(fields, 3), group)
                    CHIRApplyBaseInfo(block, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6))
                    let exceptions = ArrayList<ClassType>()
                    for (exceptionText in CHIRWireSplitList(CHIRFieldAt(fields, 4))) {
                        if (let Some(classTy) <- (CHIRParseType(exceptionText, builder, customDefs) as ClassType)) {
                            exceptions.add(classTy)
                        }
                    }
                    if (!exceptions.isEmpty()) {
                        block.SetExceptions(exceptions)
                    }
                    valuesById[CHIRFieldAt(fields, 1)] = block
                }
            }
        }
    }

    private func configureCustomDefs(): Unit {
        for (fields in customRecords) {
            let def = customDefsById.get(CHIRFieldAt(fields, 1)) ?? continue
            CHIRApplyBaseInfo(def, CHIRFieldAt(fields, 14), CHIRFieldAt(fields, 15))
            for (paramText in CHIRWireSplitList(CHIRFieldAt(fields, 6))) {
                if (let Some(genericTy) <- (CHIRParseType(paramText, builder, customDefs) as GenericType)) {
                    def.AddGenericTypeParam(genericTy)
                }
            }
            for (memberText in CHIRWireSplitList(CHIRFieldAt(fields, 7))) {
                if (memberText.isEmpty()) {
                    continue
                }
                let memberFields = CHIRWireSplitFields(memberText)
                let memberTy = CHIRParseType(CHIRFieldAt(memberFields, 1), builder, customDefs)
                def.AddInstanceVar(MemberVarInfo(CHIRFieldAt(memberFields, 0), memberTy,
                    isStatic: CHIRWireToBool(CHIRFieldAt(memberFields, 2)),
                    isReadOnly: CHIRWireToBool(CHIRFieldAt(memberFields, 3))))
            }
            if (let Some(classDef) <- (def as ClassDef)) {
                if (let Some(superValue) <- customDefsById.get(CHIRFieldAt(fields, 10))) {
                    if (let Some(superClass) <- (superValue as ClassDef)) {
                        classDef.SetSuperClassDef(superClass)
                    }
                }
                for (interfaceId in CHIRWireSplitList(CHIRFieldAt(fields, 11))) {
                    if (let Some(interfaceValue) <- customDefsById.get(interfaceId)) {
                        if (let Some(interfaceClass) <- (interfaceValue as ClassDef)) {
                            classDef.AddImplementedInterfaceDef(interfaceClass)
                        }
                    }
                }
            }
            if (let Some(enumDef) <- (def as EnumDef)) {
                for (ctorText in CHIRWireSplitList(CHIRFieldAt(fields, 9))) {
                    if (ctorText.isEmpty()) {
                        continue
                    }
                    let ctorFields = CHIRWireSplitFields(ctorText)
                    enumDef.AddCtor(EnumCtorInfo(CHIRFieldAt(ctorFields, 0),
                        CHIRParseTypeList(CHIRFieldAt(ctorFields, 1), builder, customDefs)))
                }
            }
            if (let Some(extendDef) <- (def as ExtendDef)) {
                let extendedTypeText = CHIRFieldAt(fields, 13)
                if (!extendedTypeText.isEmpty()) {
                    extendDef.extendedType = CHIRParseType(extendedTypeText, builder, customDefs)
                }
            }
            for (extendId in CHIRWireSplitList(CHIRFieldAt(fields, 12))) {
                if (let Some(extendValue) <- customDefsById.get(extendId)) {
                    if (let Some(extendDef) <- (extendValue as ExtendDef)) {
                        def.AddExtend(extendDef)
                    }
                }
            }
        }
    }

    private func configureGlobalsAndFunctions(): Unit {
        for (fields in globalRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(globalVar) <- (value as GlobalVar)) {
                    if (let Some(initValue) <- valuesById.get(CHIRFieldAt(fields, 7))) {
                        globalVar.SetInitializerValue(initValue)
                    }
                    if (let Some(parentDef) <- customDefsById.get(CHIRFieldAt(fields, 9))) {
                        globalVar.SetOuterDeclaredOrExtendedDef(parentDef)
                    }
                }
            }
        }
        for (fields in functionRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(fn) <- (value as Function)) {
                    if (let Some(bodyValue) <- valuesById.get(CHIRFieldAt(fields, 9))) {
                        if (let Some(body) <- (bodyValue as BlockGroup)) {
                            fn.InitBody(body)
                        }
                    }
                    if (let Some(parentDef) <- customDefsById.get(CHIRFieldAt(fields, 11))) {
                        fn.SetOuterDeclaredOrExtendedDef(parentDef)
                        parentDef.AddMethod(fn)
                    }
                    if (let Some(genericValue) <- valuesById.get(CHIRFieldAt(fields, 13))) {
                        if (let Some(genericFn) <- (genericValue as Function)) {
                            fn.SetGenericDecl(genericFn)
                        }
                    }
                    if (let Some(hostValue) <- valuesById.get(CHIRFieldAt(fields, 14))) {
                        if (let Some(hostFn) <- (hostValue as Function)) {
                            fn.SetParamDftValHostFunc(hostFn)
                        }
                    }
                }
            }
        }
    }

    private func createExpressions(): Unit {
        for (fields in expressionRecords) {
            if (let Some(blockValue) <- valuesById.get(CHIRFieldAt(fields, 2))) {
                if (let Some(block) <- (blockValue as Block)) {
                    let expr = createExpression(fields, block)
                    expressionsById[CHIRFieldAt(fields, 1)] = expr
                    CHIRApplyBaseInfo(expr, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12))
                    if (let Some(result) <- expr.GetResult()) {
                        result.SetIdentifier(CHIRFieldAt(fields, 6))
                        valuesById[CHIRFieldAt(fields, 5)] = result
                    }
                }
            }
        }
        for (fields in functionRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(fn) <- (value as Function)) {
                    if (let Some(retValue) <- valuesById.get(CHIRFieldAt(fields, 10))) {
                        if (let Some(retLocal) <- (retValue as LocalVar)) {
                            fn.SetReturnValue(retLocal)
                        }
                    }
                }
            }
        }
    }

    private func createExpression(fields: ArrayList<String>, block: Block): Expression {
        let kind = CHIRExprKindFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 4)))
        let resultTyText = CHIRFieldAt(fields, 7)
        let resultTy: Option<Type> = if (resultTyText.isEmpty()) {
            None
        } else {
            CHIRParseType(resultTyText, builder, customDefs)
        }
        let operands = resolveOperands(CHIRFieldAt(fields, 8))
        if (kind == ExprKind.CONSTANT) {
            let constantTy = if (let Some(ty) <- resultTy) { ty } else { builder.context.GetInvalidTy() }
            return builder.CreateConstant(constantTy, parseLiteral(CHIRFieldAt(fields, 10)), block)
        }
        let successors = resolveBlocks(CHIRFieldAt(fields, 9))
        if (kind == ExprKind.GOTO && !successors.isEmpty()) {
            return builder.CreateGoTo(successors[0], block)
        }
        if (kind == ExprKind.BRANCH && operands.size >= 1 && successors.size >= 2) {
            return builder.CreateBranch(operands[0], successors[0], successors[1], block)
        }
        if (kind == ExprKind.EXIT) {
            let retValue: Option<Value> = if (operands.isEmpty()) { None } else { operands[0] }
            return builder.CreateExit(retValue, block)
        }
        if (ExprKindMajor(kind) == ExprMajorKind.UNARY_EXPR && operands.size >= 1) {
            if (let Some(ty) <- resultTy) {
                return builder.CreateUnaryExpression(kind, ty, operands[0], block)
            }
        }
        if (ExprKindMajor(kind) == ExprMajorKind.BINARY_EXPR && operands.size >= 2) {
            if (let Some(ty) <- resultTy) {
                return builder.CreateBinaryExpression(kind, ty, operands[0], operands[1], block)
            }
        }
        return builder.CreateExpression(kind, resultTy, operands, block)
    }

    private func resolveOperands(value: String): ArrayList<Value> {
        let out = ArrayList<Value>()
        for (id in CHIRWireSplitList(value)) {
            if (let Some(valueRef) <- valuesById.get(id)) {
                out.add(valueRef)
            }
        }
        return out
    }

    private func resolveBlocks(value: String): ArrayList<Block> {
        let out = ArrayList<Block>()
        for (id in CHIRWireSplitList(value)) {
            if (let Some(valueRef) <- valuesById.get(id)) {
                if (let Some(block) <- (valueRef as Block)) {
                    out.add(block)
                }
            }
        }
        return out
    }

    private func configureBlockGroups(): Unit {
        for (fields in blockGroupRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(group) <- (value as BlockGroup)) {
                    if (let Some(ownerValue) <- valuesById.get(CHIRFieldAt(fields, 3))) {
                        if (let Some(ownerFn) <- (ownerValue as Function)) {
                            group.SetOwnerFunc(ownerFn)
                        }
                    }
                    if (let Some(ownerExpr) <- expressionsById.get(CHIRFieldAt(fields, 4))) {
                        group.SetOwnerExpression(ownerExpr)
                    }
                    if (let Some(entryValue) <- valuesById.get(CHIRFieldAt(fields, 5))) {
                        if (let Some(entryBlock) <- (entryValue as Block)) {
                            group.SetEntryBlock(entryBlock)
                        }
                    }
                }
            }
        }
    }

    private func configurePackageFunctions(pkg: Package): Unit {
        if (let Some(fields) <- packageRecord) {
            if (let Some(initValue) <- valuesById.get(CHIRFieldAt(fields, 3))) {
                if (let Some(initFn) <- (initValue as Function)) {
                    pkg.SetPackageInitFunc(initFn)
                }
            }
            if (let Some(literalValue) <- valuesById.get(CHIRFieldAt(fields, 4))) {
                if (let Some(literalFn) <- (literalValue as Function)) {
                    pkg.SetPackageLiteralInitFunc(literalFn)
                }
            }
        }
    }

    private func parseLiteral(value: String): LiteralValue {
        let fields = CHIRWireSplitFields(value)
        let kind = CHIRSafeI64(CHIRFieldAt(fields, 0))
        return match (kind) {
            case 1 => BoolLiteral(CHIRWireToBool(CHIRFieldAt(fields, 1)))
            case 2 => IntLiteral(CHIRSafeI64(CHIRFieldAt(fields, 1)))
            case 3 => FloatLiteral(Float64.parse(CHIRFieldAt(fields, 1)))
            case 4 => RuneLiteral(parseRune(CHIRFieldAt(fields, 1)))
            case 5 => StringLiteral(CHIRFieldAt(fields, 1))
            case 6 => UnitLiteral()
            case _ => NullLiteral()
        }
    }

    private func parseRune(value: String): Rune {
        if (value.isEmpty()) {
            return Rune.parse("\\0")
        }
        return Rune.parse(value)
    }

    private func DeserializeV1(lines: Array<String>): Package {
        var pkg = builder.CreatePackage("<deserialized>")
        var hasPackageLine = false
        let v1Defs = HashMap<String, CustomTypeDef>()
        for (line in lines) {
            if (line.isEmpty() || line == CHIR_TEXT_HEADER_V1) {
                continue
            }
            let parts = line.split("\t")
            if (parts.isEmpty()) {
                continue
            }
            if (parts[0] == "package" && parts.size >= 2) {
                pkg = builder.CreatePackage(UnescapeV1Field(parts[1]))
                hasPackageLine = true
            } else if (parts[0] == "global" && parts.size >= 6) {
                let ownerPackage = if (parts[4].isEmpty()) { pkg.GetName() } else { UnescapeV1Field(parts[4]) }
                let globalVar = builder.CreateGlobalVar(CHIRParseType(UnescapeV1Field(parts[5]), builder, v1Defs),
                    UnescapeV1Field(parts[1]), srcCodeIdentifier: UnescapeV1Field(parts[2]),
                    rawMangledName: UnescapeV1Field(parts[3]), packageName: ownerPackage)
                pkg.AddGlobalVar(globalVar)
            } else if (parts[0] == "function" && parts.size >= 8) {
                let paramTypes = ParseV1TypeList(UnescapeV1Field(parts[7]), builder)
                let returnTy = CHIRParseLegacyType(UnescapeV1Field(parts[6]), builder)
                let ownerPackage = if (parts[4].isEmpty()) { pkg.GetName() } else { UnescapeV1Field(parts[4]) }
                let funcTy = builder.context.GetFuncTy(paramTypes, returnTy)
                let fn = builder.CreateFunction(funcTy, UnescapeV1Field(parts[1]),
                    srcCodeIdentifier: UnescapeV1Field(parts[2]), rawMangledName: UnescapeV1Field(parts[3]),
                    packageName: ownerPackage)
                fn.SetFuncKind(CHIRFuncKindFromIndex(Int64.parse(parts[5])))
                var paramIndex: Int64 = 0
                for (paramTy in paramTypes) {
                    builder.CreateParameter(paramTy, "%arg${paramIndex}", fn)
                    paramIndex++
                }
                pkg.AddGlobalFunc(fn)
            }
        }
        if (!hasPackageLine) {
            return builder.CreatePackage("<deserialized>")
        }
        return pkg
    }
}

func ParseV1TypeList(text: String, builder: CHIRBuilder): ArrayList<Type> {
    let out = ArrayList<Type>()
    if (text.isEmpty()) {
        return out
    }
    for (part in text.split(",")) {
        out.add(CHIRParseLegacyType(part, builder))
    }
    return out
}

func UnescapeV1Field(text: String): String {
    return text.replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
}
