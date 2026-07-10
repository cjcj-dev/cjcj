package cjcj::chir

import std.collection.*
import std.convert.*
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

private func CHIRExprKindToExprKind(kind: UInt8): (ExprKind, Bool) {
    return match (kind) {
        case 1u8 => (ExprKind.GOTO, false)
        case 2u8 => (ExprKind.BRANCH, false)
        case 3u8 => (ExprKind.MULTIBRANCH, false)
        case 4u8 => (ExprKind.EXIT, false)
        case 5u8 => (ExprKind.APPLY_WITH_EXCEPTION, true)
        case 6u8 => (ExprKind.INVOKE_WITH_EXCEPTION, true)
        case 7u8 => (ExprKind.INTRINSIC_WITH_EXCEPTION, true)
        case 8u8 => (ExprKind.RAISE_EXCEPTION, false)
        case 9u8 => (ExprKind.SPAWN_WITH_EXCEPTION, true)
        case 10u8 => (ExprKind.TYPECAST_WITH_EXCEPTION, true)
        case 11u8 => (ExprKind.ALLOCATE_WITH_EXCEPTION, true)
        case 12u8 => (ExprKind.RAW_ARRAY_ALLOCATE_WITH_EXCEPTION, true)
        case 13u8 => (ExprKind.NEG, true)
        case 14u8 => (ExprKind.ADD, true)
        case 15u8 => (ExprKind.SUB, true)
        case 16u8 => (ExprKind.MUL, true)
        case 17u8 => (ExprKind.DIV, true)
        case 18u8 => (ExprKind.MOD, true)
        case 19u8 => (ExprKind.EXP, true)
        case 20u8 => (ExprKind.LSHIFT, true)
        case 21u8 => (ExprKind.RSHIFT, true)
        case 22u8 => (ExprKind.NEG, false)
        case 23u8 => (ExprKind.NOT, false)
        case 24u8 => (ExprKind.BITNOT, false)
        case 25u8 => (ExprKind.ADD, false)
        case 26u8 => (ExprKind.SUB, false)
        case 27u8 => (ExprKind.MUL, false)
        case 28u8 => (ExprKind.DIV, false)
        case 29u8 => (ExprKind.MOD, false)
        case 30u8 => (ExprKind.EXP, false)
        case 31u8 => (ExprKind.LSHIFT, false)
        case 32u8 => (ExprKind.RSHIFT, false)
        case 33u8 => (ExprKind.BITAND, false)
        case 34u8 => (ExprKind.BITOR, false)
        case 35u8 => (ExprKind.BITXOR, false)
        case 36u8 => (ExprKind.LT, false)
        case 37u8 => (ExprKind.GT, false)
        case 38u8 => (ExprKind.LE, false)
        case 39u8 => (ExprKind.GE, false)
        case 40u8 => (ExprKind.EQUAL, false)
        case 41u8 => (ExprKind.NOTEQUAL, false)
        case 42u8 => (ExprKind.AND, false)
        case 43u8 => (ExprKind.OR, false)
        case 44u8 => (ExprKind.TYPECAST, false)
        case 45u8 => (ExprKind.BOX, false)
        case 46u8 => (ExprKind.UNBOX, false)
        case 47u8 => (ExprKind.UNBOX_TO_REF, false)
        case 48u8 => (ExprKind.TYPECAST, false)
        case 49u8 => (ExprKind.TRANSFORM_TO_CONCRETE, false)
        case 50u8 => (ExprKind.TRANSFORM_TO_GENERIC, false)
        case 51u8 => (ExprKind.ALLOCATE, false)
        case 52u8 => (ExprKind.LOAD, false)
        case 53u8 => (ExprKind.STORE, false)
        case 54u8 => (ExprKind.GET_ELEMENT_BY_NAME, false)
        case 55u8 => (ExprKind.GET_ELEMENT_REF, false)
        case 56u8 => (ExprKind.STORE_ELEMENT_BY_NAME, false)
        case 57u8 => (ExprKind.STORE_ELEMENT_REF, false)
        case 58u8 => (ExprKind.FIELD, false)
        case 59u8 => (ExprKind.FIELD_BY_NAME, false)
        case 60u8 => (ExprKind.RAW_ARRAY_ALLOCATE, false)
        case 61u8 => (ExprKind.RAW_ARRAY_LITERAL_INIT, false)
        case 62u8 => (ExprKind.RAW_ARRAY_INIT_BY_VALUE, false)
        case 63u8 => (ExprKind.VARRAY, false)
        case 64u8 => (ExprKind.VARRAY_BUILDER, false)
        case 65u8 => (ExprKind.CONSTANT, false)
        case 66u8 => (ExprKind.DEBUGEXPR, false)
        case 67u8 => (ExprKind.TUPLE, false)
        case 68u8 => (ExprKind.INSTANCEOF, false)
        case 69u8 => (ExprKind.GET_EXCEPTION, false)
        case 70u8 => (ExprKind.SPAWN, false)
        case 71u8 => (ExprKind.LAMBDA, false)
        case 72u8 => (ExprKind.GET_INSTANTIATE_VALUE, false)
        case 73u8 => (ExprKind.APPLY, false)
        case 74u8 => (ExprKind.INVOKE, false)
        case 75u8 => (ExprKind.INTRINSIC, false)
        case 76u8 => (ExprKind.GET_RTTI, false)
        case 77u8 => (ExprKind.GET_RTTI_STATIC, false)
        case _ => (ExprKind.GOTO, false)
    }
}

