package cjcj::mangle

import std.collection.*
import cjcj::ast.*
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

private func unsupportedTy(kind: TypeKind, context: String): String {
    throw IllegalArgumentException(context + ": " + TypeKindName(kind))
}

private func isMangledToExportForTestBefore(decl: Decl, prefix: ArrayList<Node>): Bool {
    if (decl.TestAttr(Attribute.FOR_TEST)) {
        return true
    }
    for (node in prefix) {
        if (node.TestAttr(Attribute.FOR_TEST)) {
            return true
        }
    }
    return false
}

private func fnv1aHash(str: String): UInt64 {
    var hash: UInt64 = 2166136261u64
    for (ch in str.toArray()) {
        hash = ((hash ^ UInt64(ch)) * 16777619u64) & 0xffffffffu64
    }
    return hash
}

private func toBase62(value: UInt64): String {
    let base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    var current = value
    var result = ""
    while (current > 0u64) {
        let idx = Int64(current % UInt64(base62Chars.size))
        result += base62Chars[idx..idx + 1]
        current /= UInt64(base62Chars.size)
    }
    let length: Int64 = 13
    while (result.size < length) {
        result += "0"
    }
    var reversed = ""
    var idx = result.size - 1
    while (idx >= 0) {
        reversed += result[idx..idx + 1]
        idx--
    }
    return if (reversed.size > length) { reversed[0..length] } else { reversed }
}

public open class BaseMangler {
    public var moduleDelimiter: String = MANGLE_DOLLAR_PREFIX
    public var lambdaCounter: Int64 = 0
    public var exportIdMode: Bool = false
    // BaseMangler.h:184 unordered_map<string, Ptr<ManglerContext>>. HashMap so clear drops values
    // (ConcurrentHashMap.remove keeps removed values reachable).
    public let manglerCtxTable: HashMap<String, ManglerContext> = HashMap<String, ManglerContext>()

    public init() {}

    public init(delimiter: String) {
        moduleDelimiter = delimiter
    }

    public func ClearManglerCtxTable(): Unit {
        manglerCtxTable.clear()
    }

    public func MangleWithDeclPrefix(decl: Decl, prefix: ArrayList<Decl>): String {
        let nodePrefix = ArrayList<Node>()
        for (node in prefix) {
            nodePrefix.add(node)
        }
        return Mangle(decl, nodePrefix)
    }

    public func Mangle(decl: Decl): String {
        let prefix = ArrayList<Node>()
        var outerDecl = decl.outerDecl
        while (let Some(outer) <- outerDecl) {
            prefix.add(outer)
            outerDecl = outer.outerDecl
        }
        reverseDecls(prefix)
        return Mangle(decl, prefix)
    }

