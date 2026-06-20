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
    private let sourceFileRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private var packageRecord: Option<ArrayList<String>> = None

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    private func GetMangleNameFromIdentifier(identifier: String): String {
        if (identifier.startsWith(GLOBAL_VALUE_PREFIX)) {
            return identifier[GLOBAL_VALUE_PREFIX.size..]
        }
        return identifier
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
        registerSourceFiles()
        createCustomDefs(pkg)
        createGlobalVars(pkg)
        createFunctions(pkg)
        createBlockGroupsAndBlocks()
        configureCustomDefs()
        configureGlobalsAndFunctions()
        createExpressions()
        configureExpressionPayloadLinks()
        configureBlockPredecessors()
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
                case "sourceFile" => sourceFileRecords.add(fields)
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

    private func registerSourceFiles(): Unit {
        for (fields in sourceFileRecords) {
            let fileId = CHIRSafeU32(CHIRFieldAt(fields, 1))
            let fileName = CHIRFieldAt(fields, 2)
            if (!fileName.isEmpty()) {
                builder.context.RegisterSourceFileName(fileId, fileName)
            }
        }
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
            let globalVar = builder.CreateGlobalVar(globalTy, GetMangleNameFromIdentifier(CHIRFieldAt(fields, 2)),
                srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                packageName: ownerPackage)
            CHIRApplyAnnoInfo(globalVar.GetAnnoInfo(), CHIRFieldAt(fields, 10))
            CHIRApplyBaseInfo(globalVar, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12), annotationText: CHIRFieldAt(fields, 13))
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
            let fn = builder.CreateFunction(funcTy, GetMangleNameFromIdentifier(CHIRFieldAt(fields, 2)),
                srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                packageName: ownerPackage)
            fn.SetFuncKind(CHIRFuncKindFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 6))))
            CHIRApplyAnnoInfo(fn.GetAnnoInfo(), CHIRFieldAt(fields, 16))
            CHIRApplyBaseInfo(fn, CHIRFieldAt(fields, 17), CHIRFieldAt(fields, 18), annotationText: CHIRFieldAt(fields, 19))
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
            CHIRApplyBaseInfo(param, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6), annotationText: CHIRFieldAt(fields, 7))
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
            CHIRApplyBaseInfo(group, CHIRFieldAt(fields, 7), CHIRFieldAt(fields, 8), annotationText: CHIRFieldAt(fields, 9))
            valuesById[CHIRFieldAt(fields, 1)] = group
        }
        for (fields in blockRecords) {
            if (let Some(groupValue) <- valuesById.get(CHIRFieldAt(fields, 2))) {
                if (let Some(group) <- (groupValue as BlockGroup)) {
                    let block = builder.CreateBlock(CHIRFieldAt(fields, 3), group)
                    CHIRApplyBaseInfo(block, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6), annotationText: CHIRFieldAt(fields, 8))
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
            CHIRApplyBaseInfo(def, CHIRFieldAt(fields, 14), CHIRFieldAt(fields, 15), annotationText: CHIRFieldAt(fields, 16))
            if (!CHIRFieldAt(fields, 17).isEmpty()) {
                def.SetSrcCodeIdentifier(CHIRFieldAt(fields, 17))
            }
            CHIRApplyAnnoInfo(def.GetAnnoInfo(), CHIRFieldAt(fields, 18))
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
                let memberVar = MemberVarInfo(CHIRFieldAt(memberFields, 0), memberTy,
                    isStatic: CHIRWireToBool(CHIRFieldAt(memberFields, 2)),
                    isReadOnly: CHIRWireToBool(CHIRFieldAt(memberFields, 3)),
                    rawMangledName: CHIRFieldAt(memberFields, 4))
                CHIRApplyAttributeInfo(memberVar.attributeInfo, CHIRFieldAt(memberFields, 5))
                if (!CHIRFieldAt(memberFields, 6).isEmpty()) {
                    memberVar.loc = CHIRParseDebugLocation(CHIRFieldAt(memberFields, 6))
                }
                CHIRApplyAnnoInfo(memberVar.annoInfo, CHIRFieldAt(memberFields, 7))
                if (let Some(initValue) <- valuesById.get(CHIRFieldAt(memberFields, 8))) {
                    if (let Some(initFn) <- (initValue as Function)) {
                        memberVar.initializerFunc = initFn
                    }
                }
                if (let Some(outerDef) <- customDefsById.get(CHIRFieldAt(memberFields, 9))) {
                    memberVar.outerDef = outerDef
                }
                def.AddInstanceVar(memberVar)
            }
            if (let Some(classDef) <- (def as ClassDef)) {
                if (let Some(superValue) <- customDefsById.get(CHIRFieldAt(fields, 10))) {
                    if (let Some(superClass) <- (superValue as ClassDef)) {
                        classDef.SetSuperClassDef(superClass)
                    }
                }
                if (let Some(superTy) <- (CHIRParseType(CHIRFieldAt(fields, 23), builder, customDefs) as ClassType)) {
                    classDef.SetSuperClassTy(superTy)
                }
                for (interfaceId in CHIRWireSplitList(CHIRFieldAt(fields, 11))) {
                    if (let Some(interfaceValue) <- customDefsById.get(interfaceId)) {
                        if (let Some(interfaceClass) <- (interfaceValue as ClassDef)) {
                            classDef.AddImplementedInterfaceDef(interfaceClass)
                        }
                    }
                }
                for (interfaceTyText in CHIRWireSplitList(CHIRFieldAt(fields, 22))) {
                    if (let Some(interfaceTy) <- (CHIRParseType(interfaceTyText, builder, customDefs) as ClassType)) {
                        classDef.AddImplementedInterfaceTy(interfaceTy)
                    }
                }
            }
            if (let Some(enumDef) <- (def as EnumDef)) {
                enumDef.SetNonExhaustive(CHIRWireToBool(CHIRFieldAt(fields, 25)))
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
            if (let Some(structDef) <- (def as StructDef)) {
                if (!CHIRFieldAt(fields, 24).isEmpty()) {
                    structDef.SetCStruct(CHIRWireToBool(CHIRFieldAt(fields, 24)))
                }
            }
            for (extendId in CHIRWireSplitList(CHIRFieldAt(fields, 12))) {
                if (let Some(extendValue) <- customDefsById.get(extendId)) {
                    if (let Some(extendDef) <- (extendValue as ExtendDef)) {
                        def.AddExtend(extendDef)
                    }
                }
            }
            for (staticVarId in CHIRWireSplitList(CHIRFieldAt(fields, 19))) {
                if (let Some(staticVarValue) <- valuesById.get(staticVarId)) {
                    if (let Some(staticVar) <- (staticVarValue as GlobalVar)) {
                        def.AddStaticMemberVar(staticVar)
                    }
                }
            }
            if (let Some(initFuncValue) <- valuesById.get(CHIRFieldAt(fields, 20))) {
                if (let Some(initFunc) <- (initFuncValue as Function)) {
                    def.SetVarInitializationFunc(initFunc)
                }
            }
            if (let Some(genericDecl) <- customDefsById.get(CHIRFieldAt(fields, 21))) {
                def.SetGenericDecl(genericDecl)
            }
        }
    }

    private func configureGlobalsAndFunctions(): Unit {
        for (fields in globalRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(globalVar) <- (value as GlobalVar)) {
                    if (let Some(initValue) <- valuesById.get(CHIRFieldAt(fields, 7))) {
                        if (let Some(initFunc) <- (initValue as Function)) {
                            globalVar.SetInitFunc(initFunc)
                        } else {
                            globalVar.SetInitializerValue(initValue)
                        }
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
                    CHIRApplyBaseInfo(expr, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12), annotationText: CHIRFieldAt(fields, 14))
                    if (let Some(result) <- expr.GetResult()) {
                        configureExpressionResult(result, fields)
                        valuesById[CHIRFieldAt(fields, 5)] = result
                    }
                    configureLambdaParameters(expr, CHIRFieldAt(fields, 20))
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

    private func configureExpressionResult(result: LocalVar, fields: ArrayList<String>): Unit {
        result.SetIdentifier(CHIRFieldAt(fields, 6))
        result.SetSrcCodeIdentifier(CHIRFieldAt(fields, 15))
        if (!CHIRFieldAt(fields, 16).isEmpty()) {
            result.SetRetValue(CHIRWireToBool(CHIRFieldAt(fields, 16)))
        }
        CHIRApplyBaseInfo(result, CHIRFieldAt(fields, 17), CHIRFieldAt(fields, 18),
            annotationText: CHIRFieldAt(fields, 19))
    }

    private func configureExpressionPayloadLinks(): Unit {
        for (fields in expressionRecords) {
            let payload = CHIRWireSplitFields(CHIRFieldAt(fields, 21))
            if (CHIRFieldAt(payload, 0) != "lambda") {
                continue
            }
            if (let Some(expr) <- expressionsById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(retValue) <- valuesById.get(CHIRFieldAt(payload, 6))) {
                        if (let Some(retLocal) <- (retValue as LocalVar)) {
                            lambdaExpr.SetReturnValue(retLocal)
                        }
                    }
                    if (let Some(hostExpr) <- expressionsById.get(CHIRFieldAt(payload, 8))) {
                        if (let Some(hostLambda) <- (hostExpr as Lambda)) {
                            lambdaExpr.SetParamDftValHostFunc(hostLambda)
                        }
                    }
                }
            }
        }
    }

    private func configureLambdaParameters(expr: Expression, value: String): Unit {
        if (value.isEmpty()) {
            return
        }
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            for (item in CHIRWireSplitList(value)) {
                if (item.isEmpty()) {
                    continue
                }
                let paramFields = CHIRWireSplitFields(item)
                let paramTy = CHIRParseType(CHIRFieldAt(paramFields, 3), builder, customDefs)
                let param = Parameter(paramTy, CHIRFieldAt(paramFields, 1), lambdaExpr)
                builder.context.RegisterValue(param)
                param.SetSrcCodeIdentifier(CHIRFieldAt(paramFields, 2))
                CHIRApplyAnnoInfo(param.GetAnnoInfo(), CHIRFieldAt(paramFields, 4))
                CHIRApplyBaseInfo(param, CHIRFieldAt(paramFields, 5), CHIRFieldAt(paramFields, 6),
                    annotationText: CHIRFieldAt(paramFields, 7))
                valuesById[CHIRFieldAt(paramFields, 0)] = param
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
        let blockGroups = resolveBlockGroups(CHIRFieldAt(fields, 13))
        let successors = resolveBlocks(CHIRFieldAt(fields, 9))
        let payload = CHIRWireSplitFields(CHIRFieldAt(fields, 21))
        if (kind == ExprKind.CONSTANT) {
            let constantTy = if (let Some(ty) <- resultTy) { ty } else { builder.context.GetInvalidTy() }
            return builder.CreateConstant(constantTy, parseLiteral(CHIRFieldAt(fields, 10)), block)
        }
        if (let Some(concreteExpr) <- createPayloadExpression(kind, resultTy, operands, blockGroups, successors,
            payload, block)) {
            return concreteExpr
        }
        if (kind == ExprKind.LAMBDA && !blockGroups.isEmpty()) {
            return createLambdaExpression(operands, blockGroups[0], block, resultTy)
        }
        if (kind == ExprKind.GOTO && !successors.isEmpty()) {
            return builder.CreateGoTo(successors[0], block)
        }
        if (kind == ExprKind.BRANCH && operands.size >= 1 && successors.size >= 2) {
            return builder.CreateBranch(operands[0], successors[0], successors[1], block)
        }
        if (kind == ExprKind.MULTIBRANCH && operands.size >= 1 && !successors.isEmpty()) {
            let caseBlocks = blocksAfterFirst(successors)
            let caseVals = CHIRParseUInt64List(CHIRFieldAt(payload, 1))
            if (caseVals.size == caseBlocks.size) {
                return builder.CreateMultiBranch(operands[0], successors[0], caseVals, caseBlocks, block)
            }
        }
        if (kind == ExprKind.EXIT) {
            let retValue: Option<Value> = if (operands.isEmpty()) { None } else { operands[0] }
            return builder.CreateExit(retValue, block)
        }
        if (kind == ExprKind.RAISE_EXCEPTION && !operands.isEmpty()) {
            if (!successors.isEmpty()) {
                return builder.CreateRaiseException(operands[0], successors[0], block)
            }
            return builder.CreateRaiseException(operands[0], block)
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
        return createGenericExpression(kind, resultTy, operands, blockGroups, block)
    }

    private func createPayloadExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        blockGroups: ArrayList<BlockGroup>, successors: ArrayList<Block>, payload: ArrayList<String>,
        block: Block): Option<Expression> {
        if (payload.isEmpty()) {
            return None
        }
        if (CHIRFieldAt(payload, 0).isEmpty()) {
            return None
        }
        if (kind == ExprKind.BRANCH && operands.size >= 1 && successors.size >= 2 && CHIRFieldAt(payload, 0) == "branch") {
            let branch = builder.CreateBranch(operands[0], successors[0], successors[1], block)
            branch.SetSourceExpr(CHIRSourceExprFromIndex(CHIRSafeI64(CHIRFieldAt(payload, 1))))
            return branch
        }
        if (kind == ExprKind.INT_OP_WITH_EXCEPTION && !operands.isEmpty() && successors.size >= 2) {
            let opKind = CHIRExprKindFromIndex(CHIRSafeI64(CHIRFieldAt(payload, 1)))
            let resultTyValue = resultTypeOrInvalid(resultTy)
            if (operands.size >= 2) {
                return builder.CreateBinaryIntOpWithException(resultTyValue, opKind, operands[0], operands[1],
                    successors[0], successors[1], block)
            }
            return builder.CreateUnaryIntOpWithException(resultTyValue, opKind, operands[0], successors[0],
                successors[1], block)
        }
        if ((kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) &&
            CHIRFieldAt(payload, 0) == "allocate") {
            let allocatedTy = CHIRParseType(CHIRFieldAt(payload, 1), builder, customDefs)
            if (kind == ExprKind.ALLOCATE_WITH_EXCEPTION && successors.size >= 2) {
                return builder.CreateAllocateWithException(resultTypeOrInvalid(resultTy), allocatedTy, successors[0],
                    successors[1], block)
            }
            if (kind == ExprKind.ALLOCATE) {
                return builder.CreateAllocate(resultTypeOrInvalid(resultTy), allocatedTy, block)
            }
        }
        if (kind == ExprKind.GET_ELEMENT_REF && !operands.isEmpty()) {
            if (CHIRFieldAt(payload, 0) == "indexPath" && operands.size == 1) {
                return builder.CreateGetElementRef(resultTypeOrInvalid(resultTy), operands[0],
                    CHIRParseUInt64List(CHIRFieldAt(payload, 1)), block)
            }
            return builder.CreateDynamicElementRef(resultTypeOrInvalid(resultTy), operands[0],
                valuesAfterFirst(operands), block)
        }
        if (kind == ExprKind.GET_ELEMENT_BY_NAME && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "namePath") {
            return builder.CreateGetElementByName(resultTypeOrInvalid(resultTy), operands[0],
                CHIRWireSplitList(CHIRFieldAt(payload, 1)), block)
        }
        if (kind == ExprKind.STORE_ELEMENT_REF && operands.size >= 2 && CHIRFieldAt(payload, 0) == "indexPath") {
            return builder.CreateStoreElementRef(operands[0], operands[1], CHIRParseUInt64List(CHIRFieldAt(payload, 1)),
                block)
        }
        if (kind == ExprKind.STORE_ELEMENT_BY_NAME && operands.size >= 2 && CHIRFieldAt(payload, 0) == "namePath") {
            return builder.CreateStoreElementByName(operands[0], operands[1], CHIRWireSplitList(CHIRFieldAt(payload, 1)),
                block)
        }
        if ((kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) && !operands.isEmpty() &&
            CHIRFieldAt(payload, 0) == "apply") {
            return createApplyExpression(kind, resultTy, operands, successors, payload, block)
        }
        if ((kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC || kind == ExprKind.INVOKE_WITH_EXCEPTION ||
            kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION) && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "invoke") {
            return createInvokeExpression(kind, resultTy, operands, successors, payload, block)
        }
        if (kind == ExprKind.INSTANCEOF && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "instanceOf") {
            return builder.CreateInstanceOf(resultTypeOrInvalid(resultTy), operands[0],
                CHIRParseType(CHIRFieldAt(payload, 1), builder, customDefs), block)
        }
        if (kind == ExprKind.GET_INSTANTIATE_VALUE && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "instantiate") {
            return builder.CreateGetInstantiateValue(resultTypeOrInvalid(resultTy), operands[0],
                CHIRParseTypeList(CHIRFieldAt(payload, 1), builder, customDefs), block)
        }
        if (kind == ExprKind.GET_RTTI_STATIC && CHIRFieldAt(payload, 0) == "rttiStatic") {
            return builder.CreateGetRTTIStatic(resultTypeOrInvalid(resultTy),
                CHIRParseType(CHIRFieldAt(payload, 1), builder, customDefs), block)
        }
        if (kind == ExprKind.FIELD && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "indexPath") {
            return builder.CreateField(resultTypeOrInvalid(resultTy), operands[0],
                CHIRParseUInt64List(CHIRFieldAt(payload, 1)), block)
        }
        if (kind == ExprKind.FIELD_BY_NAME && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "namePath") {
            return builder.CreateFieldByName(resultTypeOrInvalid(resultTy), operands[0],
                CHIRWireSplitList(CHIRFieldAt(payload, 1)), block)
        }
        if ((kind == ExprKind.RAW_ARRAY_ALLOCATE || kind == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION) &&
            !operands.isEmpty() && CHIRFieldAt(payload, 0) == "rawArrayAllocate") {
            let elementTy = CHIRParseType(CHIRFieldAt(payload, 1), builder, customDefs)
            if (kind == ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION && successors.size >= 2) {
                return builder.CreateRawArrayAllocateWithException(resultTypeOrInvalid(resultTy), elementTy, operands[0],
                    successors[0], successors[1], block)
            }
            if (kind == ExprKind.RAW_ARRAY_ALLOCATE) {
                return builder.CreateRawArrayAllocate(resultTypeOrInvalid(resultTy), elementTy, operands[0], block)
            }
        }
        if ((kind == ExprKind.INTRINSIC || kind == ExprKind.INTRINSIC_WITH_EXCEPTION) &&
            CHIRFieldAt(payload, 0) == "intrinsic") {
            return createIntrinsicExpression(kind, resultTy, operands, successors, payload, block)
        }
        if (kind == ExprKind.DEBUGEXPR && !operands.isEmpty() && CHIRFieldAt(payload, 0) == "debug") {
            return builder.CreateDebug(resultTypeOrInvalid(resultTy), operands[0], CHIRFieldAt(payload, 1), block)
        }
        if ((kind == ExprKind.SPAWN || kind == ExprKind.SPAWN_WITH_EXCEPTION) && !operands.isEmpty() &&
            CHIRFieldAt(payload, 0) == "spawn") {
            return createSpawnExpression(kind, resultTy, operands, successors, payload, block)
        }
        if ((kind == ExprKind.FORIN_RANGE || kind == ExprKind.FORIN_ITER || kind == ExprKind.FORIN_CLOSED_RANGE) &&
            operands.size >= 2 && blockGroups.size >= 3) {
            return createForInExpression(kind, resultTy, operands, blockGroups, block)
        }
        if (kind == ExprKind.LAMBDA && !blockGroups.isEmpty()) {
            return createLambdaExpressionFromPayload(operands, blockGroups[0], block, resultTy, payload)
        }
        return None
    }

    private func createApplyExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        successors: ArrayList<Block>, payload: ArrayList<String>, block: Block): Option<Expression> {
        let callContext = FuncCallContext(args: valuesAfterFirst(operands),
            instTypeArgs: CHIRParseTypeList(CHIRFieldAt(payload, 1), builder, customDefs),
            thisType: parseOptionalType(CHIRFieldAt(payload, 2)))
        if (kind == ExprKind.APPLY_WITH_EXCEPTION && successors.size >= 2) {
            return builder.CreateApplyWithException(resultTypeOrInvalid(resultTy), operands[0], callContext,
                successors[0], successors[1], block)
        }
        if (kind == ExprKind.APPLY) {
            let applyExpr = builder.CreateApply(resultTypeOrInvalid(resultTy), operands[0], callContext, block)
            if (CHIRWireToBool(CHIRFieldAt(payload, 3))) {
                applyExpr.SetSuperCall()
            }
            return applyExpr
        }
        return None
    }

    private func createInvokeExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        successors: ArrayList<Block>, payload: ArrayList<String>, block: Block): Option<Expression> {
        let funcContext = FuncCallContext(args: valuesAfterFirst(operands),
            instTypeArgs: CHIRParseTypeList(CHIRFieldAt(payload, 1), builder, customDefs),
            thisType: parseOptionalType(CHIRFieldAt(payload, 2)))
        let methodContext = FuncSigInfo(parseFuncTypeOrDefault(CHIRFieldAt(payload, 4)), funcName: CHIRFieldAt(payload, 3),
            genericTypeParams: CHIRParseGenericTypeList(CHIRFieldAt(payload, 5), builder, customDefs))
        let invokeContext = InvokeCallContext(operands[0], funcContext, methodContext)
        if (kind == ExprKind.INVOKESTATIC) {
            let invokeExpr = builder.CreateInvokeStatic(resultTypeOrInvalid(resultTy), invokeContext, block)
            applyVirtualMethodOffset(invokeExpr, CHIRFieldAt(payload, 6))
            return invokeExpr
        }
        if (kind == ExprKind.INVOKE) {
            let invokeExpr = builder.CreateInvoke(resultTypeOrInvalid(resultTy), invokeContext, block)
            applyVirtualMethodOffset(invokeExpr, CHIRFieldAt(payload, 6))
            return invokeExpr
        }
        if (kind == ExprKind.INVOKESTATIC_WITH_EXCEPTION && successors.size >= 2) {
            let invokeExpr = builder.CreateInvokeStaticWithException(resultTypeOrInvalid(resultTy), invokeContext,
                successors[0], successors[1], block)
            applyVirtualMethodOffset(invokeExpr, CHIRFieldAt(payload, 6))
            return invokeExpr
        }
        if (kind == ExprKind.INVOKE_WITH_EXCEPTION && successors.size >= 2) {
            let invokeExpr = builder.CreateInvokeWithException(resultTypeOrInvalid(resultTy), invokeContext,
                successors[0], successors[1], block)
            applyVirtualMethodOffset(invokeExpr, CHIRFieldAt(payload, 6))
            return invokeExpr
        }
        return None
    }

    private func createIntrinsicExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        successors: ArrayList<Block>, payload: ArrayList<String>, block: Block): Option<Expression> {
        let callContext = IntrisicCallContext(kind: CHIRIntrinsicKindFromName(CHIRFieldAt(payload, 1)),
            args: operands, instTypeArgs: CHIRParseTypeList(CHIRFieldAt(payload, 2), builder, customDefs))
        if (kind == ExprKind.INTRINSIC_WITH_EXCEPTION && successors.size >= 2) {
            return builder.CreateIntrinsicWithException(resultTypeOrInvalid(resultTy), callContext, successors[0],
                successors[1], block)
        }
        if (kind == ExprKind.INTRINSIC) {
            return builder.CreateIntrinsic(resultTypeOrInvalid(resultTy), callContext, block)
        }
        return None
    }

    private func createSpawnExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        successors: ArrayList<Block>, payload: ArrayList<String>, block: Block): Option<Expression> {
        if (kind == ExprKind.SPAWN_WITH_EXCEPTION && successors.size >= 2) {
            let spawnExpr = if (operands.size >= 2) {
                builder.CreateSpawnWithException(resultTypeOrInvalid(resultTy), operands[0], operands[1],
                    successors[0], successors[1], block)
            } else {
                builder.CreateSpawnWithException(resultTypeOrInvalid(resultTy), operands[0], successors[0],
                    successors[1], block)
            }
            applySpawnExecuteClosure(spawnExpr, CHIRFieldAt(payload, 1))
            return spawnExpr
        }
        if (kind == ExprKind.SPAWN) {
            let spawnExpr = if (operands.size >= 2) {
                builder.CreateSpawn(resultTypeOrInvalid(resultTy), operands[0], operands[1], block)
            } else {
                builder.CreateSpawn(resultTypeOrInvalid(resultTy), operands[0], block)
            }
            applySpawnExecuteClosure(spawnExpr, CHIRFieldAt(payload, 1))
            return spawnExpr
        }
        return None
    }

    private func createForInExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        blockGroups: ArrayList<BlockGroup>, block: Block): Option<Expression> {
        let forInExpr = if (kind == ExprKind.FORIN_RANGE) {
            builder.CreateForInRange(resultTypeOrInvalid(resultTy), operands[0], operands[1], block)
        } else if (kind == ExprKind.FORIN_ITER) {
            builder.CreateForInIter(resultTypeOrInvalid(resultTy), operands[0], operands[1], block)
        } else {
            builder.CreateForInClosedRange(resultTypeOrInvalid(resultTy), operands[0], operands[1], block)
        }
        forInExpr.InitBlockGroups(blockGroups[0], blockGroups[1], blockGroups[2])
        return forInExpr
    }

    private func createLambdaExpressionFromPayload(operands: ArrayList<Value>, body: BlockGroup, block: Block,
        resultTy: Option<Type>, payload: ArrayList<String>): Option<Expression> {
        if (CHIRFieldAt(payload, 0) != "lambda") {
            return None
        }
        if (let Some(funcTy) <- (CHIRParseType(CHIRFieldAt(payload, 1), builder, customDefs) as FuncType)) {
            let lambdaExpr = builder.CreateLambda(resultTypeOrInvalid(resultTy), funcTy, block,
                isLocalFunc: CHIRWireToBool(CHIRFieldAt(payload, 2)), identifier: CHIRFieldAt(payload, 3),
                srcCodeIdentifier: CHIRFieldAt(payload, 4),
                genericTypeParams: CHIRParseGenericTypeList(CHIRFieldAt(payload, 5), builder, customDefs))
            for (operand in operands) {
                lambdaExpr.AppendOperand(operand)
            }
            lambdaExpr.InitBody(body)
            if (CHIRWireToBool(CHIRFieldAt(payload, 7))) {
                lambdaExpr.SetCompileTimeValue()
            }
            return lambdaExpr
        }
        return None
    }

    private func applyVirtualMethodOffset(expr: DynamicDispatch, value: String): Unit {
        if (!value.isEmpty()) {
            expr.SetVirtualMethodOffset(CHIRSafeU64(value))
        }
    }

    private func applyVirtualMethodOffset(expr: DynamicDispatchWithException, value: String): Unit {
        if (!value.isEmpty()) {
            expr.SetVirtualMethodOffset(CHIRSafeU64(value))
        }
    }

    private func applySpawnExecuteClosure(expr: Spawn, value: String): Unit {
        if (let Some(fnValue) <- valuesById.get(value)) {
            if (let Some(fn) <- (fnValue as Function)) {
                expr.SetExecuteClosure(fn)
            }
        }
    }

    private func applySpawnExecuteClosure(expr: SpawnWithException, value: String): Unit {
        if (let Some(fnValue) <- valuesById.get(value)) {
            if (let Some(fn) <- (fnValue as Function)) {
                expr.SetExecuteClosure(fn)
            }
        }
    }

    private func resultTypeOrInvalid(resultTy: Option<Type>): Type {
        if (let Some(ty) <- resultTy) {
            return ty
        }
        return builder.context.GetInvalidTy()
    }

    private func parseOptionalType(value: String): Option<Type> {
        if (value.isEmpty()) {
            return None
        }
        return CHIRParseType(value, builder, customDefs)
    }

    private func parseFuncTypeOrDefault(value: String): FuncType {
        if (let Some(funcTy) <- (CHIRParseType(value, builder, customDefs) as FuncType)) {
            return funcTy
        }
        return builder.context.GetFuncTy(ArrayList<Type>(), builder.context.GetInvalidTy())
    }

    private func valuesAfterFirst(values: ArrayList<Value>): ArrayList<Value> {
        let out = ArrayList<Value>()
        var idx: Int64 = 1
        while (idx < values.size) {
            out.add(values[idx])
            idx++
        }
        return out
    }

    private func blocksAfterFirst(values: ArrayList<Block>): ArrayList<Block> {
        let out = ArrayList<Block>()
        var idx: Int64 = 1
        while (idx < values.size) {
            out.add(values[idx])
            idx++
        }
        return out
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

    private func resolveBlockGroups(value: String): ArrayList<BlockGroup> {
        let out = ArrayList<BlockGroup>()
        for (id in CHIRWireSplitList(value)) {
            if (let Some(valueRef) <- valuesById.get(id)) {
                if (let Some(group) <- (valueRef as BlockGroup)) {
                    out.add(group)
                }
            }
        }
        return out
    }

    private func createLambdaExpression(operands: ArrayList<Value>, body: BlockGroup, block: Block,
        resultTy: Option<Type>): Expression {
        let expr = Lambda(operands, body, block)
        block.AppendExpression(expr)
        builder.context.RegisterExpression(expr)
        attachResult(expr, resultTy)
        return expr
    }

    private func createGenericExpression(kind: ExprKind, resultTy: Option<Type>, operands: ArrayList<Value>,
        blockGroups: ArrayList<BlockGroup>, block: Block): Expression {
        let expr = Expression(kind, operands, blockGroups, block)
        block.AppendExpression(expr)
        builder.context.RegisterExpression(expr)
        attachResult(expr, resultTy)
        return expr
    }

    private func attachResult(expr: Expression, resultTy: Option<Type>): Unit {
        if (let Some(ty) <- resultTy) {
            builder.CreateLocalVar(ty, "%${builder.context.GetAllNodesNum()}", expr)
        }
    }

    private func configureBlockPredecessors(): Unit {
        for (fields in blockRecords) {
            let predecessorText = CHIRFieldAt(fields, 7)
            if (predecessorText.isEmpty()) {
                continue
            }
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(block) <- (value as Block)) {
                    block.ClearPredecessorsOnly()
                    for (predecessor in resolveBlocks(predecessorText)) {
                        block.AddPredecessor(predecessor)
                    }
                }
            }
        }
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
                    GetMangleNameFromIdentifier(UnescapeV1Field(parts[1])),
                    srcCodeIdentifier: UnescapeV1Field(parts[2]), rawMangledName: UnescapeV1Field(parts[3]),
                    packageName: ownerPackage)
                pkg.AddGlobalVar(globalVar)
            } else if (parts[0] == "function" && parts.size >= 8) {
                let paramTypes = ParseV1TypeList(UnescapeV1Field(parts[7]), builder)
                let returnTy = CHIRParseLegacyType(UnescapeV1Field(parts[6]), builder)
                let ownerPackage = if (parts[4].isEmpty()) { pkg.GetName() } else { UnescapeV1Field(parts[4]) }
                let funcTy = builder.context.GetFuncTy(paramTypes, returnTy)
                let fn = builder.CreateFunction(funcTy, GetMangleNameFromIdentifier(UnescapeV1Field(parts[1])),
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