class CHIRDeserializerImpl {
    private let builder: CHIRBuilder
    private let compilePlatform: Bool
    private let customDefs: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    private let customDefsById: HashMap<String, CustomTypeDef> = HashMap<String, CustomTypeDef>()
    private let valuesById: HashMap<String, Value> = HashMap<String, Value>()
    private let expressionsById: HashMap<String, Expression> = HashMap<String, Expression>()
    private let customRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let literalRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let globalRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let functionRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let blockGroupRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let blockRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let expressionRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private let sourceFileRecords: ArrayList<ArrayList<String>> = ArrayList<ArrayList<String>>()
    private var packageRecord: Option<ArrayList<String>> = None
    private var pool: Option<PackageFormat_CHIRPackage> = None
    private let id2Type: HashMap<UInt32, Type> = HashMap<UInt32, Type>()
    private let id2Value: HashMap<UInt32, Value> = HashMap<UInt32, Value>()
    private let id2Expression: HashMap<UInt32, Expression> = HashMap<UInt32, Expression>()
    private let id2CustomTypeDef: HashMap<UInt32, CustomTypeDef> = HashMap<UInt32, CustomTypeDef>()
    private let genericTypeConfig: ArrayList<(GenericType, PackageFormat_GenericType)> =
        ArrayList<(GenericType, PackageFormat_GenericType)>()