    public func Mangle(decl: Decl, prefix: ArrayList<Node>): String {
        if (decl.TestAttr(Attribute.NO_MANGLE)) {
            return decl.identifier.Val()
        }
        let genericsTypeStack = ArrayList<String>()
        if (decl.astKind == ASTKind.VAR_DECL) {
            return CJMangledCompression(MangleVarDecl((decl as VarDecl).getOrThrow(), prefix))
        }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            return CJMangledCompression(MangleFunctionDecl((decl as FuncDecl).getOrThrow(), prefix, genericsTypeStack, true))
        }
        if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            return CJMangledCompression(MangleVarWithPatternDecl((decl as VarWithPatternDecl).getOrThrow(), prefix))
        }
        return CJMangledCompression(DeclName(decl, prefix, genericsTypeStack, true))
    }

    public func MangleFunctionDecl(funcDecl: FuncDecl, prefix: ArrayList<Node>,
        genericsTypeStack: ArrayList<String>, _: Bool): String {
        if (!funcDecl.mangledName.isEmpty()) {
            return funcDecl.mangledName
        }
        if (funcDecl.TestAttr(Attribute.GENERIC_INSTANTIATED) && prefix.isEmpty()) {
            let newPrefix = ArrayList<Node>()
            var outerDecl = funcDecl.outerDecl
            while (let Some(outer) <- outerDecl) {
                newPrefix.add(outer)
                outerDecl = outer.outerDecl
            }
            reverseDecls(newPrefix)
            var mangled = DeclName(funcDecl, newPrefix, genericsTypeStack, true, withSuffix: false)
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
            mangled += MangleFuncParams(funcDecl, genericsTypeStack, false)
            return mangled
        }
        if (let None <- funcDecl.outerDecl) {
            if (let Some(special) <- GetSpecialFuncName(funcDecl)) {
                return special
            }
        }
        if (let Some(entryName) <- MangleEntryFunction(funcDecl)) {
            return entryName
        }
        var mangled = ""
        if (funcDecl.TestAttr(Attribute.HAS_INITIAL)) {
            CJC_NULLPTR_CHECK(funcDecl.ownerFunc)
            let owner = funcDecl.ownerFunc.getOrThrow()
            let newPrefix = ArrayList<Node>()
            newPrefix.add(owner)
            var outerDecl = owner.outerDecl
            while (let Some(outer) <- outerDecl) {
                newPrefix.add(outer)
                outerDecl = outer.outerDecl
            }
            reverseDecls(newPrefix)
            let mangledPrefix = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
            let ownerMangled = DeclName(funcDecl, newPrefix, genericsTypeStack, true, withSuffix: true)
            mangled += MANGLE_CANGJIE_PREFIX + MANGLE_FUNC_PARA_INIT_PREFIX +
                ownerMangled[mangledPrefix.size..ownerMangled.size - 1]
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
        } else {
            mangled = DeclName(funcDecl, prefix, genericsTypeStack, true, withSuffix: false)
            mangled += MANGLE_FUNC_PARAM_TYPE_PREFIX
        }
        mangled += MangleFuncParams(funcDecl, genericsTypeStack, false)
        return mangled
    }

    public func DeclName(decl: Decl, prefix: ArrayList<Node>, genericsTypeStack: ArrayList<String>,
        declare: Bool, withSuffix!: Bool = true): String {
        if (!decl.mangledName.isEmpty() && isMangledToExportForTestBefore(decl, prefix)) {
            return decl.mangledName
        }
        var newMangled = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            newMangled += ManglePackage(decl)
            newMangled += MangleVarWithPatternDecl((decl as VarWithPatternDecl).getOrThrow(), prefix)
        } else if (decl.astKind == ASTKind.EXTEND_DECL) {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            newMangled += MangleExtendEntity((decl as ExtendDecl).getOrThrow(), genericsTypeStack, declare)
            newMangled += MangleGenericArguments(decl, genericsTypeStack, declare)
        } else {
            newMangled += ManglePrefix(decl, prefix, genericsTypeStack, declare)
            let useInternalIdent = decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY) &&
                decl.astKind != ASTKind.PRIMARY_CTOR_DECL
            if (useInternalIdent) {
                let staticPrefix = if (decl.TestAttr(Attribute.STATIC) && decl.identifier.Val() != STATIC_INIT_FUNC) {
                    "static."
                } else {
                    ""
                }
                newMangled += MangleName(MANGLE_LT_PREFIX + staticPrefix + decl.identifier.Val() + MANGLE_GT_PREFIX)
            } else if (decl.TestAttr(Attribute.OPERATOR) && OperatorTypeMangle(decl.identifier.Val()).isSome()) {
                newMangled += OperatorTypeMangle(decl.identifier.Val()).getOrThrow()
            } else if (decl.identifier.Val().startsWith(MANGLE_DOLLAR_PREFIX) &&
                (EndsWith(decl.identifier.Val(), SPECIAL_NAME_FOR_SET) || EndsWith(decl.identifier.Val(), SPECIAL_NAME_FOR_GET))) {
                newMangled += MangleName(decl.identifier.Val()[MANGLE_CHAR_LEN..decl.identifier.Val().size - MANGLE_PROP_LEN])
                newMangled += if (EndsWith(decl.identifier.Val(), SPECIAL_NAME_FOR_SET)) { "ps" } else { "pg" }
            } else {
                var name = decl.identifier.Val()
                if (decl.astKind == ASTKind.GENERIC_PARAM_DECL) {
                    if (let Some(outer) <- decl.outerDecl) {
                        if (outer.TestAnyAttr(Attribute.COMMON, Attribute.SPECIFIC) &&
                            outer.TestAttr(Attribute.GENERIC)) {
                            if (let Some(genericsTy) <- decl.GetTy()) {
                                var found = false
                                var reverseIndex: Int64 = genericsTypeStack.size - 1
                                while (reverseIndex >= 0) {
                                    if (genericsTypeStack[reverseIndex] == genericsTy.name) {
                                        name = MANGLE_GENERIC_TYPE_PREFIX + DecimalToManglingNumber("${reverseIndex}")
                                        found = true
                                        break
                                    }
                                    reverseIndex--
                                }
                                if (!found) {
                                    throw IllegalArgumentException("Using undeclared generic type: " + genericsTy.name)
                                }
                            }
                        }
                    }
                } else if (decl.TestAttr(Attribute.HAS_INITIAL)) {
                    if (let Some(pos) <- decl.identifier.Val().indexOf(MANGLE_DOT_PREFIX)) {
                        name = decl.identifier.Val()[0..pos]
                    }
                }
                newMangled += MangleName(name)
                if (decl.IsFunc() && IsLocalFunc((decl as FuncDecl).getOrThrow())) {
                    newMangled += GetMangledLocalFuncIndex((decl as FuncDecl).getOrThrow())
                }
            }
            newMangled += MangleGenericArguments(decl, genericsTypeStack, declare)
        }
        if (withSuffix) {
            newMangled += MANGLE_SUFFIX
        }
        return newMangled
    }

    public func ManglePrefix(node: Node, prefix: ArrayList<Node>, genericsTypeStack: ArrayList<String>,
        declare: Bool): String {
        var mangled = ""
        var outerMostNode: Option<Node> = None
        var prefixIndex: Int64 = 0
        for (curPrefix in prefix) {
            if (curPrefix.astKind == ASTKind.CLASS_DECL || curPrefix.astKind == ASTKind.INTERFACE_DECL ||
                curPrefix.astKind == ASTKind.ENUM_DECL || curPrefix.astKind == ASTKind.STRUCT_DECL ||
                curPrefix.astKind == ASTKind.BUILTIN_DECL) {
                mangled += MangleName((curPrefix as Decl).getOrThrow().identifier.Val())
                let genericArgs = MangleGenericArgumentsHelper((curPrefix as Decl).getOrThrow(), genericsTypeStack, true)
                if (!genericArgs.isEmpty()) {
                    mangled += genericArgs + MANGLE_SUFFIX
                }
            } else if (curPrefix.astKind == ASTKind.VAR_DECL) {
                if (curPrefix.TestAttr(Attribute.GLOBAL)) {
                    mangled += MangleName((curPrefix as Decl).getOrThrow().identifier.Val())
                }
            } else if (curPrefix.astKind == ASTKind.FUNC_DECL) {
                mangled += MangleName((curPrefix as Decl).getOrThrow().identifier.Val())
                if (IsLocalFunc((curPrefix as FuncDecl).getOrThrow())) {
                    mangled += GetMangledLocalFuncIndex((curPrefix as FuncDecl).getOrThrow())
                }
                mangled += MangleGenericArgumentsHelper((curPrefix as Decl).getOrThrow(), genericsTypeStack, true) +
                    MANGLE_FUNC_PARAM_TYPE_PREFIX + MangleFuncParams((curPrefix as FuncDecl).getOrThrow(), genericsTypeStack, false) +
                    MANGLE_SUFFIX
            } else if (curPrefix.astKind == ASTKind.EXTEND_DECL) {
                let isInitFunc = node.astKind == ASTKind.FUNC_DECL && node.TestAttr(Attribute.HAS_INITIAL)
                let useExtendEntity = node.astKind == ASTKind.GENERIC_PARAM_DECL ||
                    (node.TestAttr(Attribute.PRIVATE) && !isInitFunc) ||
                    (isInitFunc && (node as FuncDecl).getOrThrow().ownerFunc.getOrThrow().TestAttr(Attribute.PRIVATE))
                if (useExtendEntity) {
                    mangled += MangleExtendEntity((curPrefix as ExtendDecl).getOrThrow(), genericsTypeStack, declare)
                } else if (let Some(extendedType) <- (curPrefix as ExtendDecl).getOrThrow().extendedType) {
                    if (let Some(ty) <- extendedType.GetTy()) {
                        mangled += MANGLE_EXTEND_PREFIX + MangleSemaType(ty, genericsTypeStack, declare: true)
                    }
                }
            } else if (curPrefix.astKind == ASTKind.LAMBDA_EXPR) {
                let outerNode = if (let Some(value) <- FindOuterNodeOfLambda(prefix, prefixIndex)) {
                    value
                } else {
                    throw IllegalArgumentException("Outer container of lambda is not found.")
                }
                var pkgName = ""
                if (ASTKindIndex(outerNode.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                    ASTKindIndex(outerNode.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                    pkgName = (outerNode as Decl).getOrThrow().fullPackageName
                } else {
                    for (lambdaPrefixDecl in prefix) {
                        if (ASTKindIndex(lambdaPrefixDecl.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                            ASTKindIndex(lambdaPrefixDecl.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                            pkgName = (lambdaPrefixDecl as Decl).getOrThrow().fullPackageName
                            break
                        }
                    }
                }
                pkgName = ManglerContext.ReduceUnitTestPackageName(pkgName)
                if (pkgName.isEmpty()) {
                    throw IllegalArgumentException("Package name of lambda is empty.")
                }
                let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
                    value
                } else {
                    throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
                }
                let lambdaIndex = if (let Some(value) <- ctx.GetIndexOfLambda(outerNode, (curPrefix as LambdaExpr).getOrThrow())) {
                    value
                } else {
                    throw IllegalArgumentException("Index of lambda is not found.")
                }
                mangled += MANGLE_LAMBDA_PREFIX + DecimalToManglingNumber("${lambdaIndex}")
            } else if (curPrefix.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                if (curPrefix.TestAttr(Attribute.GLOBAL)) {
                    var mangleStr = ""
                    var patternContainsVar = false
                    let varDeclCollection = HashSet<Decl>()
                    let vwpDecl = (curPrefix as VarWithPatternDecl).getOrThrow()

                    func patternWalkThrough(pattern: Pattern): Unit {
                        if (!mangleStr.isEmpty()) {
                            return
                        }
                        if (pattern.astKind == ASTKind.VAR_PATTERN) {
                            let varDecl = (pattern as VarPattern).getOrThrow().varDecl.getOrThrow()
                            mangleStr = MangleName(varDecl.identifier.Val())
                            if (varDeclCollection.contains(varDecl)) {
                                patternContainsVar = true
                            }
                        }

                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in (pattern as TuplePattern).getOrThrow().patterns) {
                                patternWalkThrough(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in (pattern as EnumPattern).getOrThrow().patterns) {
                                patternWalkThrough(item)
                            }
                        }
                    }

                    func collectAllVarPattern(pattern: Pattern): Unit {
                        if (pattern.astKind == ASTKind.VAR_PATTERN) {
                            let varDecl = (pattern as VarPattern).getOrThrow().varDecl.getOrThrow()
                            varDeclCollection.add(varDecl)
                            return
                        }
                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in (pattern as TuplePattern).getOrThrow().patterns) {
                                collectAllVarPattern(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in (pattern as EnumPattern).getOrThrow().patterns) {
                                collectAllVarPattern(item)
                            }
                        }
                    }

                    if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in (pattern as TuplePattern).getOrThrow().patterns) {
                                collectAllVarPattern(item)
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in (pattern as EnumPattern).getOrThrow().patterns) {
                                collectAllVarPattern(item)
                            }
                        }

                        if (pattern.astKind == ASTKind.TUPLE_PATTERN) {
                            for (item in (pattern as TuplePattern).getOrThrow().patterns) {
                                patternWalkThrough(item)
                                if (!mangleStr.isEmpty()) {
                                    break
                                }
                            }
                        } else if (pattern.astKind == ASTKind.ENUM_PATTERN) {
                            for (item in (pattern as EnumPattern).getOrThrow().patterns) {
                                patternWalkThrough(item)
                                if (!mangleStr.isEmpty()) {
                                    break
                                }
                            }
                        }
                    }

                    if (patternContainsVar) {
                    } else if (!mangleStr.isEmpty()) {
                        mangled += mangleStr
                    } else {
                        let index = GetIndexOfWildcard(vwpDecl, prefix)
                        mangleStr += MANGLE_ANONYMOUS_VARIABLE_PREFIX
                        mangleStr += DecimalToManglingNumber("${index}")
                        mangled += mangleStr
                    }
                }
            }
            if (let None <- outerMostNode) {
                outerMostNode = curPrefix
            }
            prefixIndex++
        }
        let outer = outerMostNode ?? node
        if (outer.TestAttr(Attribute.PRIVATE)) {
            let file = if (let Some(value) <- outer.curFile) {
                value
            } else {
                throw IllegalArgumentException("Private prefix node has no current file.")
            }
            let fileName = file.fileName
            mangled = MANGLE_FILE_ID_PREFIX + if (BaseMangler.IsHashable(fileName)) {
                BaseMangler.HashToBase62(fileName)
            } else {
                BaseMangler.FileNameWithoutExtension(fileName) + MANGLE_DOLLAR_PREFIX
            } + mangled
        }
        if (node.astKind == ASTKind.LAMBDA_EXPR) {
            var reverseIndex = prefix.size - 1
            while (reverseIndex >= 0) {
                let packagePrefixDecl = prefix[reverseIndex]
                if (ASTKindIndex(packagePrefixDecl.astKind) >= ASTKindIndex(ASTKind.DECL) &&
                    ASTKindIndex(packagePrefixDecl.astKind) <= ASTKindIndex(ASTKind.INVALID_DECL)) {
                    mangled = ManglePackage((packagePrefixDecl as Decl).getOrThrow()) + mangled
                    break
                }
                reverseIndex--
            }
        } else {
            mangled = ManglePackage((node as Decl).getOrThrow()) + mangled
        }
        return mangled
    }

    public func ManglePackage(decl: Decl): String {
        let genericPackageName = ManglePackageNameForGeneric(decl)
        return if (genericPackageName.isEmpty()) { MangleFullPackageName(decl) } else { genericPackageName }
    }

    public func MangleFullPackageName(packageName: String): String {
        var orgName = ""
        var newPkgName = packageName
        if (let Some(pos) <- packageName.indexOf("::")) {
            orgName = packageName[0..pos + 1]
            if (packageName.size > pos + 2) {
                newPkgName = packageName[pos + 2..]
            } else {
                newPkgName = ""
            }
        }
        if (let Some(shortName) <- StdPackageMangle(newPkgName)) {
            return shortName
        }
        return MangleName(orgName + newPkgName)
    }

    public func MangleFullPackageName(decl: Decl): String {
        return MangleFullPackageName(decl.fullPackageName)
    }

    public func GetPrefixOfType(ty: Ty): String {
        return match (ty.kind) {
            case TypeKind.TYPE_ENUM => MANGLE_TYPE_ENUM_PREFIX
            case TypeKind.TYPE_INTERFACE => MANGLE_TYPE_CLASS_PREFIX
            case TypeKind.TYPE_CLASS => MANGLE_TYPE_CLASS_PREFIX
            case TypeKind.TYPE_STRUCT => MANGLE_TYPE_STRUCT_PREFIX
            case _ => unsupportedTy(ty.kind, "Unexpected user-defined type")
        }
    }

    public func MangleSemaType(ty: Ty): String {
        let genericsTypeStack = ArrayList<String>()
        return MangleSemaType(ty, genericsTypeStack, declare: true)
    }

    public func MangleSemaType(ty: Ty, genericsTypeStack: ArrayList<String>, declare!: Bool = false,
        isCollectGTy!: Bool = true): String {
        if (let Some(primitive) <- PrimitiveTypeMangle(ty.kind)) {
            return primitive
        }
        if (ty.kind == TypeKind.TYPE_GENERICS) {
            if (declare || isCollectGTy) {
                return MangleGenericType(ty, genericsTypeStack, declare: declare)
            }
            return MangleGenericType(ty)
        }
        if (ty.kind == TypeKind.TYPE_POINTER) {
            return MangleCPointerType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_ENUM) {
            return MangleEnumType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_ARRAY) {
            return MangleRawArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_VARRAY) {
            return MangleVArrayType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_TUPLE) {
            return MangleTupleType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_FUNC) {
            return MangleFuncType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_STRUCT || ty.kind == TypeKind.TYPE_INTERFACE ||
            ty.kind == TypeKind.TYPE_CLASS) {
            return MangleUserDefinedType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
        }
        if (ty.kind == TypeKind.TYPE_CSTRING) {
            return MangleCStringType()
        }
        return ""
    }

    public func MangleUserDefinedType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.kind != TypeKind.TYPE_ENUM && ty.kind != TypeKind.TYPE_STRUCT &&
            ty.kind != TypeKind.TYPE_CLASS && ty.kind != TypeKind.TYPE_INTERFACE) {
            return unsupportedTy(ty.kind, "Unexpected user-defined type")
        }
        let decl = if (let Some(value) <- Ty.GetDeclOfTy(ty)) {
            value
        } else {
            return unsupportedTy(ty.kind, "User-defined type has no declaration")
        }
        if (IsAutoBoxedBaseDecl(decl)) {
            return decl.mangledName
        }
        var mangledName = GetPrefixOfType(ty) + MANGLE_NESTED_PREFIX
        let genericPkgName = ManglePackageNameForGeneric(decl)
        if (!genericPkgName.isEmpty()) {
            mangledName += genericPkgName
        } else {
            mangledName += MangleFullPackageName(decl)
        }
        if (decl.TestAttr(Attribute.PRIVATE) && decl.linkage == Linkage.INTERNAL) {
            if (let Some(file) <- decl.curFile) {
                mangledName += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
            } else {
                throw IllegalArgumentException("Private internal type declaration has no current file.")
            }
        }
        mangledName += MangleName(decl.identifier.Val())
        if (let Some(_) <- decl.GetGeneric()) {
            mangledName += MANGLE_GENERIC_PREFIX
        }
        for (arg in ty.typeArgs) {
            mangledName += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangledName += MANGLE_SUFFIX
        return mangledName
    }

    public func MangleGenericArguments(decl: Decl, genericsTypeStack: ArrayList<String>, declare: Bool): String {
        return MangleGenericArgumentsHelper(decl, genericsTypeStack, declare, isCollectGTy: false)
    }

    public func MangleGenericArgumentsHelper(decl: Decl, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        let args = ArrayList<Ty>()
        if (decl.GetTy().isSome() && !decl.GetTy().getOrThrow().IsFunc()) {
            for (arg in decl.GetTy().getOrThrow().typeArgs) { args.add(arg) }
        } else if (decl.astKind == ASTKind.FUNC_DECL) {
            let body = (decl as FuncDecl).getOrThrow().funcBody.getOrThrow()
            if (let Some(generic) <- body.generic) {
                for (arg in generic.typeParameters) { args.add(arg.GetTy().getOrThrow()) }
            }
        }
        if (args.isEmpty()) {
            return ""
        }
        var mangled = MANGLE_GENERIC_PREFIX
        for (arg in args) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        return mangled
    }

    public open func MangleEntryFunction(funcDecl: FuncDecl): Option<String> {
        if (funcDecl.identifier.Val() == MAIN_INVOKE && funcDecl.TestAttr(Attribute.GLOBAL)) {
            return USER_MAIN_MANGLED_NAME
        }
        if (funcDecl.identifier.Val() == TEST_ENTRY_NAME) {
            return TEST_ENTRY_NAME
        }
        return None
    }

    public func MangleEnumType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        return MangleUserDefinedType(ty, genericsTypeStack, declare, isCollectGTy: isCollectGTy)
    }

    public func MangleRawArrayType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.typeArgs.isEmpty()) {
            return unsupportedTy(ty.kind, "RawArray type has no element type")
        }
        return MANGLE_TYPE_ARRAY_PREFIX + DecimalToManglingNumber("${(ty as ArrayTy).getOrThrow().dims}") +
            MangleSemaType(ty.typeArgs[0], genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
    }

    public func MangleVArrayType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        var mangled = MANGLE_VARRAY_PREFIX + DecimalToManglingNumber("${(ty as VArrayTy).getOrThrow().size}")
        for (arg in ty.typeArgs) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        return mangled
    }

    public func MangleTupleType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        var mangled = MANGLE_TUPLE_PREFIX + DecimalToManglingNumber("${ty.typeArgs.size}")
        for (arg in ty.typeArgs) {
            mangled += MangleSemaType(arg, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangled += MANGLE_SUFFIX
        return mangled
    }

    public func MangleFuncType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        let funcTy = (ty as FuncTy).getOrThrow()
        var mangled = if (funcTy.IsCFunc()) { MANGLE_CFUNC_PREFIX } else { MANGLE_GENERAL_FUNC_PREFIX }
        var retTy = MangleSemaType(funcTy.retTy, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        if (retTy.isEmpty()) { retTy = MANGLE_VOID_TY_SUFFIX }
        var params = ""
        for (param in funcTy.paramTys) {
            params += MangleSemaType(param, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
        }
        mangled += retTy + params + MANGLE_SUFFIX
        return mangled
    }

    public func MangleFuncParams(funcDecl: FuncDecl, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (let Some(body) <- funcDecl.funcBody) {
            if (body.paramLists.isEmpty() || body.paramLists[0].params.isEmpty()) {
                return MANGLE_VOID_TY_SUFFIX
            }
            var mangled = ""
            for (param in body.paramLists[0].params) {
                if (let Some(ty) <- param.GetTy()) {
                    if (ty.kind != TypeKind.TYPE_INITIAL) {
                        mangled += MangleSemaType(ty, genericsTypeStack, declare: declare, isCollectGTy: isCollectGTy)
                    }
                } else {
                    throw IllegalArgumentException("Function parameter has no semantic type: " + param.identifier.Val())
                }
            }
            return mangled
        }
        return MANGLE_VOID_TY_SUFFIX
    }

    public func MangleCPointerType(ty: Ty, genericsTypeStack: ArrayList<String>, declare: Bool,
        isCollectGTy!: Bool = true): String {
        if (ty.typeArgs.isEmpty()) {
            return unsupportedTy(ty.kind, "CPointer type has no element type")
        }
        return MANGLE_POINTER_PREFIX + MangleSemaType(ty.typeArgs[0], genericsTypeStack, declare: declare,
            isCollectGTy: isCollectGTy)
    }

    public func MangleGenericType(ty: Ty): String {
        return MANGLE_GENERIC_TYPE_PREFIX + MangleName(ty.name)
    }

    public func MangleGenericType(ty: Ty, genericsTypeStack: ArrayList<String>, declare!: Bool = false): String {
        var index: Int64 = 0
        if (declare) {
            index = genericsTypeStack.size
            genericsTypeStack.add(ty.name)
        } else {
            var found = false
            var reverseIndex: Int64 = genericsTypeStack.size - 1
            while (reverseIndex >= 0) {
                if (genericsTypeStack[reverseIndex] == ty.name) {
                    index = reverseIndex
                    found = true
                    break
                }
                reverseIndex--
            }
            if (!found) {
                throw IllegalArgumentException("Using undeclared generic type: " + ty.name)
            }
        }
        return MANGLE_GENERIC_TYPE_PREFIX + DecimalToManglingNumber("${index}")
    }

    public func MangleCStringType(): String {
        return "k"
    }

    public func MangleVarDecl(decl: VarDecl, prefix: ArrayList<Node>): String {
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(decl, prefix, genericsTypeStack, false)
        mangleStr += MangleName(decl.identifier.Val())
        if (IsLocalVariable(decl)) {
            if (let Some(ctx) <- manglerCtxTable.get(decl.fullPackageName)) {
                mangleStr += MANGLE_COUNT_PREFIX
                if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
                    if (outerNode.astKind == ASTKind.CLASS_DECL || outerNode.astKind == ASTKind.INTERFACE_DECL ||
                        outerNode.astKind == ASTKind.STRUCT_DECL) {
                        mangleStr += DecimalToManglingNumber("0")
                    } else {
                        let indexOption = ctx.GetIndexOfVar(outerNode, decl)
                        CJC_ASSERT(indexOption.isSome())
                        let index = indexOption.getOrThrow()
                        mangleStr += DecimalToManglingNumber("${index}")
                    }
                }
            }
        }
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func GetIndexOfWildcard(vwpDecl: VarWithPatternDecl, prefix: ArrayList<Node>): Int64 {
        let pattern = if (let Some(value) <- vwpDecl.irrefutablePattern) {
            value
        } else {
            throw IllegalArgumentException("VarWithPattern declaration has no irrefutable pattern.")
        }
        if (!ManglerContext.CheckAllElementsWildcard(pattern)) {
            throw IllegalArgumentException("VarWithPattern declaration is not an all-wildcard pattern.")
        }
        let pkgName = ManglerContext.ReduceUnitTestPackageName(vwpDecl.fullPackageName)
        if (pkgName.isEmpty()) {
            throw IllegalArgumentException("Package name of VarWithPattern declaration is empty.")
        }
        let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
        }
        if (vwpDecl.TestAttr(Attribute.GLOBAL)) {
            let file = if (let Some(value) <- vwpDecl.curFile) {
                value
            } else {
                throw IllegalArgumentException("Global VarWithPattern declaration has no current file.")
            }
            if (let Some(index) <- ctx.GetIndexOfGlobalWildcardVar(file, vwpDecl)) {
                return index
            }
        } else if (let Some(outerNode) <- findOuterNodeOfLocal(prefix)) {
            if (let Some(index) <- ctx.GetIndexOfLocalWildcardVar(outerNode, vwpDecl)) {
                return index
            }
        } else {
            throw IllegalArgumentException("Outer scope of local VarWithPattern declaration is not found.")
        }
        throw IllegalArgumentException("Index of VarWithPattern declaration is not found.")
    }

    public func MangleVarWithPatternDecl(vwpDecl: VarWithPatternDecl, prefix: ArrayList<Node>): String {
        if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
            if (let Some(varDecl) <- firstVarPatternDecl(pattern)) {
                return MangleVarDecl(varDecl, prefix)
            }
        }
        let index = GetIndexOfWildcard(vwpDecl, prefix)
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(vwpDecl, prefix, genericsTypeStack, true)
        if (vwpDecl.TestAttr(Attribute.GLOBAL)) {
            let file = if (let Some(value) <- vwpDecl.curFile) {
                value
            } else {
                throw IllegalArgumentException("Global VarWithPattern declaration has no current file.")
            }
            mangleStr += MANGLE_FILE_ID_PREFIX + fileIdFor(file)
        }
        mangleStr += MANGLE_ANONYMOUS_VARIABLE_PREFIX
        mangleStr += DecimalToManglingNumber("${index}")
        mangleStr += MANGLE_SUFFIX
        return mangleStr
    }

    public func MangleExtendEntity(extendDecl: ExtendDecl, genericsTypeStack: ArrayList<String>, declare: Bool): String {
        let extNode = if (let Some(value) <- extendDecl.extendedType) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration has no extended type.")
        }
        let extTy = if (let Some(value) <- extNode.GetTy()) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration extended type has no semantic type.")
        }
        let targetFile = if (let Some(value) <- extendDecl.curFile) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration has no current file.")
        }
        let ctxValue = if (let Some(value) <- manglerCtxTable.get(
            ManglerContext.ReduceUnitTestPackageName(extendDecl.fullPackageName))) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + extendDecl.fullPackageName)
        }
        let extendIndex = if (let Some(value) <- ctxValue.GetIndexOfExtend(targetFile, extendDecl)) {
            value
        } else {
            throw IllegalArgumentException("Extend declaration not registered in mangler context.")
        }
        var mangled = MANGLE_EXTEND_PREFIX + MangleSemaType(extTy, genericsTypeStack, declare: declare)
        mangled += MANGLE_FILE_ID_PREFIX + fileIdFor(targetFile)
        mangled += MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${extendIndex}")
        return mangled
    }

    public func MangleLambda(lambda: LambdaExpr, prefix: ArrayList<Node>): String {
        let index = GetLambdaIndex(lambda, prefix, prefix.size)
        var mangleStr = MANGLE_CANGJIE_PREFIX + MANGLE_NESTED_PREFIX
        let genericsTypeStack = ArrayList<String>()
        mangleStr += ManglePrefix(lambda, prefix, genericsTypeStack, true)
        mangleStr += MANGLE_LAMBDA_PREFIX + DecimalToManglingNumber("${index}") + MANGLE_SUFFIX
        return CJMangledCompression(mangleStr)
    }

    public func GetMangledLocalFuncIndex(decl: FuncDecl): String {
        if (let Some(outerNode) <- GetOuterDecl(decl)) {
            let pkgName = ManglerContext.ReduceUnitTestPackageName(decl.fullPackageName)
            let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
                value
            } else {
                throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
            }
            let index = if (let Some(value) <- ctx.GetIndexOfFunc(outerNode, decl)) {
                value
            } else {
                throw IllegalArgumentException("Index of local function is not found: " + decl.identifier.Val())
            }
            if (index > 0) {
                return MANGLE_COUNT_PREFIX + DecimalToManglingNumber("${index - 1}")
            }
        } else {
            if (IsLocalFunc((decl as FuncDecl).getOrThrow())) {
                throw IllegalArgumentException("Outer declaration of local function is not found: " + decl.identifier.Val())
            }
        }
        return ""
    }

    public func IsLocalVariable(decl: Decl): Bool {
        if (decl.astKind != ASTKind.VAR_DECL) {
            return false
        }
        let isStaticMemberVar = if (let Some(outer) <- decl.outerDecl) {
            (outer.IsClassLikeDecl() || outer.IsStructOrClassDecl()) && decl.TestAttr(Attribute.STATIC)
        } else {
            false
        }
        return !decl.TestAttr(Attribute.GLOBAL) && !isStaticMemberVar
    }

    public func IsLocalFunc(funcDecl: FuncDecl): Bool {
        if (let Some(outer) <- funcDecl.outerDecl) {
            return !funcDecl.TestAttr(Attribute.GLOBAL) && !outer.IsNominalDecl()
        }
        return false
    }

    public func GetAnyMangledTypeName(): String {
        return "CNat3AnyE"
    }

    public func PrepareContextForPackage(pkg: Package): ManglerContext {
        let pkgName = ManglerContext.ReduceUnitTestPackageName(pkg.fullPackageName)
        let ctx = ManglerContext()
        manglerCtxTable[pkgName] = ctx
        return ctx
    }

    public func CollectLocalDecls(ctx: ManglerContext, pkg: Package): Unit {
        Walker(pkg, visitPre: { node: Node =>
            if (let Some(ed) <- (node as ExtendDecl)) { ctx.SaveExtend2CurFile(ed.curFile.getOrThrow(), ed) }
            if (let Some(vpd) <- (node as VarWithPatternDecl)) {
                if (vpd.TestAttr(Attribute.GLOBAL)) { ctx.SaveGlobalWildcardVar(vpd.curFile.getOrThrow(), vpd) }
            }
            let isGlobal = node is VarDeclAbstract && node.TestAttr(Attribute.GLOBAL)
            var isCompositeType = false
            if (let Some(vda) <- (node as VarDeclAbstract)) {
                if (let Some(outer) <- vda.outerDecl) {
                    isCompositeType = outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                        outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
                }
            }
            if (node is FuncDecl || node is LambdaExpr || isGlobal || isCompositeType) {
                ctx.SaveVar2CurDecl(node)
                ctx.SaveLambda2CurDecl(node)
                ctx.SaveLocalWildcardVar2Decl(node)
                ctx.SaveFunc2CurDecl(node)
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    public func MangleExportIds(pkg: Package): Unit {
        let ctx = PrepareContextForPackage(pkg)
        CollectLocalDecls(ctx, pkg)
        exportIdMode = true
        Walker(pkg, visitPre: { node: Node =>
            if (let Some(decl) <- (node as Decl)) {
                if (Ty.IsTyCorrect(decl.GetTy()) && decl.TestAttr(Attribute.GLOBAL)) {
                    decl.exportId = MangleExportId(decl)
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    public func MangleExportId(decl: Decl): String {
        if (decl.TestAttr(Attribute.NO_MANGLE)) {
            return decl.identifier.Val()
        }
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            return ""
        }
        if (decl.astKind == ASTKind.FUNC_DECL) {
            decl.exportId = Mangle(decl)
            if (decl.TestAttr(Attribute.DEFAULT)) {
                if (let Some(outer) <- decl.outerDecl) {
                    if (outer.astKind == ASTKind.INTERFACE_DECL) {
                        MangleExportIdForGenericParamDecl(decl)
                    }
                }
            }
            return decl.exportId
        }
        if (decl.astKind == ASTKind.PROP_DECL) {
            for (getter in (decl as PropDecl).getOrThrow().getters) {
                getter.exportId = Mangle(getter)
            }
            for (setter in (decl as PropDecl).getOrThrow().setters) {
                setter.exportId = Mangle(setter)
            }
            return Mangle(decl)
        }
        decl.exportId = Mangle(decl)
        for (member in decl.GetMemberDeclPtrs()) {
            member.exportId = MangleExportId(member)
        }
        if (decl.astKind == ASTKind.INTERFACE_DECL && decl.TestAttr(Attribute.GENERIC)) {
            MangleExportIdForGenericParamDecl(decl)
        }
        return decl.exportId
    }

    public static func HashToBase62(input: String): String {
        return toBase62(fnv1aHash(input))
    }

    public static func IsHashable(str: String): Bool {
        let fileName = BaseMangler.FileNameWithoutExtension(str)
        if (fileName.size > 12) {
            return true
        }
        for (ch in fileName.toArray()) {
            if (!(IsAlpha(ch) || IsDigit(ch) || ch == b'.' || ch == b'_' || ch == b'-')) {
                return true
            }
        }
        return false
    }

    public static func FileNameWithoutExtension(fileName: String): String {
        if (fileName.size > 3 && EndsWith(fileName, ".cj")) {
            return fileName[0..fileName.size - 3]
        }
        return fileName
    }

    private func ManglePackageNameForGeneric(decl: Decl): String {
        var genericPkg = ""
        var genericDecl = decl.genericDecl
        while (let Some(value) <- genericDecl) {
            genericPkg = MangleFullPackageName(value)
            genericDecl = value.genericDecl
        }
        if (!genericPkg.isEmpty()) {
            return genericPkg
        }
        var outer: Option<Decl> = decl
        while (let Some(current) <- outer) {
            if (let Some(generic) <- current.genericDecl) {
                return MangleFullPackageName(generic)
            }
            outer = GetOuterDecl(current)
        }
        return genericPkg
    }

    private func GetOuterDecl(decl: Decl): Option<Decl> {
        if (decl.astKind != ASTKind.FUNC_DECL) {
            return decl.outerDecl
        }
        if (let Some(body) <- (decl as FuncDecl).getOrThrow().funcBody) {
            if (let Some(parent) <- body.parentClassLike) {
                return parent
            }
            if (let Some(parent) <- body.parentStruct) {
                return parent
            }
            if (let Some(parent) <- body.parentEnum) {
                return parent
            }
        }
        return decl.outerDecl
    }

    private func IsLambdaOuterCandidate(node: Node): Bool {
        if (node.astKind == ASTKind.FUNC_DECL || node.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            node.astKind == ASTKind.LAMBDA_EXPR) {
            return true
        }
        if ((node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
            node.TestAttr(Attribute.GLOBAL)) {
            return true
        }
        if (node.astKind == ASTKind.VAR_DECL || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            if (let Some(outer) <- (node as VarDeclAbstract).getOrThrow().outerDecl) {
                return outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                    outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
            }
        }
        return false
    }

    private func FindOuterNodeOfLambda(prefix: ArrayList<Node>, stopExclusive: Int64): Option<Node> {
        var idx = stopExclusive - 1
        while (idx >= 0) {
            let prevPrefix = prefix[idx]
            if (IsLambdaOuterCandidate(prevPrefix)) {
                return prevPrefix
            }
            idx--
        }
        return None
    }

    private func GetLambdaIndex(lambda: LambdaExpr, prefix: ArrayList<Node>, stopExclusive: Int64): Int64 {
        let outerNode = if (let Some(value) <- FindOuterNodeOfLambda(prefix, stopExclusive)) {
            value
        } else {
            throw IllegalArgumentException("Outer container of lambda is not found.")
        }
        var pkgName = ""
        if (let Some(decl) <- (outerNode as Decl)) {
            pkgName = decl.fullPackageName
        } else {
            for (node in prefix) {
                if (let Some(decl) <- (node as Decl)) {
                    pkgName = decl.fullPackageName
                    break
                }
            }
        }
        pkgName = ManglerContext.ReduceUnitTestPackageName(pkgName)
        if (pkgName.isEmpty()) {
            throw IllegalArgumentException("Package name of lambda is empty.")
        }
        let ctx = if (let Some(value) <- manglerCtxTable.get(pkgName)) {
            value
        } else {
            throw IllegalArgumentException("Mangler context not prepared for package: " + pkgName)
        }
        if (let Some(index) <- ctx.GetIndexOfLambda(outerNode, lambda)) {
            return index
        }
        throw IllegalArgumentException("Index of lambda is not found.")
    }

    @When[backend == "cjnative"]
    private func GetSpecialFuncName(fd: FuncDecl): Option<String> {
        if (fd.fullPackageName != CORE_PACKAGE_NAME) {
            return None
        }
        return match (fd.identifier.Val()) {
            case "throwGlobalOutOfMemoryError" => "rt$ThrowGlobalOutOfMemoryError"
            case "throwStackOverflowError" => "rt$ThrowStackOverflowError"
            case "throwOutOfMemoryError" => "rt$ThrowOutOfMemoryError"
            case "throwImplicitException" => "rt$ThrowImplicitException"
            case "throwArithmeticException" => "rt$ThrowArithmeticException"
            case "throwArithmeticExceptionMsg" => "rt$ThrowArithmeticException_msg"
            case "createArithmeticExceptionMsg" => "rt$CreateArithmeticException_msg"
            case "createOverflowExceptionMsg" => "rt$CreateOverflowException_msg"
            case "throwOverflowException" => "rt$ThrowOverflowException"
            case "throwIndexOutOfBoundsException" => "rt$ThrowIndexOutOfBoundsException"
            case "throwNegativeArraySizeException" => "rt$ThrowNegativeArraySizeException"
            case "callToString" => "rt$CallToString"
            case "checkIsError" => "rt$CheckIsError"
            case "throwError" => "rt$ThrowError"
            case "callPrintStackTrace" => "rt$CallPrintStackTrace"
            case "callPrintStackTraceError" => "rt$CallPrintStackTraceError"
            case _ => None
        }
    }

    @When[backend != "cjnative"]
    private func GetSpecialFuncName(fd: FuncDecl): Option<String> {
        if (fd.fullPackageName != CORE_PACKAGE_NAME) {
            return None
        }
        return match (fd.identifier.Val()) {
            case "throwOutOfMemoryError" => "rt$ThrowOutOfMemoryError"
            case "throwImplicitException" => "rt$ThrowImplicitException"
            case "throwArithmeticException" => "rt$ThrowArithmeticException"
            case "throwArithmeticExceptionMsg" => "rt$ThrowArithmeticException_msg"
            case "createArithmeticExceptionMsg" => "rt$CreateArithmeticException_msg"
            case "createOverflowExceptionMsg" => "rt$CreateOverflowException_msg"
            case "throwOverflowException" => "rt$ThrowOverflowException"
            case "throwIndexOutOfBoundsException" => "rt$ThrowIndexOutOfBoundsException"
            case "throwNegativeArraySizeException" => "rt$ThrowNegativeArraySizeException"
            case "callToString" => "rt$CallToString"
            case "checkIsError" => "rt$CheckIsError"
            case "throwError" => "rt$ThrowError"
            case "callPrintStackTrace" => "rt$CallPrintStackTrace"
            case "callPrintStackTraceError" => "rt$CallPrintStackTraceError"
            case _ => None
        }
    }

    private func MangleExportIdForGenericParamDecl(decl: Decl): Unit {
        if (let Some(generic) <- decl.GetGeneric()) {
            for (gpd in generic.typeParameters) {
                let outer = if (let Some(value) <- gpd.outerDecl) {
                    value
                } else {
                    throw IllegalArgumentException("Generic parameter has no outer declaration: " + gpd.identifier.Val())
                }
                let ty = if (let Some(value) <- gpd.GetTy()) {
                    value
                } else {
                    throw IllegalArgumentException("Generic parameter has no semantic type: " + gpd.identifier.Val())
                }
                let genericsTypeStack = ArrayList<String>()
                gpd.exportId = outer.exportId + MANGLE_WILDCARD_PREFIX + gpd.identifier.Val() +
                    MangleSemaType(ty, genericsTypeStack, declare: false, isCollectGTy: false)
            }
        }
    }

    private func findOuterNodeOfLocal(prefix: ArrayList<Node>): Option<Node> {
        var idx = prefix.size - 1
        while (idx >= 0) {
            let curPrefix = prefix[idx]
            if (curPrefix.astKind == ASTKind.FUNC_DECL ||
                curPrefix.astKind == ASTKind.PRIMARY_CTOR_DECL ||
                curPrefix.astKind == ASTKind.LAMBDA_EXPR ||
                curPrefix.astKind == ASTKind.CLASS_DECL ||
                curPrefix.astKind == ASTKind.INTERFACE_DECL ||
                curPrefix.astKind == ASTKind.STRUCT_DECL ||
                ((curPrefix.astKind == ASTKind.VAR_DECL ||
                    curPrefix.astKind == ASTKind.VAR_WITH_PATTERN_DECL) &&
                    curPrefix.TestAttr(Attribute.GLOBAL))) {
                return curPrefix
            }
            idx--
        }
        return None
    }

    private func firstVarPatternDecl(pattern: Pattern): Option<VarDecl> {
        if (let Some(vp) <- (pattern as VarPattern)) { return vp.varDecl }
        if (let Some(tp) <- (pattern as TuplePattern)) {
            for (child in tp.patterns) {
                if (let Some(found) <- firstVarPatternDecl(child)) { return found }
            }
        } else if (let Some(ep) <- (pattern as EnumPattern)) {
            for (child in ep.patterns) {
                if (let Some(found) <- firstVarPatternDecl(child)) { return found }
            }
        }
        return None
    }

    private func fileIdFor(file: File): String {
        return if (BaseMangler.IsHashable(file.fileName)) {
            BaseMangler.HashToBase62(file.fileName)
        } else {
            BaseMangler.FileNameWithoutExtension(file.fileName) + MANGLE_DOLLAR_PREFIX
        }
    }

    private func reverseDecls(values: ArrayList<Node>): Unit {
        var left: Int64 = 0
        var right = values.size - 1
        while (left < right) {
            let tmp = values[left]
            values[left] = values[right]
            values[right] = tmp
            left++
            right--
        }
    }
}
