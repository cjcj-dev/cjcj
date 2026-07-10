package cjcj::chir

import std.collection.*
import std.convert.*
import cjcj::basic.Linkage as BasicLinkage
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, OverflowStrategy}

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

    public func Run(pkg: PackageFormat_CHIRPackage): Unit {
        pool = pkg
        if (builder.context.GetCurPackage().isNone()) {
            let currentPackage = builder.CreatePackage(pkg.GetName().getOrThrow().str())
            currentPackage.SetPackageAccessLevel(CHIRAccessLevelFromIndex(Int64(pkg.GetPkgAccessLevel())))
        }
        let defs = pkg.GetDefs().getOrThrow()
        var id = 1u32
        while (id <= defs.size()) {
            GetCustomTypeDef<CustomTypeDef>(id)
            id++
        }
        let values = pkg.GetValues().getOrThrow()
        let valueKinds = pkg.GetValues_type().getOrThrow()
        id = 1u32
        while (id <= values.size()) {
            let kind = (valueKinds.Get(id - 1u32) as UInt8).getOrThrow()
            if (kind == CHIRFB_VALUE_ELEM_FUNCTION || kind == CHIRFB_VALUE_ELEM_GLOBAL_VAR) {
                GetValue<Value>(id)
            }
            id++
        }
        let defKinds = pkg.GetDefs_type().getOrThrow()
        id = 1u32
        while (id <= defs.size()) {
            let kind = (defKinds.Get(id - 1u32) as UInt8).getOrThrow()
            let position = (defs.Get(id - 1u32) as Int64).getOrThrow()
            if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_ENUM_DEF) {
                Config(PackageFormat_EnumDef(defs.data, position), GetCustomTypeDef<EnumDef>(id).getOrThrow())
            } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_STRUCT_DEF) {
                Config(PackageFormat_StructDef(defs.data, position), GetCustomTypeDef<StructDef>(id).getOrThrow())
            } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_CLASS_DEF) {
                Config(PackageFormat_ClassDef(defs.data, position), GetCustomTypeDef<ClassDef>(id).getOrThrow())
            } else if (kind == CHIRFB_CUSTOM_TYPE_DEF_ELEM_EXTEND_DEF) {
                Config(PackageFormat_ExtendDef(defs.data, position), GetCustomTypeDef<ExtendDef>(id).getOrThrow())
            }
            id++
        }
        id = 1u32
        while (id <= values.size()) {
            let kind = (valueKinds.Get(id - 1u32) as UInt8).getOrThrow()
            let position = (values.Get(id - 1u32) as Int64).getOrThrow()
            if (kind == CHIRFB_VALUE_ELEM_GLOBAL_VAR) {
                Config(PackageFormat_GlobalVar(values.data, position), GetValue<GlobalVar>(id).getOrThrow())
            } else if (kind == CHIRFB_VALUE_ELEM_FUNCTION) {
                Config(PackageFormat_Function(values.data, position), GetValue<Function>(id).getOrThrow())
            } else if (kind == CHIRFB_VALUE_ELEM_BLOCK) {
                Config(PackageFormat_Block(values.data, position), GetValue<Block>(id).getOrThrow())
            } else if (kind == CHIRFB_VALUE_ELEM_BLOCK_GROUP) {
                Config(PackageFormat_BlockGroup(values.data, position), GetValue<BlockGroup>(id).getOrThrow())
            }
            id++
        }
        id = 1u32
        while (id <= values.size()) {
            let kind = (valueKinds.Get(id - 1u32) as UInt8).getOrThrow()
            if (kind == CHIRFB_VALUE_ELEM_LOCAL_VAR) {
                GetValue<Value>(id)
            } else if (kind == CHIRFB_VALUE_ELEM_FUNCTION) {
                let position = (values.Get(id - 1u32) as Int64).getOrThrow()
                let rawFunction = PackageFormat_Function(values.data, position)
                let function = GetValue<Function>(id).getOrThrow()
                function.SetLocalId(rawFunction.GetLocalId())
                function.SetBlockId(rawFunction.GetBlockId())
                function.SetBlockGroupId(rawFunction.GetBlockGroupId())
            }
            id++
        }
        var genericIndex: Int64 = 0
        while (genericIndex < genericTypeConfig.size) {
            let (genericType, rawGenericType) = genericTypeConfig[genericIndex]
            genericType.SetUpperBounds(GetType<Type>(rawGenericType.GetUpperBounds()))
            genericIndex++
        }
        let currentPackage = builder.context.GetCurPackage().getOrThrow()
        currentPackage.SetPackageInitFunc(GetValue<Function>(pkg.GetPackageInitFunc()).getOrThrow())
        currentPackage.SetPackageLiteralInitFunc(GetValue<Function>(pkg.GetPackageLiteralInitFunc()).getOrThrow())
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
        if (kind == CHIRFB_CHIR_TYPE_KIND_C_STRING) { return builder.context.GetCStringTy() }
        if (kind == CHIRFB_CHIR_TYPE_KIND_THIS) { return builder.context.GetThisTy() }
        let argTys = obj.GetArgTys().getOrThrow()
        CJC_ASSERT(argTys.size() >= 1u32)
        let argTy = GetType<Type>((argTys.Get(0u32) as UInt32).getOrThrow()).getOrThrow()
        if (kind == CHIRFB_CHIR_TYPE_KIND_C_POINTER) { return builder.context.GetCPointerTy(argTy) }
        if (kind == CHIRFB_CHIR_TYPE_KIND_REFTYPE) { return builder.context.GetRefTy(argTy) }
        if (kind == CHIRFB_CHIR_TYPE_KIND_BOXTYPE) { return builder.context.GetBoxTy(argTy) }
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

    private func Create(obj: PackageFormat_MemberVarInfo): MemberVarInfo {
        let attributeInfo = AttributeInfo(obj.GetAttributes())
        if (compilePlatform) {
            attributeInfo.Enable(Attribute.DESERIALIZED)
        }
        let result = MemberVarInfo(obj.GetName().getOrThrow().str(), GetType<Type>(obj.GetType()).getOrThrow(),
            rawMangledName: obj.GetRawMangledName().getOrThrow().str())
        result.attributeInfo.CopyFrom(attributeInfo)
        result.loc = Create(obj.GetLoc().getOrThrow())
        result.annoInfo = Create(obj.GetAnnoInfo().getOrThrow())
        result.initializerFunc = GetValue<Function>(obj.GetInitializerFunc())
        result.outerDef = GetCustomTypeDef<CustomTypeDef>(obj.GetOuterDef())
        return result
    }

    private func Create(obj: PackageFormat_EnumCtorInfo): EnumCtorInfo {
        return EnumCtorInfo(obj.GetSrcCodeName().getOrThrow().str(), ArrayList<Type>(),
            mangledName: obj.GetMangledName().getOrThrow().str(), funcType: GetType<FuncType>(obj.GetFuncType()))
    }

    private func Create(obj: PackageFormat_VirtualMethodInfo): VirtualMethodInfo {
        let condition = FuncSigInfo(GetType<FuncType>(obj.GetSigType()).getOrThrow(),
            funcName: obj.GetFuncName().getOrThrow().str(),
            genericTypeParams: GetType<GenericType>(obj.GetMethodGenericTypeParams()))
        return VirtualMethodInfo(condition, GetValue<Function>(obj.GetInstance()), AttributeInfo(obj.GetAttributes()),
            GetType<FuncType>(obj.GetOriginalType()).getOrThrow(), GetType<Type>(obj.GetParentType()).getOrThrow(),
            GetType<Type>(obj.GetReturnType()).getOrThrow())
    }

    private func Create(obj: Vector<Offset<PackageFormat_VTableInType>>): VTableInDef {
        let result = VTableInDef()
        var index = 0u32
        while (index < obj.size()) {
            let position = (obj.Get(index) as Int64).getOrThrow()
            let item = PackageFormat_VTableInType(obj.data, position)
            let methods = ArrayList<VirtualMethodInfo>()
            if (let Some(rawMethods) <- item.GetVirtualMethods()) {
                var methodIndex = 0u32
                while (methodIndex < rawMethods.size()) {
                    let methodPosition = (rawMethods.Get(methodIndex) as Int64).getOrThrow()
                    methods.add(Create(PackageFormat_VirtualMethodInfo(rawMethods.data, methodPosition)))
                    methodIndex++
                }
            }
            result.AddNewItemToTypeVTable(GetType<ClassType>(item.GetSrcParentType()).getOrThrow(), methods)
            index++
        }
        return result
    }

    private func ConfigBase(buffer: PackageFormat_Base, obj: Base): Unit {
        let annos = buffer.GetAnnos().getOrThrow()
        let annoTypes = buffer.GetAnnos_type().getOrThrow()
        var index = 0u32
        while (index < annos.size()) {
            let position = (annos.Get(index) as Int64).getOrThrow()
            let annoType = (annoTypes.Get(index) as UInt8).getOrThrow()
            match (annoType) {
                case 1u8 =>
                    let anno = PackageFormat_NeedCheckArrayBound(annos.data, position)
                    obj.Set<NeedCheckArrayBound, Bool>(anno.GetNeed())
                case 2u8 =>
                    let anno = PackageFormat_NeedCheckCast(annos.data, position)
                    obj.Set<NeedCheckCast, Bool>(anno.GetNeed())
                case 3u8 =>
                    let anno = PackageFormat_DebugLocation(annos.data, position)
                    obj.Set<DebugLocationInfoForWarning, DebugLocation>(Create(anno))
                case 4u8 =>
                    let anno = PackageFormat_GeneratedFromForIn(annos.data, position)
                    obj.Set<GeneratedFromForIn, Bool>(anno.GetValue())
                case 5u8 =>
                    let anno = PackageFormat_IsAutoEnvClass(annos.data, position)
                    obj.Set<IsAutoEnvClass, Bool>(anno.GetValue())
                case 6u8 =>
                    let anno = PackageFormat_IsCapturedClassInCC(annos.data, position)
                    obj.Set<IsCapturedClassInCC, Bool>(anno.GetValue())
                case 7u8 =>
                    let anno = PackageFormat_LinkTypeInfo(annos.data, position)
                    let linkage = match (anno.GetLinkage()) {
                        case 0 => BasicLinkage.WEAK_ODR
                        case 1 => BasicLinkage.EXTERNAL
                        case 2 => BasicLinkage.INTERNAL
                        case 3 => BasicLinkage.LINKONCE_ODR
                        case 4 => BasicLinkage.EXTERNAL_WEAK
                        case _ =>
                            CJC_ABORT()
                            BasicLinkage.EXTERNAL
                    }
                    obj.Set<LinkTypeInfo, BasicLinkage>(linkage)
                case 8u8 =>
                    let anno = PackageFormat_SkipCheck(annos.data, position)
                    let skipKind = match (anno.GetSkipKind()) {
                        case 0u8 => SkipKind.NO_SKIP
                        case 1u8 => SkipKind.SKIP_DCE_WARNING
                        case 2u8 => SkipKind.SKIP_FORIN_EXIT
                        case 3u8 => SkipKind.SKIP_VIC
                        case _ =>
                            CJC_ABORT()
                            SkipKind.NO_SKIP
                    }
                    obj.Set<SkipCheck, SkipKind>(skipKind)
                case 9u8 =>
                    let anno = PackageFormat_NeverOverflowInfo(annos.data, position)
                    obj.Set<NeverOverflowInfo, Bool>(anno.GetNeverOverflow())
                case 10u8 =>
                    let anno = PackageFormat_EnumCaseIndex(annos.data, position)
                    if (anno.GetIndex() != -1) {
                        obj.Set<EnumCaseIndex, Option<Int64>>(Some(anno.GetIndex()))
                    }
                case 11u8 =>
                    let anno = PackageFormat_VirMethodOffset(annos.data, position)
                    if (anno.GetOffset() != -1) {
                        obj.Set<VirMethodOffset, Option<Int64>>(Some(anno.GetOffset()))
                    }
                case 12u8 =>
                    let anno = PackageFormat_WrappedRawMethod(annos.data, position)
                    obj.Set<WrappedRawMethod, Option<Function>>(GetValue<Function>(anno.GetRawMethod()))
                case 13u8 =>
                    let anno = PackageFormat_OverrideSrcFuncType(annos.data, position)
                    obj.Set<OverrideSrcFuncType, Option<FuncType>>(GetType<FuncType>(anno.GetType()))
                case _ => ()
            }
            index++
        }
        if (let Some(location) <- buffer.GetLoc()) {
            obj.SetDebugLocation(Create(location))
        }
        obj.AppendAttributeInfo(AttributeInfo(buffer.GetAttributes()))
    }

    private func ConfigValue(buffer: PackageFormat_Value, obj: Value): Unit {
        ConfigBase(buffer.GetBase().getOrThrow(), obj)
        if (let Some(identifier) <- buffer.GetIdentifier()) {
            obj.SetIdentifier(identifier.str())
        }
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

    private func Deserialize(obj: PackageFormat_BlockGroup): BlockGroup {
        var blockGroup: Option<BlockGroup> = None
        if (obj.GetOwnedFunc() != 0u32) {
            let ownedFunc = GetValue<Function>(obj.GetOwnedFunc()).getOrThrow()
            let result = builder.CreateBlockGroup(ownedFunc)
            result.SetOwnerFunc(ownedFunc)
            blockGroup = result
        } else if (obj.GetOwnedExpression() != 0u32) {
            let ownedExpression = GetExpression<Expression>(obj.GetOwnedExpression()).getOrThrow()
            let result = builder.CreateBlockGroup(ownedExpression.GetTopLevelFunc().getOrThrow())
            if (let Some(lambda) <- (ownedExpression as Lambda)) {
                lambda.InitBody(result)
            }
            blockGroup = result
        }
        return blockGroup.getOrThrow()
    }

    private func Deserialize(obj: PackageFormat_Block): Block {
        let parentGroup = GetValue<BlockGroup>(obj.GetParentGroup()).getOrThrow()
        return builder.CreateBlock(parentGroup)
    }

    private func Deserialize(obj: PackageFormat_Parameter): Parameter {
        let base = obj.GetBase().getOrThrow()
        CJC_ASSERT(base.GetKind() == CHIRFB_VALUE_KIND_PARAMETER)
        let ty = GetType<Type>(base.GetType()).getOrThrow()
        let result: Parameter
        if (let Some(ownedFunc) <- GetValue<Function>(obj.GetOwnedFunc())) {
            result = builder.CreateParameter(ty, INVALID_LOCATION, ownedFunc)
        } else if (let Some(ownedLambda) <- GetExpression<Lambda>(obj.GetOwnedLambda())) {
            result = builder.CreateParameter(ty, INVALID_LOCATION, ownedLambda)
        } else {
            CJC_ABORT()
            return builder.CreateParameter(ty, INVALID_LOCATION,
                GetValue<Function>(obj.GetOwnedFunc()).getOrThrow())
        }
        result.SetSrcCodeIdentifier(obj.GetSrcCodeIdentifier().getOrThrow().str())
        if (let Some(annoInfo) <- obj.GetAnnoInfo()) {
            result.SetAnnoInfo(Create(annoInfo))
        }
        return result
    }

    private func Deserialize(obj: PackageFormat_LocalVar): LocalVar {
        let associatedExpr = GetExpression<Expression>(obj.GetAssociatedExpr()).getOrThrow()
        let result = associatedExpr.GetResult().getOrThrow()
        result.SetSrcCodeIdentifier(obj.GetSrcCodeIdentifier().getOrThrow().str())
        result.SetIdentifier(obj.GetBase().getOrThrow().GetIdentifier().getOrThrow().str())
        if (obj.GetIsRetVal()) {
            result.SetRetValue(true)
        }
        return result
    }

    private func GetValue<T>(ids: Option<Vector<UInt32>>): ArrayList<T> {
        let result = ArrayList<T>()
        if (let Some(vector) <- ids) {
            var index = 0u32
            while (index < vector.size()) {
                let id = (vector.Get(index) as UInt32).getOrThrow()
                if (let Some(value) <- GetValue<T>(id)) {
                    result.add(value)
                }
                index++
            }
        }
        return result
    }

    private func GetValue<T>(id: UInt32): Option<T> {
        if (id == 0u32) {
            return None
        }
        if (let Some(value) <- id2Value.get(id)) {
            return value as T
        }
        let rawPackage = pool.getOrThrow()
        let values = rawPackage.GetValues().getOrThrow()
        let kinds = rawPackage.GetValues_type().getOrThrow()
        let kind = (kinds.Get(id - 1u32) as UInt8).getOrThrow()
        let position = (values.Get(id - 1u32) as Int64).getOrThrow()
        let value: Value
        match (kind) {
            case 1u8 =>
                let raw = PackageFormat_BoolLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 2u8 =>
                let raw = PackageFormat_RuneLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 3u8 =>
                let raw = PackageFormat_StringLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 4u8 =>
                let raw = PackageFormat_IntLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 5u8 =>
                let raw = PackageFormat_FloatLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 6u8 =>
                let raw = PackageFormat_UnitLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 7u8 =>
                let raw = PackageFormat_NullLiteral(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow().GetBase().getOrThrow(), value)
            case 8u8 =>
                let raw = PackageFormat_Parameter(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow(), value)
            case 9u8 =>
                let raw = PackageFormat_LocalVar(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow(), value)
            case 10u8 =>
                value = Deserialize(PackageFormat_GlobalVar(values.data, position))
                id2Value[id] = value
            case 11u8 =>
                value = Deserialize(PackageFormat_Function(values.data, position))
                id2Value[id] = value
            case 12u8 =>
                let raw = PackageFormat_Block(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow(), value)
            case 13u8 =>
                let raw = PackageFormat_BlockGroup(values.data, position)
                value = Deserialize(raw)
                id2Value[id] = value
                ConfigValue(raw.GetBase().getOrThrow(), value)
            case _ =>
                CJC_ABORT()
                return builder.CreateLiteralValue(UnitLiteral(), builder.context.GetUnitTy()) as T
        }
        return value as T
    }

    private func GetExpression<T>(ids: Option<Vector<UInt32>>): ArrayList<T> {
        let result = ArrayList<T>()
        if (let Some(vector) <- ids) {
            var index = 0u32
            while (index < vector.size()) {
                let id = (vector.Get(index) as UInt32).getOrThrow()
                if (let Some(expression) <- GetExpression<T>(id)) {
                    result.add(expression)
                }
                index++
            }
        }
        return result
    }

    private func Deserialize(obj: PackageFormat_UnaryExpressionBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let operands = base.GetOperands().getOrThrow()
        let operandId = (operands.Get(0u32) as UInt32).getOrThrow()
        let operand = GetValue<Value>(operandId).getOrThrow()
        let parentBlock = GetValue<Block>(base.GetOwner()).getOrThrow()
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let overflowStrategy = match (obj.GetOverflowStrategy()) {
            case 0u8 => OverflowStrategy.NA
            case 1u8 => OverflowStrategy.CHECKED
            case 2u8 => OverflowStrategy.WRAPPING
            case 3u8 => OverflowStrategy.THROWING
            case 4u8 => OverflowStrategy.SATURATING
            case _ =>
                CJC_ABORT()
                OverflowStrategy.NA
        }
        let (kind, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let normalId = (operands.Get(1u32) as UInt32).getOrThrow()
            let exceptionId = (operands.Get(2u32) as UInt32).getOrThrow()
            let result = builder.CreateUnaryIntOpWithException(resultTy, kind, operand,
                GetValue<Block>(normalId).getOrThrow(), GetValue<Block>(exceptionId).getOrThrow(), parentBlock)
            result.SetOverflowStrategy(overflowStrategy)
            return result
        }
        return builder.CreateUnaryExpression(kind, resultTy, operand, parentBlock,
            overflowStrategy: overflowStrategy)
    }

    private func Deserialize(obj: PackageFormat_BinaryExpressionBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let operands = base.GetOperands().getOrThrow()
        let lhs = GetValue<Value>((operands.Get(0u32) as UInt32).getOrThrow()).getOrThrow()
        let rhs = GetValue<Value>((operands.Get(1u32) as UInt32).getOrThrow()).getOrThrow()
        let parentBlock = GetValue<Block>(base.GetOwner()).getOrThrow()
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let overflowStrategy = match (obj.GetOverflowStrategy()) {
            case 0u8 => OverflowStrategy.NA
            case 1u8 => OverflowStrategy.CHECKED
            case 2u8 => OverflowStrategy.WRAPPING
            case 3u8 => OverflowStrategy.THROWING
            case 4u8 => OverflowStrategy.SATURATING
            case _ =>
                CJC_ABORT()
                OverflowStrategy.NA
        }
        let (kind, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let normalId = (operands.Get(2u32) as UInt32).getOrThrow()
            let exceptionId = (operands.Get(3u32) as UInt32).getOrThrow()
            let result = builder.CreateBinaryIntOpWithException(resultTy, kind, lhs, rhs,
                GetValue<Block>(normalId).getOrThrow(), GetValue<Block>(exceptionId).getOrThrow(), parentBlock)
            result.SetOverflowStrategy(overflowStrategy)
            return result
        }
        return builder.CreateBinaryExpression(kind, resultTy, lhs, rhs, parentBlock,
            overflowStrategy: overflowStrategy)
    }

    private func DeserializeConstant(resultTy: Type, value: LiteralValue, parent: Block): Constant {
        if (let Some(literal) <- (value as BoolLiteral)) {
            return builder.CreateConstant(resultTy, BoolLiteral(literal.GetVal()), parent)
        } else if (let Some(literal) <- (value as FloatLiteral)) {
            return builder.CreateConstant(resultTy, FloatLiteral(literal.GetVal()), parent)
        } else if (let Some(literal) <- (value as IntLiteral)) {
            return builder.CreateConstant(resultTy, IntLiteral(literal.GetUnsignedVal()), parent)
        } else if (value is NullLiteral) {
            return builder.CreateConstant(resultTy, NullLiteral(), parent)
        } else if (let Some(literal) <- (value as RuneLiteral)) {
            return builder.CreateConstant(resultTy, RuneLiteral(literal.GetVal()), parent)
        } else if (let Some(literal) <- (value as StringLiteral)) {
            return builder.CreateConstant(resultTy, StringLiteral(literal.GetVal()), parent)
        } else if (value is UnitLiteral) {
            return builder.CreateConstant(resultTy, UnitLiteral(), parent)
        }
        CJC_ABORT()
        return builder.CreateConstant(resultTy, UnitLiteral(), parent)
    }

    private func Deserialize(obj: PackageFormat_Expression): Expression {
        let operands = GetValue<Value>(obj.GetOperands())
        let owner = GetValue<Block>(obj.GetOwner()).getOrThrow()
        let resultTy = GetType<Type>(obj.GetResultTy())
        let (kind, _) = CHIRExprKindToExprKind(obj.GetKind())
        match (kind) {
            case ExprKind.BOX =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateBox(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.CONSTANT =>
                CJC_ASSERT(operands.size == 1)
                return DeserializeConstant(resultTy.getOrThrow(),
                    (operands[0] as LiteralValue).getOrThrow(), owner)
            case ExprKind.EXIT => return builder.CreateExit(None, owner)
            case ExprKind.GET_EXCEPTION => return builder.CreateGetException(resultTy.getOrThrow(), owner)
            case ExprKind.GET_RTTI =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateGetRTTI(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.GOTO =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateGoTo((operands[0] as Block).getOrThrow(), owner)
            case ExprKind.LOAD =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateLoad(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.RAISE_EXCEPTION =>
                if (operands.size == 2) {
                    return builder.CreateRaiseException(operands[0], (operands[1] as Block).getOrThrow(), owner)
                }
                CJC_ASSERT(operands.size == 1)
                return builder.CreateRaiseException(operands[0], owner)
            case ExprKind.RAW_ARRAY_INIT_BY_VALUE =>
                CJC_ASSERT(operands.size == 3)
                return builder.CreateRawArrayInitByValue(resultTy.getOrThrow(), operands[0], operands[1],
                    operands[2], owner)
            case ExprKind.RAW_ARRAY_LITERAL_INIT =>
                CJC_ASSERT(!operands.isEmpty())
                let rawArrayMemory = operands[0]
                operands.remove(at: 0)
                return builder.CreateRawArrayLiteralInit(resultTy.getOrThrow(), rawArrayMemory, operands, owner)
            case ExprKind.STORE =>
                CJC_ASSERT(operands.size == 2)
                return builder.CreateStore(operands[0], operands[1], owner)
            case ExprKind.TRANSFORM_TO_CONCRETE =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateTransformToConcrete(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.TRANSFORM_TO_GENERIC =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateTransformToGeneric(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.TUPLE => return builder.CreateTuple(resultTy.getOrThrow(), operands, owner)
            case ExprKind.UNBOX =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateUnBox(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.UNBOX_TO_REF =>
                CJC_ASSERT(operands.size == 1)
                return builder.CreateUnBoxToRef(resultTy.getOrThrow(), operands[0], owner)
            case ExprKind.VARRAY =>
                CJC_ASSERT(!operands.isEmpty())
                return builder.CreateVArray(resultTy.getOrThrow(), operands, owner)
            case ExprKind.VARRAY_BUILDER =>
                CJC_ASSERT(operands.size == 3)
                return builder.CreateVArrayBuilder(resultTy.getOrThrow(), operands[0], operands[1], operands[2], owner)
            case _ =>
                CJC_ABORT()
                return builder.CreateExit(None, owner)
        }
    }

    private func Deserialize(obj: PackageFormat_AllocateBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let parentBlock = GetValue<Block>(base.GetOwner()).getOrThrow()
        let targetType = GetType<Type>(obj.GetAllocatedType()).getOrThrow()
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let operands = GetValue<Value>(base.GetOperands())
            CJC_ASSERT(operands.size == 2)
            return builder.CreateAllocateWithException(resultTy, targetType,
                (operands[0] as Block).getOrThrow(), (operands[1] as Block).getOrThrow(), parentBlock)
        }
        return builder.CreateAllocate(resultTy, targetType, parentBlock)
    }

    private func Deserialize(obj: PackageFormat_GetElementRef): GetElementRef {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let path = ArrayList<UInt64>()
        let rawPath = obj.GetPath().getOrThrow()
        var index = 0u32
        while (index < rawPath.size()) {
            path.add((rawPath.Get(index) as UInt64).getOrThrow())
            index++
        }
        return builder.CreateGetElementRef(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0], path,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_GetElementByName): GetElementByName {
        let base = obj.GetBase().getOrThrow()
        let names = ArrayList<String>()
        let rawNames = obj.GetFieldNames().getOrThrow()
        var index = 0u32
        while (index < rawNames.size()) {
            names.add(FlatBufferString(rawNames.data, (rawNames.Get(index) as Int64).getOrThrow()).str())
            index++
        }
        let operands = GetValue<Value>(base.GetOperands())
        return builder.CreateGetElementByName(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0], names,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_StoreElementRef): StoreElementRef {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let path = ArrayList<UInt64>()
        let rawPath = obj.GetPath().getOrThrow()
        var index = 0u32
        while (index < rawPath.size()) {
            path.add((rawPath.Get(index) as UInt64).getOrThrow())
            index++
        }
        return builder.CreateStoreElementRef(operands[0], operands[1], path,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_StoreElementByName): StoreElementByName {
        let base = obj.GetBase().getOrThrow()
        let names = ArrayList<String>()
        let rawNames = obj.GetFieldNames().getOrThrow()
        var index = 0u32
        while (index < rawNames.size()) {
            names.add(FlatBufferString(rawNames.data, (rawNames.Get(index) as Int64).getOrThrow()).str())
            index++
        }
        let operands = GetValue<Value>(base.GetOperands())
        return builder.CreateStoreElementByName(operands[0], operands[1], names,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_ApplyBase): Expression {
        let funcCallBase = obj.GetBase().getOrThrow()
        let base = funcCallBase.GetBase().getOrThrow()
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        CJC_ASSERT(!operands.isEmpty())
        let callee = operands[0]
        operands.remove(at: 0)
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let instantiatedTypeArgs = GetType<Type>(funcCallBase.GetInstantiatedTypeArgs())
        let objType = GetType<Type>(funcCallBase.GetObjType())
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let exceptionBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let normalBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let callContext = FuncCallContext(args: operands, instTypeArgs: instantiatedTypeArgs,
                thisType: objType)
            return builder.CreateApplyWithException(resultTy, callee, callContext, normalBlock,
                exceptionBlock, owner)
        }
        let callContext = FuncCallContext(args: operands, instTypeArgs: instantiatedTypeArgs, thisType: objType)
        let expression = builder.CreateApply(resultTy, callee, callContext, owner)
        if (obj.GetIsSuperCall()) {
            expression.SetSuperCall()
        }
        return expression
    }

    private func Deserialize(obj: PackageFormat_InvokeBase): Expression {
        let funcCallBase = obj.GetBase().getOrThrow()
        let base = funcCallBase.GetBase().getOrThrow()
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        CJC_ASSERT(!operands.isEmpty())
        let caller = operands[0]
        operands.remove(at: 0)
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let (kind, withException) = CHIRExprKindToExprKind(base.GetKind())
        var exceptionBlock: Option<Block> = None
        var normalBlock: Option<Block> = None
        if (withException) {
            exceptionBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            normalBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
        }
        let virMethodCtx = obj.GetVirMethodCtx().getOrThrow()
        let invokeInfo = InvokeCallContext(caller,
            FuncCallContext(args: operands, instTypeArgs: GetType<Type>(funcCallBase.GetInstantiatedTypeArgs()),
                thisType: GetType<Type>(funcCallBase.GetObjType())),
            FuncSigInfo(GetType<FuncType>(virMethodCtx.GetFuncType()).getOrThrow(),
                funcName: virMethodCtx.GetFuncName().getOrThrow().str(),
                genericTypeParams: GetType<GenericType>(virMethodCtx.GetGenericTypeParams())))
        var isStatic = false
        if (let Some(local) <- (caller as LocalVar)) {
            if (let Some(callerExpression) <- local.GetExpr()) {
                let callerKind = callerExpression.GetExprKind()
                isStatic = callerKind == ExprKind.GET_RTTI_STATIC || callerKind == ExprKind.GET_RTTI
            }
        }
        if (kind == ExprKind.INVOKE) {
            if (isStatic) {
                return builder.CreateInvokeStatic(resultTy, invokeInfo, owner)
            }
            return builder.CreateInvoke(resultTy, invokeInfo, owner)
        }
        if (isStatic) {
            return builder.CreateInvokeStaticWithException(resultTy, invokeInfo, normalBlock.getOrThrow(),
                exceptionBlock.getOrThrow(), owner)
        }
        return builder.CreateInvokeWithException(resultTy, invokeInfo, normalBlock.getOrThrow(),
            exceptionBlock.getOrThrow(), owner)
    }

    private func Deserialize(obj: PackageFormat_GetInstantiateValue): GetInstantiateValue {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        return builder.CreateGetInstantiateValue(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0],
            GetType<Type>(obj.GetInstantiateTypes()), GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_NumericCastBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let overflowStrategy = match (obj.GetOverflowStrategy()) {
            case 0u8 => OverflowStrategy.NA
            case 1u8 => OverflowStrategy.CHECKED
            case 2u8 => OverflowStrategy.WRAPPING
            case 3u8 => OverflowStrategy.THROWING
            case 4u8 => OverflowStrategy.SATURATING
            case _ =>
                CJC_ABORT()
                OverflowStrategy.NA
        }
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            return builder.CreateTypeCastWithException(resultTy, operands[0],
                (operands[1] as Block).getOrThrow(), (operands[2] as Block).getOrThrow(), owner)
        }
        return builder.CreateTypeCast(resultTy, operands[0], owner, overflowStrategy: overflowStrategy)
    }

    private func Deserialize(obj: PackageFormat_InstanceOf): InstanceOf {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        return builder.CreateInstanceOf(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0],
            GetType<Type>(obj.GetTargetType()).getOrThrow(), GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_Field): Field {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let indexes = ArrayList<UInt64>()
        let path = obj.GetPath().getOrThrow()
        var index = 0u32
        while (index < path.size()) {
            indexes.add((path.Get(index) as UInt64).getOrThrow())
            index++
        }
        return builder.CreateField(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0], indexes,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_FieldByName): FieldByName {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let names = ArrayList<String>()
        let fieldNames = obj.GetFieldNames().getOrThrow()
        var index = 0u32
        while (index < fieldNames.size()) {
            names.add(FlatBufferString(fieldNames.data, (fieldNames.Get(index) as Int64).getOrThrow()).str())
            index++
        }
        return builder.CreateFieldByName(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0], names,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_Debug): Debug {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        CJC_ASSERT(operands.size == 1)
        return builder.CreateDebug(GetType<Type>(base.GetResultTy()).getOrThrow(), operands[0],
            obj.GetSrcCodeName().getOrThrow().str(), GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_Lambda): Lambda {
        let base = obj.GetBase().getOrThrow()
        let lambda = builder.CreateLambda(GetType<Type>(base.GetResultTy()).getOrThrow(),
            GetType<FuncType>(obj.GetFuncTy()).getOrThrow(), GetValue<Block>(base.GetOwner()).getOrThrow(),
            isLocalFunc: obj.GetIsLocalFunc(), identifier: obj.GetIdentifier().getOrThrow().str(),
            srcCodeIdentifier: obj.GetSrcCodeName().getOrThrow().str(),
            genericTypeParams: GetType<GenericType>(obj.GetGenericTypeParams()))
        if (obj.GetIsCompileTimeValue()) {
            lambda.SetCompileTimeValue()
        }
        return lambda
    }

    private func Deserialize(obj: PackageFormat_Branch): Branch {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let result = builder.CreateBranch(operands[0], (operands[1] as Block).getOrThrow(),
            (operands[2] as Block).getOrThrow(), GetValue<Block>(base.GetOwner()).getOrThrow())
        result.SetSourceExpr(CHIRSourceExprFromIndex(Int64(obj.GetSourceExpr())))
        return result
    }

    private func Deserialize(obj: PackageFormat_MultiBranch): MultiBranch {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let cond = operands[0]
        operands.remove(at: 0)
        let defaultBlock = (operands[0] as Block).getOrThrow()
        operands.remove(at: 0)
        let caseBlocks = ArrayList<Block>()
        for (operand in operands) {
            caseBlocks.add((operand as Block).getOrThrow())
        }
        let caseValues = ArrayList<UInt64>()
        let rawValues = obj.GetCaseValues().getOrThrow()
        var index = 0u32
        while (index < rawValues.size()) {
            caseValues.add((rawValues.Get(index) as UInt64).getOrThrow())
            index++
        }
        return builder.CreateMultiBranch(cond, defaultBlock, caseValues, caseBlocks,
            GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func Deserialize(obj: PackageFormat_IntrinsicBase): Expression {
        let funcCallBase = obj.GetBase().getOrThrow()
        let base = funcCallBase.GetBase().getOrThrow()
        let intrinsicKind = match (obj.GetIntrinsicKind()) {
            case 0u16 => IntrinsicKind.NOT_INTRINSIC
            case 1u16 => IntrinsicKind.NOT_IMPLEMENTED
            case 2u16 => IntrinsicKind.ARRAY_INIT
            case 3u16 => IntrinsicKind.SIZE_OF
            case 4u16 => IntrinsicKind.ALIGN_OF
            case 5u16 => IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA
            case 6u16 => IntrinsicKind.ARRAY_RELEASE_RAW_DATA
            case 7u16 => IntrinsicKind.ARRAY_BUILT_IN_COPY_TO
            case 8u16 => IntrinsicKind.ARRAY_GET
            case 9u16 => IntrinsicKind.ARRAY_SET
            case 10u16 => IntrinsicKind.ARRAY_GET_UNCHECKED
            case 11u16 => IntrinsicKind.ARRAY_GET_REF_UNCHECKED
            case 12u16 => IntrinsicKind.ARRAY_SET_UNCHECKED
            case 13u16 => IntrinsicKind.ARRAY_SIZE
            case 14u16 => IntrinsicKind.ARRAY_CLONE
            case 15u16 => IntrinsicKind.ARRAY_SLICE_INIT
            case 16u16 => IntrinsicKind.ARRAY_SLICE
            case 17u16 => IntrinsicKind.ARRAY_SLICE_RAWARRAY
            case 18u16 => IntrinsicKind.ARRAY_SLICE_START
            case 19u16 => IntrinsicKind.ARRAY_SLICE_SIZE
            case 20u16 => IntrinsicKind.ARRAY_SLICE_GET_ELEMENT
            case 21u16 => IntrinsicKind.ARRAY_SLICE_GET_ELEMENT_UNCHECKED
            case 22u16 => IntrinsicKind.ARRAY_SLICE_SET_ELEMENT
            case 23u16 => IntrinsicKind.ARRAY_SLICE_SET_ELEMENT_UNCHECKED
            case 24u16 => IntrinsicKind.FILL_IN_STACK_TRACE
            case 25u16 => IntrinsicKind.DECODE_STACK_TRACE
            case 26u16 => IntrinsicKind.DUMP_CURRENT_THREAD_INFO
            case 27u16 => IntrinsicKind.DUMP_ALL_THREADS_INFO
            case 28u16 => IntrinsicKind.CHR
            case 29u16 => IntrinsicKind.ORD
            case 30u16 => IntrinsicKind.CPOINTER_GET_POINTER_ADDRESS
            case 31u16 => IntrinsicKind.CPOINTER_INIT0
            case 32u16 => IntrinsicKind.CPOINTER_INIT1
            case 33u16 => IntrinsicKind.CPOINTER_READ
            case 34u16 => IntrinsicKind.CPOINTER_WRITE
            case 35u16 => IntrinsicKind.CPOINTER_ADD
            case 36u16 => IntrinsicKind.CSTRING_INIT
            case 37u16 => IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR
            case 38u16 => IntrinsicKind.INOUT_PARAM
            case 39u16 => IntrinsicKind.REGISTER_WATCHED_OBJECT
            case 40u16 => IntrinsicKind.OBJECT_REFEQ
            case 41u16 => IntrinsicKind.RAW_ARRAY_REFEQ
            case 42u16 => IntrinsicKind.FUNC_REFEQ
            case 43u16 => IntrinsicKind.OBJECT_ZERO_VALUE
            case 44u16 => IntrinsicKind.INVOKE_GC
            case 45u16 => IntrinsicKind.SET_GC_THRESHOLD
            case 46u16 => IntrinsicKind.DUMP_CJ_HEAP_DATA
            case 47u16 => IntrinsicKind.GET_GC_COUNT
            case 48u16 => IntrinsicKind.GET_GC_TIME_US
            case 49u16 => IntrinsicKind.GET_GC_FREED_SIZE
            case 50u16 => IntrinsicKind.START_CJ_CPU_PROFILING
            case 51u16 => IntrinsicKind.STOP_CJ_CPU_PROFILING
            case 52u16 => IntrinsicKind.BLACK_BOX
            case 53u16 => IntrinsicKind.GET_MAX_HEAP_SIZE
            case 54u16 => IntrinsicKind.GET_ALLOCATE_HEAP_SIZE
            case 55u16 => IntrinsicKind.GET_REAL_HEAP_SIZE
            case 56u16 => IntrinsicKind.GET_THREAD_NUMBER
            case 57u16 => IntrinsicKind.GET_BLOCKING_THREAD_NUMBER
            case 58u16 => IntrinsicKind.GET_NATIVE_THREAD_NUMBER
            case 59u16 => IntrinsicKind.VARRAY_SET
            case 60u16 => IntrinsicKind.VARRAY_GET
            case 61u16 => IntrinsicKind.FUTURE_INIT
            case 62u16 => IntrinsicKind.FUTURE_IS_COMPLETE
            case 63u16 => IntrinsicKind.FUTURE_WAIT
            case 64u16 => IntrinsicKind.FUTURE_NOTIFYALL
            case 65u16 => IntrinsicKind.IS_THREAD_OBJECT_INITED
            case 66u16 => IntrinsicKind.GET_THREAD_OBJECT
            case 67u16 => IntrinsicKind.SET_THREAD_OBJECT
            case 68u16 => IntrinsicKind.OVERFLOW_CHECKED_ADD
            case 69u16 => IntrinsicKind.OVERFLOW_CHECKED_SUB
            case 70u16 => IntrinsicKind.OVERFLOW_CHECKED_MUL
            case 71u16 => IntrinsicKind.OVERFLOW_CHECKED_DIV
            case 72u16 => IntrinsicKind.OVERFLOW_CHECKED_MOD
            case 73u16 => IntrinsicKind.OVERFLOW_CHECKED_POW
            case 74u16 => IntrinsicKind.OVERFLOW_CHECKED_INC
            case 75u16 => IntrinsicKind.OVERFLOW_CHECKED_DEC
            case 76u16 => IntrinsicKind.OVERFLOW_CHECKED_NEG
            case 77u16 => IntrinsicKind.OVERFLOW_THROWING_ADD
            case 78u16 => IntrinsicKind.OVERFLOW_THROWING_SUB
            case 79u16 => IntrinsicKind.OVERFLOW_THROWING_MUL
            case 80u16 => IntrinsicKind.OVERFLOW_THROWING_DIV
            case 81u16 => IntrinsicKind.OVERFLOW_THROWING_MOD
            case 82u16 => IntrinsicKind.OVERFLOW_THROWING_POW
            case 83u16 => IntrinsicKind.OVERFLOW_THROWING_INC
            case 84u16 => IntrinsicKind.OVERFLOW_THROWING_DEC
            case 85u16 => IntrinsicKind.OVERFLOW_THROWING_NEG
            case 86u16 => IntrinsicKind.OVERFLOW_SATURATING_ADD
            case 87u16 => IntrinsicKind.OVERFLOW_SATURATING_SUB
            case 88u16 => IntrinsicKind.OVERFLOW_SATURATING_MUL
            case 89u16 => IntrinsicKind.OVERFLOW_SATURATING_DIV
            case 90u16 => IntrinsicKind.OVERFLOW_SATURATING_MOD
            case 91u16 => IntrinsicKind.OVERFLOW_SATURATING_POW
            case 92u16 => IntrinsicKind.OVERFLOW_SATURATING_INC
            case 93u16 => IntrinsicKind.OVERFLOW_SATURATING_DEC
            case 94u16 => IntrinsicKind.OVERFLOW_SATURATING_NEG
            case 95u16 => IntrinsicKind.OVERFLOW_WRAPPING_ADD
            case 96u16 => IntrinsicKind.OVERFLOW_WRAPPING_SUB
            case 97u16 => IntrinsicKind.OVERFLOW_WRAPPING_MUL
            case 98u16 => IntrinsicKind.OVERFLOW_WRAPPING_DIV
            case 99u16 => IntrinsicKind.OVERFLOW_WRAPPING_MOD
            case 100u16 => IntrinsicKind.OVERFLOW_WRAPPING_POW
            case 101u16 => IntrinsicKind.OVERFLOW_WRAPPING_INC
            case 102u16 => IntrinsicKind.OVERFLOW_WRAPPING_DEC
            case 103u16 => IntrinsicKind.OVERFLOW_WRAPPING_NEG
            case 104u16 => IntrinsicKind.VECTOR_COMPARE_32
            case 105u16 => IntrinsicKind.VECTOR_INDEX_BYTE_32
            case 106u16 => IntrinsicKind.CJ_CORE_CAN_USE_SIMD
            case 107u16 => IntrinsicKind.CJ_TLS_DYN_SET_SESSION_CALLBACK
            case 108u16 => IntrinsicKind.CJ_TLS_DYN_SSL_INIT
            case 109u16 => IntrinsicKind.REFLECTION_INTRINSIC_START_FLAG
            case 110u16 => IntrinsicKind.IS_INTERFACE
            case 111u16 => IntrinsicKind.IS_CLASS
            case 112u16 => IntrinsicKind.IS_PRIMITIVE
            case 113u16 => IntrinsicKind.IS_STRUCT
            case 114u16 => IntrinsicKind.IS_GENERIC
            case 115u16 => IntrinsicKind.IS_TUPLE
            case 116u16 => IntrinsicKind.IS_FUNCTION
            case 117u16 => IntrinsicKind.IS_ENUM
            case 118u16 => IntrinsicKind.IS_BOX
            case 119u16 => IntrinsicKind.GET_OR_CREATE_TYPEINFO_FOR_REFLECT
            case 120u16 => IntrinsicKind.GET_TYPETEMPLATE
            case 121u16 => IntrinsicKind.CHECK_METHOD_ACTUAL_ARGS
            case 122u16 => IntrinsicKind.METHOD_ENTRYPOINT_IS_NULL
            case 123u16 => IntrinsicKind.IS_RELECT_UNSUPPORTED_TYPE
            case 124u16 => IntrinsicKind.GET_TYPE_FOR_ANY
            case 125u16 => IntrinsicKind.GET_TYPE_BY_MANGLED_NAME
            case 126u16 => IntrinsicKind.GET_TYPE_NAME
            case 127u16 => IntrinsicKind.GET_TYPE_BY_QUALIFIED_NAME
            case 128u16 => IntrinsicKind.GET_TYPE_QUALIFIED_NAME_LENGTH
            case 129u16 => IntrinsicKind.GET_TYPE_QUALIFIED_NAME
            case 130u16 => IntrinsicKind.GET_NUM_OF_INTERFACE
            case 131u16 => IntrinsicKind.GET_INTERFACE
            case 132u16 => IntrinsicKind.IS_SUBTYPE
            case 133u16 => IntrinsicKind.GET_TYPE_INFO_MODIFIER
            case 134u16 => IntrinsicKind.GET_TYPE_INFO_ANNOTATIONS
            case 135u16 => IntrinsicKind.GET_OBJ_CLASS
            case 136u16 => IntrinsicKind.GET_SUPER_TYPE_INFO
            case 137u16 => IntrinsicKind.GET_TYPE_ARGS
            case 138u16 => IntrinsicKind.GET_NUM_OF_INSTANCE_METHOD_INFOS
            case 139u16 => IntrinsicKind.GET_INSTANCE_METHOD_INFO
            case 140u16 => IntrinsicKind.GET_NUM_OF_STATIC_METHOD_INFOS
            case 141u16 => IntrinsicKind.GET_STATIC_METHOD_INFO
            case 142u16 => IntrinsicKind.GET_METHOD_NAME
            case 143u16 => IntrinsicKind.GET_METHOD_RETURN_TYPE
            case 144u16 => IntrinsicKind.GET_METHOD_MODIFIER
            case 145u16 => IntrinsicKind.GET_METHOD_ANNOTATIONS
            case 146u16 => IntrinsicKind.APPLY_CJ_METHOD
            case 147u16 => IntrinsicKind.APPLY_CJ_STATIC_METHOD
            case 148u16 => IntrinsicKind.APPLY_CJ_GENERIC_METHOD
            case 149u16 => IntrinsicKind.APPLY_CJ_GENERIC_STATIC_METHOD
            case 150u16 => IntrinsicKind.GET_NUM_OF_ACTUAL_PARAMETERS
            case 151u16 => IntrinsicKind.GET_NUM_OF_GENERIC_PARAMETERS
            case 152u16 => IntrinsicKind.GET_ACTUAL_PARAMETER_INFO
            case 153u16 => IntrinsicKind.GET_GENERIC_PARAMETER_INFO
            case 154u16 => IntrinsicKind.GET_NUM_OF_INSTANCE_FIELD_INFOS
            case 155u16 => IntrinsicKind.GET_INSTANCE_FIELD_INFO
            case 156u16 => IntrinsicKind.GET_NUM_OF_STATIC_FIELD_INFOS
            case 157u16 => IntrinsicKind.GET_STATIC_FIELD_INFO
            case 158u16 => IntrinsicKind.GET_STATIC_FIELD_NAME
            case 159u16 => IntrinsicKind.GET_STATIC_FIELD_TYPE
            case 160u16 => IntrinsicKind.GET_STATIC_FIELD_ANNOTATIONS
            case 161u16 => IntrinsicKind.GET_INSTANCE_FIELD_NAME
            case 162u16 => IntrinsicKind.GET_INSTANCE_FIELD_TYPE
            case 163u16 => IntrinsicKind.GET_INSTANCE_FIELD_ANNOTATIONS
            case 164u16 => IntrinsicKind.GET_INSTANCE_FIELD_MODIFIER
            case 165u16 => IntrinsicKind.GET_STATIC_FIELD_MODIFIER
            case 166u16 => IntrinsicKind.GET_FIELD_VALUE
            case 167u16 => IntrinsicKind.SET_FIELD_VALUE
            case 168u16 => IntrinsicKind.GET_STATIC_FIELD_VALUE
            case 169u16 => IntrinsicKind.SET_STATIC_FIELD_VALUE
            case 170u16 => IntrinsicKind.GET_FIELD_DECLARING_TYPE
            case 171u16 => IntrinsicKind.GET_PARAMETER_INDEX
            case 172u16 => IntrinsicKind.GET_PARAMETER_NAME
            case 173u16 => IntrinsicKind.GET_PARAMETER_TYPE
            case 174u16 => IntrinsicKind.GET_PARAMETER_ANNOTATIONS
            case 175u16 => IntrinsicKind.GET_RELATED_PACKAGE_INF
            case 176u16 => IntrinsicKind.GET_PACKAGE_NAME
            case 177u16 => IntrinsicKind.GET_PACKAGE_NUM_OF_TYPE_INFOS
            case 178u16 => IntrinsicKind.GET_PACKAGE_TYPE_INFO
            case 179u16 => IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_METHODS
            case 180u16 => IntrinsicKind.GET_PACKAGE_GLOBAL_METHOD_INFO
            case 181u16 => IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_FIELD_INFOS
            case 182u16 => IntrinsicKind.GET_PACKAGE_GLOBAL_FIELD_INFO
            case 183u16 => IntrinsicKind.LOAD_PACKAGE
            case 184u16 => IntrinsicKind.GET_PACKAGE_BY_QUALIFIEDNAME
            case 185u16 => IntrinsicKind.GET_PACKAGE_VERSION
            case 186u16 => IntrinsicKind.GET_SUB_PACKAGES
            case 187u16 => IntrinsicKind.GET_NUM_OF_FIELD_TYPES
            case 188u16 => IntrinsicKind.GET_FIELD_TYPES
            case 189u16 => IntrinsicKind.NEW_AND_INIT_OBJECT
            case 190u16 => IntrinsicKind.GET_ASSOCIATED_VALUES
            case 191u16 => IntrinsicKind.GET_NUM_OF_FUNCTION_SIGNATURETYPES
            case 192u16 => IntrinsicKind.GET_FUNCTION_SIGNATURE_TYPES
            case 193u16 => IntrinsicKind.GET_NUM_OF_ENUM_CONSTRUCTOR_INFOS
            case 194u16 => IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO
            case 195u16 => IntrinsicKind.GET_ENUM_CONSTRUCTOR_NAME
            case 196u16 => IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO_FROM_ANY
            case 197u16 => IntrinsicKind.REFLECTION_INTRINSIC_END_FLAG
            case 198u16 => IntrinsicKind.SLEEP
            case 199u16 => IntrinsicKind.SOURCE_FILE
            case 200u16 => IntrinsicKind.SOURCE_LINE
            case 201u16 => IntrinsicKind.IDENTITY_HASHCODE
            case 202u16 => IntrinsicKind.IDENTITY_HASHCODE_FOR_ARRAY
            case 203u16 => IntrinsicKind.ATOMIC_LOAD
            case 204u16 => IntrinsicKind.ATOMIC_STORE
            case 205u16 => IntrinsicKind.ATOMIC_SWAP
            case 206u16 => IntrinsicKind.ATOMIC_COMPARE_AND_SWAP
            case 207u16 => IntrinsicKind.ATOMIC_FETCH_ADD
            case 208u16 => IntrinsicKind.ATOMIC_FETCH_SUB
            case 209u16 => IntrinsicKind.ATOMIC_FETCH_AND
            case 210u16 => IntrinsicKind.ATOMIC_FETCH_OR
            case 211u16 => IntrinsicKind.ATOMIC_FETCH_XOR
            case 212u16 => IntrinsicKind.MUTEX_INIT
            case 213u16 => IntrinsicKind.CJ_MUTEX_LOCK
            case 214u16 => IntrinsicKind.MUTEX_TRY_LOCK
            case 215u16 => IntrinsicKind.MUTEX_CHECK_STATUS
            case 216u16 => IntrinsicKind.MUTEX_UNLOCK
            case 217u16 => IntrinsicKind.WAITQUEUE_INIT
            case 218u16 => IntrinsicKind.MONITOR_INIT
            case 219u16 => IntrinsicKind.MOITIOR_WAIT
            case 220u16 => IntrinsicKind.MOITIOR_NOTIFY
            case 221u16 => IntrinsicKind.MOITIOR_NOTIFY_ALL
            case 222u16 => IntrinsicKind.MULTICONDITION_WAIT
            case 223u16 => IntrinsicKind.MULTICONDITION_NOTIFY
            case 224u16 => IntrinsicKind.MULTICONDITION_NOTIFY_ALL
            case 225u16 => IntrinsicKind.CROSS_ACCESS_BARRIER
            case 226u16 => IntrinsicKind.CREATE_EXPORT_HANDLE
            case 227u16 => IntrinsicKind.GET_EXPORTED_REF
            case 228u16 => IntrinsicKind.REMOVE_EXPORTED_REF
            case 229u16 => IntrinsicKind.GET_JSLAMBDA_ADDR
            case 230u16 => IntrinsicKind.FFI_CJ_AST_LEX
            case 231u16 => IntrinsicKind.FFI_CJ_AST_PARSEEXPR
            case 232u16 => IntrinsicKind.FFI_CJ_AST_PARSEDECL
            case 233u16 => IntrinsicKind.FFI_CJ_AST_PARSE_PROPMEMBERDECL
            case 234u16 => IntrinsicKind.FFI_CJ_AST_PARSE_PRICONSTRUCTOR
            case 235u16 => IntrinsicKind.FFI_CJ_AST_PARSE_PATTERN
            case 236u16 => IntrinsicKind.FFI_CJ_AST_PARSE_TYPE
            case 237u16 => IntrinsicKind.FFI_CJ_AST_PARSETOPLEVEL
            case 238u16 => IntrinsicKind.FFI_CJ_AST_DIAGREPORT
            case 239u16 => IntrinsicKind.FFI_CJ_PARENT_CONTEXT
            case 240u16 => IntrinsicKind.FFI_CJ_MACRO_ITEM_INFO
            case 241u16 => IntrinsicKind.FFI_CJ_GET_CHILD_MESSAGES
            case 242u16 => IntrinsicKind.FFI_CJ_CHECK_ADD_SPACE
            case 243u16 => IntrinsicKind.CG_UNSAFE_BEGIN
            case 244u16 => IntrinsicKind.CG_UNSAFE_END
            case 245u16 => IntrinsicKind.STRLEN
            case 246u16 => IntrinsicKind.MEMCPY_S
            case 247u16 => IntrinsicKind.MEMSET_S
            case 248u16 => IntrinsicKind.FREE
            case 249u16 => IntrinsicKind.MALLOC
            case 250u16 => IntrinsicKind.STRCMP
            case 251u16 => IntrinsicKind.MEMCMP
            case 252u16 => IntrinsicKind.STRNCMP
            case 253u16 => IntrinsicKind.STRCASECMP
            case 254u16 => IntrinsicKind.ATOMIC_INT8_LOAD
            case 255u16 => IntrinsicKind.ATOMIC_INT8_STORE
            case 256u16 => IntrinsicKind.ATOMIC_INT8_SWAP
            case 257u16 => IntrinsicKind.ATOMIC_INT8_CAS
            case 258u16 => IntrinsicKind.ATOMIC_INT8_FETCH_ADD
            case 259u16 => IntrinsicKind.ATOMIC_INT8_FETCH_SUB
            case 260u16 => IntrinsicKind.ATOMIC_INT8_FETCH_AND
            case 261u16 => IntrinsicKind.ATOMIC_INT8_FETCH_OR
            case 262u16 => IntrinsicKind.ATOMIC_INT8_FETCH_XOR
            case 263u16 => IntrinsicKind.ATOMIC_INT16_LOAD
            case 264u16 => IntrinsicKind.ATOMIC_INT16_STORE
            case 265u16 => IntrinsicKind.ATOMIC_INT16_SWAP
            case 266u16 => IntrinsicKind.ATOMIC_INT16_CAS
            case 267u16 => IntrinsicKind.ATOMIC_INT16_FETCH_ADD
            case 268u16 => IntrinsicKind.ATOMIC_INT16_FETCH_SUB
            case 269u16 => IntrinsicKind.ATOMIC_INT16_FETCH_AND
            case 270u16 => IntrinsicKind.ATOMIC_INT16_FETCH_OR
            case 271u16 => IntrinsicKind.ATOMIC_INT16_FETCH_XOR
            case 272u16 => IntrinsicKind.ATOMIC_INT32_LOAD
            case 273u16 => IntrinsicKind.ATOMIC_INT32_STORE
            case 274u16 => IntrinsicKind.ATOMIC_INT32_SWAP
            case 275u16 => IntrinsicKind.ATOMIC_INT32_CAS
            case 276u16 => IntrinsicKind.ATOMIC_INT32_FETCH_ADD
            case 277u16 => IntrinsicKind.ATOMIC_INT32_FETCH_SUB
            case 278u16 => IntrinsicKind.ATOMIC_INT32_FETCH_AND
            case 279u16 => IntrinsicKind.ATOMIC_INT32_FETCH_OR
            case 280u16 => IntrinsicKind.ATOMIC_INT32_FETCH_XOR
            case 281u16 => IntrinsicKind.ATOMIC_INT64_LOAD
            case 282u16 => IntrinsicKind.ATOMIC_INT64_STORE
            case 283u16 => IntrinsicKind.ATOMIC_INT64_SWAP
            case 284u16 => IntrinsicKind.ATOMIC_INT64_CAS
            case 285u16 => IntrinsicKind.ATOMIC_INT64_FETCH_ADD
            case 286u16 => IntrinsicKind.ATOMIC_INT64_FETCH_SUB
            case 287u16 => IntrinsicKind.ATOMIC_INT64_FETCH_AND
            case 288u16 => IntrinsicKind.ATOMIC_INT64_FETCH_OR
            case 289u16 => IntrinsicKind.ATOMIC_INT64_FETCH_XOR
            case 290u16 => IntrinsicKind.ATOMIC_UINT8_LOAD
            case 291u16 => IntrinsicKind.ATOMIC_UINT8_STORE
            case 292u16 => IntrinsicKind.ATOMIC_UINT8_SWAP
            case 293u16 => IntrinsicKind.ATOMIC_UINT8_CAS
            case 294u16 => IntrinsicKind.ATOMIC_UINT8_FETCH_ADD
            case 295u16 => IntrinsicKind.ATOMIC_UINT8_FETCH_SUB
            case 296u16 => IntrinsicKind.ATOMIC_UINT8_FETCH_AND
            case 297u16 => IntrinsicKind.ATOMIC_UINT8_FETCH_OR
            case 298u16 => IntrinsicKind.ATOMIC_UINT8_FETCH_XOR
            case 299u16 => IntrinsicKind.ATOMIC_UINT16_LOAD
            case 300u16 => IntrinsicKind.ATOMIC_UINT16_STORE
            case 301u16 => IntrinsicKind.ATOMIC_UINT16_SWAP
            case 302u16 => IntrinsicKind.ATOMIC_UINT16_CAS
            case 303u16 => IntrinsicKind.ATOMIC_UINT16_FETCH_ADD
            case 304u16 => IntrinsicKind.ATOMIC_UINT16_FETCH_SUB
            case 305u16 => IntrinsicKind.ATOMIC_UINT16_FETCH_AND
            case 306u16 => IntrinsicKind.ATOMIC_UINT16_FETCH_OR
            case 307u16 => IntrinsicKind.ATOMIC_UINT16_FETCH_XOR
            case 308u16 => IntrinsicKind.ATOMIC_UINT32_LOAD
            case 309u16 => IntrinsicKind.ATOMIC_UINT32_STORE
            case 310u16 => IntrinsicKind.ATOMIC_UINT32_SWAP
            case 311u16 => IntrinsicKind.ATOMIC_UINT32_CAS
            case 312u16 => IntrinsicKind.ATOMIC_UINT32_FETCH_ADD
            case 313u16 => IntrinsicKind.ATOMIC_UINT32_FETCH_SUB
            case 314u16 => IntrinsicKind.ATOMIC_UINT32_FETCH_AND
            case 315u16 => IntrinsicKind.ATOMIC_UINT32_FETCH_OR
            case 316u16 => IntrinsicKind.ATOMIC_UINT32_FETCH_XOR
            case 317u16 => IntrinsicKind.ATOMIC_UINT64_LOAD
            case 318u16 => IntrinsicKind.ATOMIC_UINT64_STORE
            case 319u16 => IntrinsicKind.ATOMIC_UINT64_SWAP
            case 320u16 => IntrinsicKind.ATOMIC_UINT64_CAS
            case 321u16 => IntrinsicKind.ATOMIC_UINT64_FETCH_ADD
            case 322u16 => IntrinsicKind.ATOMIC_UINT64_FETCH_SUB
            case 323u16 => IntrinsicKind.ATOMIC_UINT64_FETCH_AND
            case 324u16 => IntrinsicKind.ATOMIC_UINT64_FETCH_OR
            case 325u16 => IntrinsicKind.ATOMIC_UINT64_FETCH_XOR
            case 326u16 => IntrinsicKind.ATOMIC_BOOL_LOAD
            case 327u16 => IntrinsicKind.ATOMIC_BOOL_STORE
            case 328u16 => IntrinsicKind.ATOMIC_BOOL_SWAP
            case 329u16 => IntrinsicKind.ATOMIC_BOOL_CAS
            case 330u16 => IntrinsicKind.ATOMIC_REFERENCEBASE_LOAD
            case 331u16 => IntrinsicKind.ATOMIC_REFERENCEBASE_STORE
            case 332u16 => IntrinsicKind.ATOMIC_REFERENCEBASE_SWAP
            case 333u16 => IntrinsicKind.ATOMIC_REFERENCEBASE_CAS
            case 334u16 => IntrinsicKind.ATOMIC_OPTIONREFERENCE_LOAD
            case 335u16 => IntrinsicKind.ATOMIC_OPTIONREFERENCE_STORE
            case 336u16 => IntrinsicKind.ATOMIC_OPTIONREFERENCE_SWAP
            case 337u16 => IntrinsicKind.ATOMIC_OPTIONREFERENCE_CAS
            case 338u16 => IntrinsicKind.BEGIN_CATCH
            case 339u16 => IntrinsicKind.ABS
            case 340u16 => IntrinsicKind.FABS
            case 341u16 => IntrinsicKind.FLOOR
            case 342u16 => IntrinsicKind.CEIL
            case 343u16 => IntrinsicKind.TRUNC
            case 344u16 => IntrinsicKind.SIN
            case 345u16 => IntrinsicKind.COS
            case 346u16 => IntrinsicKind.EXP
            case 347u16 => IntrinsicKind.EXP2
            case 348u16 => IntrinsicKind.LOG
            case 349u16 => IntrinsicKind.LOG2
            case 350u16 => IntrinsicKind.LOG10
            case 351u16 => IntrinsicKind.SQRT
            case 352u16 => IntrinsicKind.ROUND
            case 353u16 => IntrinsicKind.POW
            case 354u16 => IntrinsicKind.POWI
            case 355u16 => IntrinsicKind.BIT_CAST
            case 356u16 => IntrinsicKind.PREINITIALIZE
            case 357u16 => IntrinsicKind.OBJECT_AS
            case 358u16 => IntrinsicKind.IS_NULL
            case 359u16 => IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER
            case 360u16 => IntrinsicKind.IS_SUBTYPE_TYPES
            case 361u16 => IntrinsicKind.EXCLUSIVE_SCOPE
            case _ =>
                CJC_ABORT()
                IntrinsicKind.NOT_INTRINSIC
        }
        let operands = GetValue<Value>(base.GetOperands())
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let exceptionBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let normalBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let callContext = IntrisicCallContext(kind: intrinsicKind, args: operands,
                instTypeArgs: GetType<Type>(funcCallBase.GetInstantiatedTypeArgs()))
            return builder.CreateIntrinsicWithException(resultTy, callContext, normalBlock, exceptionBlock, owner)
        }
        let callContext = IntrisicCallContext(kind: intrinsicKind, args: operands,
            instTypeArgs: GetType<Type>(funcCallBase.GetInstantiatedTypeArgs()))
        return builder.CreateIntrinsic(resultTy, callContext, owner)
    }

    private func Deserialize(obj: PackageFormat_RawArrayAllocateBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let elementType = GetType<Type>(obj.GetElementType()).getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let size = operands[0]
        operands.remove(at: 0)
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let exceptionBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let normalBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            return builder.CreateRawArrayAllocateWithException(resultTy, elementType, size, normalBlock,
                exceptionBlock, owner)
        }
        return builder.CreateRawArrayAllocate(resultTy, elementType, size, owner)
    }

    private func Deserialize(obj: PackageFormat_SpawnBase): Expression {
        let base = obj.GetBase().getOrThrow()
        let operands = GetValue<Value>(base.GetOperands())
        let value = operands[0]
        operands.remove(at: 0)
        let executeClosure = GetValue<Function>(obj.GetExecuteClosure())
        let resultTy = GetType<Type>(base.GetResultTy()).getOrThrow()
        let owner = GetValue<Block>(base.GetOwner()).getOrThrow()
        let (_, isException) = CHIRExprKindToExprKind(base.GetKind())
        if (isException) {
            let exceptionBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let normalBlock = (operands[operands.size - 1] as Block).getOrThrow()
            operands.remove(at: operands.size - 1)
            let expression = if (operands.isEmpty()) {
                builder.CreateSpawnWithException(resultTy, value, normalBlock, exceptionBlock, owner)
            } else {
                builder.CreateSpawnWithException(resultTy, value, operands[0], normalBlock, exceptionBlock, owner)
            }
            if (let Some(fn) <- executeClosure) {
                expression.SetExecuteClosure(fn)
            }
            return expression
        }
        let expression = if (operands.isEmpty()) {
            builder.CreateSpawn(resultTy, value, owner)
        } else {
            builder.CreateSpawn(resultTy, value, operands[0], owner)
        }
        if (let Some(fn) <- executeClosure) {
            expression.SetExecuteClosure(fn)
        }
        return expression
    }

    private func Deserialize(obj: PackageFormat_GetRTTIStatic): GetRTTIStatic {
        let base = obj.GetBase().getOrThrow()
        return builder.CreateGetRTTIStatic(GetType<Type>(base.GetResultTy()).getOrThrow(),
            GetType<Type>(obj.GetRttiType()).getOrThrow(), GetValue<Block>(base.GetOwner()).getOrThrow())
    }

    private func ConfigExpression(buffer: PackageFormat_Expression, obj: Expression): Unit {
        ConfigBase(buffer.GetBase().getOrThrow(), obj)
    }

    private func ConfigLambda(buffer: PackageFormat_Lambda, obj: Lambda): Unit {
        ConfigExpression(buffer.GetBase().getOrThrow(), obj)
        GetValue<Parameter>(buffer.GetParams())
        if (let Some(returnValue) <- GetValue<LocalVar>(buffer.GetRetVal())) {
            obj.SetReturnValue(returnValue)
        }
    }

    private func ConfigCustomTypeDef(buffer: PackageFormat_CustomTypeDef, obj: CustomTypeDef): Unit {
        ConfigBase(buffer.GetBase().getOrThrow(), obj)
        obj.SetSrcCodeIdentifier(buffer.GetSrcCodeIdentifier().getOrThrow().str())
        obj.SetType(GetType<CustomType>(buffer.GetType()).getOrThrow())
        if (buffer.GetGenericDecl() != 0u32) {
            obj.SetGenericDecl(GetCustomTypeDef<CustomTypeDef>(buffer.GetGenericDecl()).getOrThrow())
        }
        for (method in GetValue<Function>(buffer.GetMethods())) { obj.AddMethod(method) }
        for (interfaceType in GetType<ClassType>(buffer.GetImplementedInterfaces())) {
            obj.AddImplementedInterfaceTy(interfaceType)
        }
        if (let Some(rawVars) <- buffer.GetInstanceMemberVars()) {
            var index = 0u32
            while (index < rawVars.size()) {
                let position = (rawVars.Get(index) as Int64).getOrThrow()
                obj.AddInstanceVar(Create(PackageFormat_MemberVarInfo(rawVars.data, position)))
                index++
            }
        }
        for (variable in GetValue<GlobalVar>(buffer.GetStaticMemberVars())) { obj.AddStaticMemberVar(variable) }
        if (compilePlatform) { obj.EnableAttr(Attribute.DESERIALIZED) }
        obj.SetAnnoInfo(Create(buffer.GetAnnoInfo().getOrThrow()))
        obj.SetVTable(Create(buffer.GetVtable().getOrThrow()))
        obj.SetVarInitializationFunc(GetValue<Function>(buffer.GetInstanceVarInitFunc()))
    }

    private func Config(buffer: PackageFormat_Function, obj: Function): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigBase(buffer.GetBase().getOrThrow().GetBase().getOrThrow().GetBase().getOrThrow(), obj)
        if (buffer.GetParamDftValHostFunc() != 0u32) {
            obj.SetParamDftValHostFunc(GetValue<Function>(buffer.GetParamDftValHostFunc()).getOrThrow())
        }
        if (buffer.GetGenericDecl() != 0u32) {
            obj.SetGenericDecl(GetValue<Function>(buffer.GetGenericDecl()).getOrThrow())
        }
        if (let Some(rawAnno) <- buffer.GetBase().getOrThrow().GetAnnoInfo()) { obj.SetAnnoInfo(Create(rawAnno)) }
        let params = GetValue<Parameter>(buffer.GetParams())
        obj.RemoveParams()
        for (param in params) { obj.AddParam(param) }
        if (buffer.GetBody() != 0u32) {
            if (let Some(body) <- GetValue<BlockGroup>(buffer.GetBody())) {
                obj.InitBody(body)
            } else {
                CJC_ASSERT(obj.TestAttr(Attribute.COMMON))
            }
            obj.SetFuncKind(CHIRFuncKindFromIndex(Int64(buffer.GetFuncKind())))
            if (let Some(retVal) <- GetValue<LocalVar>(buffer.GetRetVal())) { obj.SetReturnValue(retVal) }
            obj.SetRawMangledName(buffer.GetBase().getOrThrow().GetRawMangledName().getOrThrow().str())
            if (compilePlatform) { obj.EnableAttr(Attribute.DESERIALIZED) }
            obj.SetPropLocation(Create(buffer.GetPropLoc().getOrThrow()))
            if (let Some(rawInfo) <- buffer.GetOriginalLambdaInfo()) {
                obj.SetOriginalLambdaInfo(FuncSigInfo(GetType<FuncType>(rawInfo.GetFuncType()).getOrThrow(),
                    funcName: if (let Some(name) <- rawInfo.GetFuncName()) { name.str() } else { "" },
                    genericTypeParams: GetType<GenericType>(rawInfo.GetGenericTypeParams())))
            }
            if (let Some(retVal) <- GetValue<LocalVar>(buffer.GetRetVal())) { obj.SetReturnValue(retVal) }
        }
    }

    private func Config(buffer: PackageFormat_BlockGroup, obj: BlockGroup): Unit {
        ConfigValue(buffer.GetBase().getOrThrow(), obj)
        GetValue<Block>(buffer.GetBlocks())
        obj.SetEntryBlock(GetValue<Block>(buffer.GetEntryBlock()))
    }

    private func Config(buffer: PackageFormat_Block, obj: Block): Unit {
        ConfigValue(buffer.GetBase().getOrThrow(), obj)
        if (buffer.GetIsLandingPadBlock()) { obj.SetExceptions(GetType<ClassType>(buffer.GetExceptionCatchList())) }
        obj.AppendExpressions(GetExpression<Expression>(buffer.GetExprs()))
        obj.ClearPredecessorsOnly()
        for (predecessor in GetValue<Block>(buffer.GetPredecessors())) { obj.AppendPredecessorOnly(predecessor) }
    }

    private func Config(buffer: PackageFormat_GlobalVar, obj: GlobalVar): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigBase(buffer.GetBase().getOrThrow().GetBase().getOrThrow().GetBase().getOrThrow(), obj)
        if (let Some(rawAnno) <- buffer.GetBase().getOrThrow().GetAnnoInfo()) { obj.SetAnnoInfo(Create(rawAnno)) }
        if (buffer.GetInitializer() != 0u32) {
            if (let Some(initializer) <- GetValue<Value>(buffer.GetInitializer())) {
                if (let Some(literal) <- (initializer as LiteralValue)) {
                    obj.SetInitializer(literal)
                } else if (let Some(initFunc) <- (initializer as Function)) {
                    obj.SetInitFunc(initFunc)
                }
            }
        }
    }

    private func Config(buffer: PackageFormat_EnumDef, obj: EnumDef): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigCustomTypeDef(buffer.GetBase().getOrThrow(), obj)
        if (let Some(rawCtors) <- buffer.GetCtors()) {
            var index = 0u32
            while (index < rawCtors.size()) {
                let position = (rawCtors.Get(index) as Int64).getOrThrow()
                obj.AddCtor(Create(PackageFormat_EnumCtorInfo(rawCtors.data, position)))
                index++
            }
        }
    }

    private func Config(buffer: PackageFormat_StructDef, obj: StructDef): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigCustomTypeDef(buffer.GetBase().getOrThrow(), obj)
        obj.SetCStruct(buffer.GetIsCStruct())
    }

    private func Config(buffer: PackageFormat_ClassDef, obj: ClassDef): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigCustomTypeDef(buffer.GetBase().getOrThrow(), obj)
        if (let Some(targets) <- buffer.GetAnnotationTargets()) { obj.SetAnnotationTargets(GetValue<GlobalVar>(targets)) }
        if (let Some(superClass) <- GetType<ClassType>(buffer.GetSuperClass())) { obj.SetSuperClassTy(superClass) }
    }

    private func Config(buffer: PackageFormat_ExtendDef, obj: ExtendDef): Unit {
        if (obj.TestAttr(Attribute.PREVIOUSLY_DESERIALIZED)) { return }
        ConfigCustomTypeDef(buffer.GetBase().getOrThrow(), obj)
        if (let Some(extendedType) <- GetType<Type>(buffer.GetExtendedType())) { obj.SetExtendedType(extendedType) }
    }

    private func GetExpression<T>(id: UInt32): Option<T> {
        if (id == 0u32) {
            return None
        }
        if (let Some(expression) <- id2Expression.get(id)) {
            return expression as T
        }
        let rawPackage = pool.getOrThrow()
        let expressions = rawPackage.GetExprs().getOrThrow()
        let kinds = rawPackage.GetExprs_type().getOrThrow()
        let kind = (kinds.Get(id - 1u32) as UInt8).getOrThrow()
        let position = (expressions.Get(id - 1u32) as Int64).getOrThrow()
        let expression: Expression
        match (kind) {
            case 1u8 =>
                let raw = PackageFormat_Expression(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw, expression)
            case 2u8 =>
                let raw = PackageFormat_AllocateBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 3u8 =>
                let raw = PackageFormat_ApplyBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow().GetBase().getOrThrow(), expression)
            case 4u8 =>
                let raw = PackageFormat_BinaryExpressionBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 5u8 =>
                let raw = PackageFormat_Branch(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 6u8 =>
                let raw = PackageFormat_Debug(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 7u8 =>
                let raw = PackageFormat_Field(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 8u8 =>
                let raw = PackageFormat_FieldByName(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 9u8 =>
                let raw = PackageFormat_GetElementByName(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 10u8 =>
                let raw = PackageFormat_GetElementRef(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 11u8 =>
                let raw = PackageFormat_GetInstantiateValue(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 12u8 =>
                let raw = PackageFormat_GetRTTIStatic(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 13u8 =>
                let raw = PackageFormat_InstanceOf(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 14u8 =>
                let raw = PackageFormat_IntrinsicBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow().GetBase().getOrThrow(), expression)
            case 15u8 =>
                let raw = PackageFormat_InvokeBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow().GetBase().getOrThrow(), expression)
            case 16u8 =>
                let raw = PackageFormat_Lambda(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigLambda(raw, (expression as Lambda).getOrThrow())
            case 17u8 =>
                let raw = PackageFormat_MultiBranch(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 18u8 =>
                let raw = PackageFormat_NumericCastBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 19u8 =>
                let raw = PackageFormat_RawArrayAllocateBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 20u8 =>
                let raw = PackageFormat_SpawnBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 21u8 =>
                let raw = PackageFormat_StoreElementByName(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 22u8 =>
                let raw = PackageFormat_StoreElementRef(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case 23u8 =>
                let raw = PackageFormat_UnaryExpressionBase(expressions.data, position)
                expression = Deserialize(raw)
                id2Expression[id] = expression
                ConfigExpression(raw.GetBase().getOrThrow(), expression)
            case _ =>
                CJC_ABORT()
                return id2Expression[id] as T
        }
        return expression as T
    }

}