    public init(builder: CHIRBuilder, compilePlatform!: Bool = false) {
        this.builder = builder
        this.compilePlatform = compilePlatform
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
        for (fields in literalRecords) {
            let literalTy = CHIRParseType(CHIRFieldAt(fields, 2), builder, customDefs)
            let literal = Deserialize(literalTy, fields)
            CHIRApplyBaseInfo(literal, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6),
                annotationText: CHIRFieldAt(fields, 7))
            valuesById[CHIRFieldAt(fields, 1)] = literal
        }
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
                case "literal" => literalRecords.add(fields)
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
            let def: CustomTypeDef = if (compilePlatform && kind == "enum") {
                if (let Some(exist) <- pkg.TryGetEnumDef(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
                }
            } else if (compilePlatform && kind == "struct") {
                if (let Some(exist) <- pkg.TryGetStructDef(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
                }
            } else if (compilePlatform && kind == "class") {
                if (let Some(exist) <- pkg.TryGetClassDef(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
                }
            } else if (compilePlatform) {
                if (let Some(exist) <- pkg.TryGetExtendDef(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
                }
            } else {
                CHIRCreateDetachedCustomDef(kind, packageName, identifier, builder, customDefs)
            }
            if (compilePlatform && !def.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                def.EnableAttr(Attribute.DESERIALIZED)
            }
            customDefs[CHIRCustomDefKey(kind, packageName, identifier)] = def
            customDefsById[id] = def
            if (!def.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                if (scope == "import") {
                    addImportedDef(pkg, def)
                } else {
                    addLocalDef(pkg, def)
                }
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
            let identifier = CHIRFieldAt(fields, 2)
            let globalVar: GlobalVar = if (compilePlatform) {
                if (let Some(exist) <- pkg.TryGetGlobalVar(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    let globalTy = CHIRParseType(CHIRFieldAt(fields, 6), builder, customDefs)
                    let ownerPackage = if (CHIRFieldAt(fields, 5).isEmpty()) { pkg.GetName() } else { CHIRFieldAt(fields, 5) }
                    builder.CreateGlobalVar(globalTy, GetMangleNameFromIdentifier(identifier),
                        srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                        packageName: ownerPackage)
                }
            } else {
                let globalTy = CHIRParseType(CHIRFieldAt(fields, 6), builder, customDefs)
                let ownerPackage = if (CHIRFieldAt(fields, 5).isEmpty()) { pkg.GetName() } else { CHIRFieldAt(fields, 5) }
                builder.CreateGlobalVar(globalTy, GetMangleNameFromIdentifier(identifier),
                    srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                    packageName: ownerPackage)
            }
            if (compilePlatform && !globalVar.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                globalVar.EnableAttr(Attribute.DESERIALIZED)
            }
            valuesById[CHIRFieldAt(fields, 1)] = globalVar
            if (!globalVar.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                CHIRApplyAnnoInfo(globalVar.GetAnnoInfo(), CHIRFieldAt(fields, 10))
                CHIRApplyBaseInfo(globalVar, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12),
                    annotationText: CHIRFieldAt(fields, 13))
                if (let Some(linkText) <- globalVar.GetAnnotation("LinkTypeInfo")) {
                    globalVar.SetLinkTypeInfo(LinkTypeInfo.Extract(linkText))
                }
                for (feature in CHIRWireSplitList(CHIRFieldAt(fields, 8))) {
                    if (!feature.isEmpty()) {
                        globalVar.AddFeature(feature)
                    }
                }
                pkg.AddGlobalVar(globalVar)
            }
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
            let identifier = CHIRFieldAt(fields, 2)
            let fn: Function = if (compilePlatform) {
                if (let Some(exist) <- pkg.TryGetGlobalFunc(identifier)) {
                    exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                    exist
                } else {
                    builder.CreateFunction(funcTy, GetMangleNameFromIdentifier(identifier),
                        srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                        packageName: ownerPackage)
                }
            } else {
                builder.CreateFunction(funcTy, GetMangleNameFromIdentifier(identifier),
                    srcCodeIdentifier: CHIRFieldAt(fields, 3), rawMangledName: CHIRFieldAt(fields, 4),
                    packageName: ownerPackage)
            }
            if (compilePlatform && !fn.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                fn.EnableAttr(Attribute.DESERIALIZED)
            }
            valuesById[CHIRFieldAt(fields, 1)] = fn
            if (!fn.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                fn.SetFuncKind(CHIRFuncKindFromIndex(CHIRSafeI64(CHIRFieldAt(fields, 6))))
                CHIRApplyAnnoInfo(fn.GetAnnoInfo(), CHIRFieldAt(fields, 16))
                CHIRApplyBaseInfo(fn, CHIRFieldAt(fields, 17), CHIRFieldAt(fields, 18),
                    annotationText: CHIRFieldAt(fields, 19))
                fn.SetPropLocation(CHIRParseDebugLocation(CHIRFieldAt(fields, 15)))
                fn.SetCFFIWrapper(CHIRWireToBool(CHIRFieldAt(fields, 23)))
                for (feature in CHIRWireSplitList(CHIRFieldAt(fields, 12))) {
                    if (!feature.isEmpty()) {
                        fn.AddFeature(feature)
                    }
                }
                createParameters(fn, CHIRFieldAt(fields, 8))
            }
        }
    }

    private func createParameters(fn: Function, value: String): Unit {
        for (item in CHIRWireSplitList(value)) {
            if (item.isEmpty()) {
                continue
            }
            let fields = CHIRWireSplitFields(item)
            let paramTy = CHIRParseType(CHIRFieldAt(fields, 3), builder, customDefs)
            let param = builder.CreateParameter(paramTy, INVALID_LOCATION, fn)
            param.SetSrcCodeIdentifier(CHIRFieldAt(fields, 2))
            CHIRApplyAnnoInfo(param.GetAnnoInfo(), CHIRFieldAt(fields, 4))
            CHIRApplyBaseInfo(param, CHIRFieldAt(fields, 5), CHIRFieldAt(fields, 6), annotationText: CHIRFieldAt(fields, 7))
            valuesById[CHIRFieldAt(fields, 0)] = param
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
            if (def.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                continue
            }
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
            let genericParamTypes = ArrayList<Type>()
            for (genericParam in def.GetGenericTypeParams()) {
                genericParamTypes.add(genericParam)
            }
            let serializedDefType = CHIRFieldAt(fields, 27)
            let parsedDefType: Option<CustomType> = if (!serializedDefType.isEmpty()) {
                CHIRParseType(serializedDefType, builder, customDefs) as CustomType
            } else if (let Some(structDef) <- (def as StructDef)) {
                builder.context.GetStructTy(structDef, genericParamTypes)
            } else if (let Some(classDef) <- (def as ClassDef)) {
                builder.context.GetClassTy(classDef, genericParamTypes)
            } else if (let Some(enumDef) <- (def as EnumDef)) {
                builder.context.GetEnumTy(enumDef, genericParamTypes)
            } else {
                None
            }
            if (let Some(customTy) <- parsedDefType) {
                def.SetType(customTy)
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
                if (compilePlatform) {
                    memberVar.attributeInfo.Enable(Attribute.DESERIALIZED)
                }
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
                if (let Some(superTy) <- (CHIRParseType(CHIRFieldAt(fields, 23), builder, customDefs) as ClassType)) {
                    classDef.SetSuperClassTy(superTy)
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
            let varInitializationFunc: Option<Function> = match (valuesById.get(CHIRFieldAt(fields, 20))) {
                case Some(value) => value as Function
                case None => None
            }
            def.SetVarInitializationFunc(varInitializationFunc)
            if (let Some(genericDecl) <- customDefsById.get(CHIRFieldAt(fields, 21))) {
                def.SetGenericDecl(genericDecl)
            }
            let vtableInDef = VTableInDef()
            for (item in CHIRWireSplitList(CHIRFieldAt(fields, 26))) {
                if (item.isEmpty()) {
                    continue
                }
                let vtableFields = CHIRWireSplitFields(item)
                if (let Some(srcParentTy) <- (CHIRParseType(CHIRFieldAt(vtableFields, 0), builder, customDefs) as ClassType)) {
                    let virtualMethods = ArrayList<VirtualMethodInfo>()
                    for (methodItem in CHIRWireSplitList(CHIRFieldAt(vtableFields, 1))) {
                        if (methodItem.isEmpty()) {
                            continue
                        }
                        let methodFields = CHIRWireSplitFields(methodItem)
                        let condition = FuncSigInfo(parseFuncTypeOrDefault(CHIRFieldAt(methodFields, 1)),
                            funcName: CHIRFieldAt(methodFields, 0),
                            genericTypeParams: CHIRParseGenericTypeList(CHIRFieldAt(methodFields, 2), builder, customDefs))
                        let funcPtr: Option<Function> = if (let Some(fnValue) <- valuesById.get(CHIRFieldAt(methodFields, 3))) {
                            fnValue as Function
                        } else {
                            None
                        }
                        let attributeInfo = AttributeInfo()
                        CHIRApplyAttributeInfo(attributeInfo, CHIRFieldAt(methodFields, 4))
                        let originalType = parseFuncTypeOrDefault(CHIRFieldAt(methodFields, 5))
                        let parentType = CHIRParseType(CHIRFieldAt(methodFields, 6), builder, customDefs)
                        let returnType = CHIRParseType(CHIRFieldAt(methodFields, 7), builder, customDefs)
                        virtualMethods.add(VirtualMethodInfo(condition, funcPtr, attributeInfo, originalType, parentType,
                            returnType))
                    }
                    vtableInDef.AddNewItemToTypeVTable(srcParentTy, virtualMethods)
                }
            }
            def.SetVTable(vtableInDef)
        }
    }

    private func Deserialize(literalTy: Type, fields: ArrayList<String>): LiteralValue {
        let value = CHIRFieldAt(fields, 4)
        return match (CHIRSafeI64(CHIRFieldAt(fields, 3))) {
            case 0 => builder.CreateLiteralValue(NullLiteral(), literalTy)
            case 1 => builder.CreateLiteralValue(BoolLiteral(CHIRWireToBool(value)), literalTy)
            case 2 => builder.CreateLiteralValue(IntLiteral(CHIRSafeU64(value)), literalTy)
            case 3 => builder.CreateLiteralValue(FloatLiteral(Float64.parse(value)), literalTy)
            case 4 => builder.CreateLiteralValue(RuneLiteral(parseRune(value)), literalTy)
            case 5 => builder.CreateLiteralValue(StringLiteral(value), literalTy)
            case 6 => builder.CreateLiteralValue(UnitLiteral(), literalTy)
            case _ =>
                CJC_ABORT()
                builder.CreateLiteralValue(NullLiteral(), literalTy)
        }
    }

    private func configureGlobalsAndFunctions(): Unit {
        for (fields in globalRecords) {
            if (let Some(value) <- valuesById.get(CHIRFieldAt(fields, 1))) {
                if (let Some(globalVar) <- (value as GlobalVar)) {
                    if (globalVar.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                        continue
                    }
                    if (let Some(initValue) <- valuesById.get(CHIRFieldAt(fields, 7))) {
                        if (let Some(initFunc) <- (initValue as Function)) {
                            globalVar.SetInitFunc(initFunc)
                        } else if (let Some(literal) <- (initValue as LiteralValue)) {
                            globalVar.SetInitializer(literal)
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
                    if (fn.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) {
                        continue
                    }
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
                    if (let Some(rawValue) <- valuesById.get(CHIRFieldAt(fields, 20))) {
                        if (let Some(rawFn) <- (rawValue as Function)) {
                            fn.SetWrappedRawMethod(rawFn)
                        }
                    }
                    if (!CHIRFieldAt(fields, 21).isEmpty()) {
                        if (let Some(srcFuncTy) <- (CHIRParseType(CHIRFieldAt(fields, 21), builder, customDefs) as FuncType)) {
                            fn.SetOverrideSrcFuncType(srcFuncTy)
                        }
                    }
                    if (!CHIRFieldAt(fields, 22).isEmpty()) {
                        fn.SetLinkTypeInfo(LinkTypeInfo.Extract(CHIRFieldAt(fields, 22)))
                    } else if (let Some(linkText) <- fn.GetAnnotation("LinkTypeInfo")) {
                        fn.SetLinkTypeInfo(LinkTypeInfo.Extract(linkText))
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
                    CHIRApplyBaseInfo(expr, CHIRFieldAt(fields, 11), CHIRFieldAt(fields, 12),
                        annotationText: CHIRFieldAt(fields, 14))
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
        if (kind == ExprKind.GOTO) {
            CJC_ASSERT(operands.size == 1)
            if (let Some(target) <- (operands[0] as Block)) {
                return builder.CreateGoTo(target, block)
            }
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
            if (operands.size == 2) {
                if (let Some(exceptionBlock) <- (operands[1] as Block)) {
                    return builder.CreateRaiseException(operands[0], exceptionBlock, block)
                }
            }
            return builder.CreateRaiseException(operands[0], block)
        }
        if (kind == ExprKind.BOX) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateBox(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.GET_EXCEPTION) {
            return builder.CreateGetException(resultTypeOrInvalid(resultTy), block)
        }
        if (kind == ExprKind.GET_RTTI) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateGetRTTI(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.LOAD) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateLoad(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.RAW_ARRAY_INIT_BY_VALUE) {
            CJC_ASSERT(operands.size == 3)
            return builder.CreateRawArrayInitByValue(resultTypeOrInvalid(resultTy), operands[0], operands[1],
                operands[2], block)
        }
        if (kind == ExprKind.RAW_ARRAY_LITERAL_INIT) {
            CJC_ASSERT(!operands.isEmpty())
            return builder.CreateRawArrayLiteralInit(resultTypeOrInvalid(resultTy), operands[0], valuesAfterFirst(operands),
                block)
        }
        if (kind == ExprKind.STORE) {
            CJC_ASSERT(operands.size == 2)
            return builder.CreateStore(operands[0], operands[1], block)
        }
        if (kind == ExprKind.TRANSFORM_TO_CONCRETE) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateTransformToConcrete(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.TRANSFORM_TO_GENERIC) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateTransformToGeneric(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.TUPLE) {
            return builder.CreateTuple(resultTypeOrInvalid(resultTy), operands, block)
        }
        if (kind == ExprKind.UNBOX) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateUnBox(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.UNBOX_TO_REF) {
            CJC_ASSERT(operands.size == 1)
            return builder.CreateUnBoxToRef(resultTypeOrInvalid(resultTy), operands[0], block)
        }
        if (kind == ExprKind.VARRAY) {
            CJC_ASSERT(!operands.isEmpty())
            return builder.CreateVArray(resultTypeOrInvalid(resultTy), operands, block)
        }
        if (kind == ExprKind.VARRAY_BUILDER) {
            CJC_ASSERT(operands.size == 3)
            return builder.CreateVArrayBuilder(resultTypeOrInvalid(resultTy), operands[0], operands[1], operands[2], block)
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
        CJC_ABORT()
        throw IllegalStateException("unsupported CHIR expression")
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
            case 2 => IntLiteral(CHIRSafeU64(CHIRFieldAt(fields, 1)))
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

    private func GetType<T>(ids: Option<Vector<UInt32>>): ArrayList<T> {
        let result = ArrayList<T>()
        if (let Some(vector) <- ids) {
            var index = 0u32
            while (index < vector.size()) {
                let id = (vector.Get(index) as UInt32).getOrThrow()
                if (let Some(ty) <- GetType<T>(id)) {
                    result.add(ty)
                }
                index++
            }
        }
        return result
    }

    private func Deserialize(obj: PackageFormat_Type): Type {
        let kind = obj.GetKind()
        if (kind == CHIRFB_CHIR_TYPE_KIND_INT8) { return builder.context.GetInt8Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_INT16) { return builder.context.GetInt16Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_INT32) { return builder.context.GetInt32Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_INT64) { return builder.context.GetInt64Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_INT_NATIVE) { return builder.context.GetIntNativeTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UINT8) { return builder.context.GetUInt8Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UINT16) { return builder.context.GetUInt16Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UINT32) { return builder.context.GetUInt32Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UINT64) { return builder.context.GetUInt64Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UINT_NATIVE) { return builder.context.GetUIntNativeTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_FLOAT16) { return builder.context.GetFloat16Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_FLOAT32) { return builder.context.GetFloat32Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_FLOAT64) { return builder.context.GetFloat64Ty() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_RUNE) { return builder.context.GetRuneTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_BOOLEAN) { return builder.context.GetBoolTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_UNIT) { return builder.context.GetUnitTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_NOTHING) { return builder.context.GetNothingType() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_VOID) { return builder.context.GetVoidTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_TUPLE) {
            return builder.context.GetTupleTy(GetType<Type>(obj.GetArgTys()))
        }
        let argTys = obj.GetArgTys().getOrThrow()
        CJC_ASSERT(argTys.size() >= 1u32)
        let argTy = GetType<Type>((argTys.Get(0u32) as UInt32).getOrThrow()).getOrThrow()
        if (kind == CHIRFB_CHIR_TYPE_KIND_C_POINTER) { return builder.context.GetCPointerTy(argTy) }
        if (kind == CHIRFB_CHIR_TYPE_KIND_C_STRING) { return builder.context.GetCStringTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_REFTYPE) { return builder.context.GetRefTy(argTy) }
        if (kind == CHIRFB_CHIR_TYPE_KIND_BOXTYPE) { return builder.context.GetBoxTy(argTy) }
        if (kind == CHIRFB_CHIR_TYPE_KIND_THIS) { return builder.context.GetThisTy() }
        CJC_ABORT()
        return builder.context.GetInvalidTy()
    }

    private func Deserialize(obj: PackageFormat_RawArrayType): RawArrayType {
        let argTys = obj.GetBase().getOrThrow().GetArgTys().getOrThrow()
        let elemTy = GetType<Type>((argTys.Get(0u32) as UInt32).getOrThrow()).getOrThrow()
        return builder.context.GetRawArrayTy(elemTy, dims: UInt64(obj.GetDims()))
    }

    private func Deserialize(obj: PackageFormat_VArrayType): VArrayType {
        let argTys = obj.GetBase().getOrThrow().GetArgTys().getOrThrow()
        let elemTy = GetType<Type>((argTys.Get(0u32) as UInt32).getOrThrow()).getOrThrow()
        return builder.context.GetVArrayTy(elemTy, UInt64(obj.GetSize()))
    }

    private func Deserialize(obj: PackageFormat_FuncType): FuncType {
        let argTys = obj.GetBase().getOrThrow().GetArgTys().getOrThrow()
        CJC_ASSERT(argTys.size() > 0u32)
        let retTyId = (argTys.Get(argTys.size() - 1u32) as UInt32).getOrThrow()
        let retTy = GetType<Type>(retTyId).getOrThrow()
        let paramTys = ArrayList<Type>()
        var index = 0u32
        while (index + 1u32 < argTys.size()) {
            paramTys.add(GetType<Type>((argTys.Get(index) as UInt32).getOrThrow()).getOrThrow())
            index++
        }
        return builder.context.GetFuncTy(paramTys, retTy, hasVarLenParam: obj.GetHasVarArg(),
            isCFunc: obj.GetIsCFuncType())
    }

    private func Deserialize(obj: PackageFormat_CustomType): CustomType {
        let kind = obj.GetBase().getOrThrow().GetKind()
        let def = GetCustomTypeDef<CustomTypeDef>(obj.GetCustomTypeDef()).getOrThrow()
        let typeArgs = GetType<Type>(obj.GetBase().getOrThrow().GetArgTys())
        if (kind == CHIRFB_CHIR_TYPE_KIND_CLASS) {
            return builder.context.GetClassTy((def as ClassDef).getOrThrow(), typeArgs)
        }
        if (kind == CHIRFB_CHIR_TYPE_KIND_ENUM) {
            return builder.context.GetEnumTy((def as EnumDef).getOrThrow(), typeArgs)
        }
        if (kind == CHIRFB_CHIR_TYPE_KIND_STRUCT) {
            return builder.context.GetStructTy((def as StructDef).getOrThrow(), typeArgs)
        }
        CJC_ABORT()
        return builder.context.GetStructTy((def as StructDef).getOrThrow(), typeArgs)
    }

    private func Deserialize(obj: PackageFormat_GenericType): GenericType {
        let identifier = obj.GetIdentifier().getOrThrow().str()
        let srcCodeIdentifier = obj.GetSrcCodeIdentifier().getOrThrow().str()
        let genericType = builder.context.GetGenericTy(identifier, srcCodeIdentifier)
        genericTypeConfig.add((genericType, obj))
        return genericType
    }

    private func GetType<T>(id: UInt32): Option<T> {
        if (id == 0u32) { return None }
        if (let Some(ty) <- id2Type.get(id)) { return ty as T }
        let rawPackage = pool.getOrThrow()
        let types = rawPackage.GetTypes().getOrThrow()
        let kinds = rawPackage.GetTypes_type().getOrThrow()
        let kind = (kinds.Get(id - 1u32) as UInt8).getOrThrow()
        let position = (types.Get(id - 1u32) as Int64).getOrThrow()
        let ty: Type
        if (kind == CHIRFB_TYPE_ELEM_TYPE) {
            ty = Deserialize(PackageFormat_Type(types.data, position))
        } else if (kind == CHIRFB_TYPE_ELEM_RAW_ARRAY_TYPE) {
            ty = Deserialize(PackageFormat_RawArrayType(types.data, position))
        } else if (kind == CHIRFB_TYPE_ELEM_V_ARRAY_TYPE) {
            ty = Deserialize(PackageFormat_VArrayType(types.data, position))
        } else if (kind == CHIRFB_TYPE_ELEM_FUNC_TYPE) {
            ty = Deserialize(PackageFormat_FuncType(types.data, position))
        } else if (kind == CHIRFB_TYPE_ELEM_CUSTOM_TYPE) {
            ty = Deserialize(PackageFormat_CustomType(types.data, position))
        } else if (kind == CHIRFB_TYPE_ELEM_GENERIC_TYPE) {
            ty = Deserialize(PackageFormat_GenericType(types.data, position))
        } else {
            CJC_ABORT()
            return None
        }
        id2Type[id] = ty
        return ty as T
    }

    private func Deserialize(obj: PackageFormat_EnumDef): EnumDef {
        let base = obj.GetBase().getOrThrow()
        let identifier = base.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetEnumDef(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let attrs = AttributeInfo(base.GetBase().getOrThrow().GetAttributes())
        let result = builder.CreateEnum(DebugLocation(), base.GetSrcCodeIdentifier().getOrThrow().str(),
            GetMangleNameFromIdentifier(identifier), base.GetPackageName().getOrThrow().str(),
            attrs.Test(Attribute.IMPORTED), obj.GetNonExhaustive())
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        return result
    }

    private func Deserialize(obj: PackageFormat_StructDef): StructDef {
        let base = obj.GetBase().getOrThrow()
        let identifier = base.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetStructDef(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let attrs = AttributeInfo(base.GetBase().getOrThrow().GetAttributes())
        let result = builder.CreateStruct(DebugLocation(), base.GetSrcCodeIdentifier().getOrThrow().str(),
            GetMangleNameFromIdentifier(identifier), base.GetPackageName().getOrThrow().str(),
            attrs.Test(Attribute.IMPORTED))
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        return result
    }

    private func Deserialize(obj: PackageFormat_ClassDef): ClassDef {
        let base = obj.GetBase().getOrThrow()
        let identifier = base.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetClassDef(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let attrs = AttributeInfo(base.GetBase().getOrThrow().GetAttributes())
        let result = builder.CreateClass(DebugLocation(), base.GetSrcCodeIdentifier().getOrThrow().str(),
            GetMangleNameFromIdentifier(identifier), base.GetPackageName().getOrThrow().str(), obj.GetIsClass(),
            attrs.Test(Attribute.IMPORTED))
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        return result
    }

    private func Deserialize(obj: PackageFormat_ExtendDef): ExtendDef {
        let base = obj.GetBase().getOrThrow()
        let identifier = base.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetExtendDef(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let attrs = AttributeInfo(base.GetBase().getOrThrow().GetAttributes())
        let genericParams = GetType<GenericType>(obj.GetGenericParams())
        let result = builder.CreateExtend(DebugLocation(), GetMangleNameFromIdentifier(identifier),
            base.GetPackageName().getOrThrow().str(), attrs.Test(Attribute.IMPORTED), genericParams)
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        result.AppendAttributeInfo(attrs)
        return result
    }

    private func GetCustomTypeDef<T>(id: UInt32): Option<T> {
        if (id == 0u32) { return None }
        if (let Some(def) <- id2CustomTypeDef.get(id)) { return def as T }
        let rawPackage = pool.getOrThrow()
        let defs = rawPackage.GetDefs().getOrThrow()
        let kinds = rawPackage.GetDefs_type().getOrThrow()
        let kind = (kinds.Get(id - 1u32) as UInt8).getOrThrow()
        let position = (defs.Get(id - 1u32) as Int64).getOrThrow()
        let def: CustomTypeDef
        if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_ENUM_DEF) {
            def = Deserialize(PackageFormat_EnumDef(defs.data, position))
        } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_STRUCT_DEF) {
            def = Deserialize(PackageFormat_StructDef(defs.data, position))
        } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_CLASS_DEF) {
            def = Deserialize(PackageFormat_ClassDef(defs.data, position))
        } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_EXTEND_DEF) {
            def = Deserialize(PackageFormat_ExtendDef(defs.data, position))
        } else {
            CJC_ABORT()
            return None
        }
        id2CustomTypeDef[id] = def
        return def as T
    }

    private func Create(obj: PackageFormat_Pos): Position {
        return Position(obj.GetLine(), obj.GetColumn())
    }

    private func Create(obj: PackageFormat_DebugLocation): DebugLocation {
        let filePath = obj.GetFilePath().getOrThrow().str()
        let fileId = obj.GetFileId()
        let beginPos = Create(obj.GetBeginPos().getOrThrow())
        let endPos = Create(obj.GetEndPos().getOrThrow())
        let scope = ArrayList<Int64>()
        if (let Some(values) <- obj.GetScope()) {
            var index = 0u32
            while (index < values.size()) {
                scope.add(Int64((values.Get(index) as Int32).getOrThrow()))
                index++
            }
        }
        if (builder.context.GetSourceFileName(fileId) == INVALID_NAME) {
            builder.context.RegisterSourceFileName(fileId, filePath)
        }
        return DebugLocation(builder.context.GetSourceFileName(fileId), fileId, beginPos, endPos, scopeInfo: scope)
    }

    private func Create(obj: PackageFormat_AnnoInfo): AnnoInfo {
        let mangledName = obj.GetMangledName().getOrThrow().str()
        let instances = ArrayList<CustomAnnoInstance>()
        if (let Some(rawInstances) <- obj.GetAnnoInstances()) {
            var index = 0u32
            while (index < rawInstances.size()) {
                let position = (rawInstances.Get(index) as Int64).getOrThrow()
                let rawInstance = PackageFormat_CustomAnnoInstance(rawInstances.data, position)
                let argValues = ArrayList<String>()
                if (let Some(rawArgs) <- rawInstance.GetArgValues()) {
                    var argIndex = 0u32
                    while (argIndex < rawArgs.size()) {
                        let argPos = (rawArgs.Get(argIndex) as Int64).getOrThrow()
                        argValues.add(FlatBufferString(rawArgs.data, argPos).str())
                        argIndex++
                    }
                }
                let loc = if (let Some(rawLoc) <- rawInstance.GetLoc()) { Create(rawLoc) } else { DebugLocation() }
                let className = if (let Some(rawName) <- rawInstance.GetAnnoClassName()) { rawName.str() } else { "" }
                instances.add(CustomAnnoInstance(className, argValues, loc))
                index++
            }
        }
        return AnnoInfo(mangledName, instances)
    }

    private func GetFeatures(obj: PackageFormat_GlobalValue): ArrayList<String> {
        let features = ArrayList<String>()
        if (let Some(vector) <- obj.GetFeatures()) {
            var index = 0u32
            while (index < vector.size()) {
                let position = (vector.Get(index) as Int64).getOrThrow()
                features.add(FlatBufferString(vector.data, position).str())
                index++
            }
        }
        return features
    }

    private func Deserialize(obj: PackageFormat_BoolLiteral): BoolLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(BoolLiteral(obj.GetVal()), valueTy)
    }

    private func Deserialize(obj: PackageFormat_RuneLiteral): RuneLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(RuneLiteral(Rune(obj.GetVal())), valueTy)
    }

    private func Deserialize(obj: PackageFormat_StringLiteral): StringLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(StringLiteral(obj.GetVal().getOrThrow().str()), valueTy)
    }

    private func Deserialize(obj: PackageFormat_IntLiteral): IntLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(IntLiteral(obj.GetVal()), valueTy)
    }

    private func Deserialize(obj: PackageFormat_FloatLiteral): FloatLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(FloatLiteral(obj.GetVal()), valueTy)
    }

    private func Deserialize(obj: PackageFormat_UnitLiteral): UnitLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(UnitLiteral(), valueTy)
    }

    private func Deserialize(obj: PackageFormat_NullLiteral): NullLiteral {
        let valueTy = GetType<Type>(obj.GetBase().getOrThrow().GetBase().getOrThrow().GetType()).getOrThrow()
        return builder.CreateLiteralValue(NullLiteral(), valueTy)
    }

    private func Deserialize(obj: PackageFormat_GlobalVar): GlobalVar {
        let globalValue = obj.GetBase().getOrThrow()
        let valueBase = globalValue.GetBase().getOrThrow()
        let identifier = valueBase.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetGlobalVar(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let valueTy = GetType<RefType>(valueBase.GetType()).getOrThrow()
        let result = builder.CreateGlobalVar(valueTy, GetMangleNameFromIdentifier(identifier),
            srcCodeIdentifier: globalValue.GetSrcCodeIdentifier().getOrThrow().str(),
            rawMangledName: globalValue.GetRawMangledName().getOrThrow().str(),
            packageName: globalValue.GetPackageName().getOrThrow().str())
        builder.context.GetCurPackage().getOrThrow().AddGlobalVar(result)
        result.SetFeatures(GetFeatures(globalValue))
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        return result
    }

    private func Deserialize(obj: PackageFormat_Function): Function {
        let globalValue = obj.GetBase().getOrThrow()
        let valueBase = globalValue.GetBase().getOrThrow()
        let valueTy = GetType<FuncType>(valueBase.GetType()).getOrThrow()
        let identifier = valueBase.GetIdentifier().getOrThrow().str()
        if (compilePlatform) {
            if (let Some(exist) <- builder.context.GetCurPackage().getOrThrow().TryGetGlobalFunc(identifier)) {
                exist.EnableAttr(Attribute.PREVIOUSLY_DESERIALIZED)
                return exist
            }
        }
        let result = builder.CreateFunction(valueTy, GetMangleNameFromIdentifier(identifier),
            srcCodeIdentifier: globalValue.GetSrcCodeIdentifier().getOrThrow().str(),
            rawMangledName: globalValue.GetRawMangledName().getOrThrow().str(),
            packageName: globalValue.GetPackageName().getOrThrow().str(),
            genericTypeParams: GetType<GenericType>(obj.GetGenericTypeParams()))
        result.SetFeatures(GetFeatures(globalValue))
        result.SetFastNative(obj.GetIsFastNative())
        result.SetCFFIWrapper(obj.GetIsCFFIWrapper())
        result.SetFuncKind(CHIRFuncKindFromIndex(Int64(obj.GetFuncKind())))
        if (compilePlatform) { result.EnableAttr(Attribute.DESERIALIZED) }
        return result
    }

}
