package cjcj::ast

import cjcj::utils.{
    CJC_ASSERT, FloatFormat, GetRootPackageName, INTEROP_JAVA_LANG_PACKAGE, INTEROP_JOBJECT_NAME,
    INTEROPLIB_CFFI_JAVA_ENTITY, JAVA_REF_GETTER_FUNC_NAME, Stold, SYNTHETIC_CLASS_SUFFIX
}
import std.collection.*
import std.sort.*

public func AddMacroAttr(node: Node): Unit {
    if (let Some(macroCall) <- node.curMacroCall) {
        let invocation = macroCall.GetInvocation() ?? return
        let curFile = node.curFile
        if (IsPureAnnotation(invocation)) {
            let walker = Walker(node, visitPre: { curNode: Node =>
                curNode.curFile = curFile
                VisitAction.WALK_CHILDREN
            })
            walker.Walk()
            return
        }
        let walker = Walker(node, visitPre: { curNode: Node =>
            curNode.curMacroCall = macroCall
            curNode.curFile = curFile
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

public func AddCurFile(root: Node, file!: Option<File> = None): Unit {
    if (let Some(pkg) <- (root as Package)) {
        for (pkgFile in pkg.files) {
            pkgFile.curPackage = pkg
            assignCurFile(pkgFile, pkgFile)
        }
        return
    }
    if (let Some(fileNode) <- (root as File)) {
        assignCurFile(fileNode, fileNode)
        return
    }
    if (let Some(value) <- file) {
        assignCurFile(root, value)
    }
}

private func assignCurFile(root: Node, file: File): Unit {
    let walker = Walker(root, visitPre: { curNode: Node =>
        if (let Some(fileNode) <- (curNode as File)) {
            fileNode.curFile = Some(fileNode)
            for (importSpec in fileNode.imports) {
                importSpec.curFile = Some(fileNode)
            }
            return VisitAction.WALK_CHILDREN
        }
        if (let None <- curNode.curFile) {
            curNode.curFile = file
        }
        if (let Some(_) <- curNode.curMacroCall) {
            AddMacroAttr(curNode)
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    walker.Walk()
}

public func IsPureAnnotation(invocation: MacroInvocation): Bool {
    return invocation.macroCallDiagInfo.isCustom && invocation.macroCallDiagInfo.isCurFile
}

public func SortModifierByPos(modifiers: ArrayList<Modifier>): ArrayList<Modifier> {
    let out = ArrayList<Modifier>()
    for (modifier in modifiers) {
        var inserted = false
        var idx: Int64 = 0
        while (idx < out.size) {
            if (modifier.begin < out[idx].begin) {
                out.add(modifier, at: idx)
                inserted = true
                break
            }
            idx++
        }
        if (!inserted) {
            out.add(modifier)
        }
    }
    return out
}

public func IsInstanceConstructor(node: Node): Bool {
    return node.TestAttr(Attribute.CONSTRUCTOR) && !node.TestAttr(Attribute.STATIC)
}

public func IsStaticInitializer(decl: Decl): Bool {
    return decl.TestAttr(Attribute.STATIC) && decl.TestAttr(Attribute.CONSTRUCTOR)
}

public func IsClassOrEnumConstructor(decl: Decl): Bool {
    return IsInstanceConstructor(decl) || decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

public func IsGlobalOrMember(node: Node): Bool {
    return node.TestAnyAttr(Attribute.GLOBAL, Attribute.IN_CLASSLIKE, Attribute.IN_ENUM) ||
        node.TestAnyAttr(Attribute.IN_STRUCT, Attribute.IN_EXTEND)
}

public func IsInstanceMember(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        return outer.IsNominalDecl() && !decl.TestAttr(Attribute.STATIC)
    }
    return false
}

public func IsGlobalOrStaticVar(decl: Decl): Bool {
    return decl.astKind == ASTKind.VAR_DECL && decl.TestAnyAttr(Attribute.STATIC, Attribute.GLOBAL)
}

public func IsInheritableClass(decl: Decl): Bool {
    return decl.astKind == ASTKind.CLASS_DECL && decl.TestAnyAttr(Attribute.OPEN, Attribute.ABSTRACT)
}

public func IsMemberParam(decl: Decl): Bool {
    if (let Some(param) <- (decl as FuncParam)) {
        return param.isMemberParam
    }
    return false
}

public func IsSingleRuneStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return lit.kind == LitConstKind.STRING && lit.codepoint.size == 1
    }
    return false
}

public func IsSingleByteStringLiteral(expr: Expr): Bool {
    if (let Some(lit) <- (expr as LitConstExpr)) {
        return IsSingleRuneStringLiteral(expr) && lit.codepoint[0] <= 255u32
    }
    return false
}

public func GetSizeDecl(ty: Ty): Option<FuncDecl> {
    if (!ty.IsClassLike()) {
        return None
    }
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.decl) {
            return getSizeDeclFromMembers(decl.GetMemberDecls())
        }
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.decl) {
            return getSizeDeclFromMembers(decl.GetMemberDecls())
        }
    }
    if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
        if (let Some(decl) <- classLikeTy.commonDecl) {
            return getSizeDeclFromMembers(decl.GetMemberDecls())
        }
    }
    return None
}

private func getSizeDeclFromMembers(members: ArrayList<Decl>): Option<FuncDecl> {
    for (member in members) {
        if (let Some(propDecl) <- (member as PropDecl)) {
            if (propDecl.identifier == "size" && !propDecl.getters.isEmpty()) {
                return propDecl.getters[0]
            }
        }
    }
    return None
}

public func HasJavaAttr(node: Node): Option<Attribute> {
    if (node.TestAttr(Attribute.JAVA_APP)) {
        return Attribute.JAVA_APP
    }
    if (node.TestAttr(Attribute.JAVA_EXT)) {
        return Attribute.JAVA_EXT
    }
    return None
}

public class FloatTypeInfo {
    public var inf: UInt64 = 0
    public var min: String = ""
    public var max: String = ""

    public init() {}

    public init(inf: UInt64, min: String, max: String) {
        this.inf = inf
        this.min = min
        this.max = max
    }
}

public func GetFloatTypeInfoByKind(kind: TypeKind): FloatTypeInfo {
    if (kind == TypeKind.TYPE_FLOAT16) {
        return FloatTypeInfo(0xF800, "5.960464477539063E-8", "6.5504E4")
    }
    if (kind == TypeKind.TYPE_FLOAT32) {
        return FloatTypeInfo(0xFF000000, "1.40129846E-45", "3.40282347E38")
    }
    return FloatTypeInfo(0xFFE0000000000000, "4.9406564584124654E-324", "1.7976931348623157E308")
}

public func SetOuterFunctionDecl(decl: Decl): Unit {
    var root: Option<Node> = None
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            root = body
        }
    } else if (let Some(varDecl) <- (decl as VarDecl)) {
        let isGlobalOrMember = varDecl.TestAttr(Attribute.GLOBAL) ||
            (if (let Some(outer) <- varDecl.outerDecl) { outer.IsNominalDecl() } else { false })
        if (isGlobalOrMember) {
            if (let Some(initializer) <- varDecl.initializer) {
                root = initializer
            }
        }
    }
    if (let Some(value) <- root) {
        let walker = Walker(value, visitPre: { node: Node =>
            if (let Some(param) <- (node as FuncParam)) {
                param.outerDecl = decl
                return VisitAction.SKIP_CHILDREN
            }
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                funcDecl.outerDecl = decl
                return VisitAction.SKIP_CHILDREN
            }
            VisitAction.WALK_CHILDREN
        })
        walker.Walk()
    }
}

public func IsInDeclWithAttribute(decl: Decl, attr: Attribute): Bool {
    var current: Option<Decl> = decl
    while (let Some(value) <- current) {
        if (value.TestAttr(attr)) {
            return true
        }
        if (let Some(funcDecl) <- (value as FuncDecl)) {
            if (let Some(ownerFunc) <- funcDecl.ownerFunc) {
                if (ownerFunc.TestAttr(attr)) {
                    return true
                }
            }
        }
        current = value.outerDecl
    }
    return false
}

public func InitializeLitConstValue(lce: LitConstExpr): Unit {
    if (!Ty.IsTyCorrect(lce.GetTy())) {
        return
    }
    lce.isConst = true
    let lceTy = lce.GetTy() ?? return
    let primitiveTyOpt = GetPrimitiveUpperBoundTy(lceTy)
    if (let None <- primitiveTyOpt) {
        return
    }
    let primitiveTy = primitiveTyOpt.getOrThrow()
    if (primitiveTy.IsInteger()) {
        let kind = if (primitiveTy.IsNative()) {
            if (primitiveTy.kind == TypeKind.TYPE_INT_NATIVE) {
                if (primitiveTy.bitness == 32u64) { TypeKind.TYPE_INT32 } else { TypeKind.TYPE_INT64 }
            } else {
                if (primitiveTy.bitness == 32u64) { TypeKind.TYPE_UINT32 } else { TypeKind.TYPE_UINT64 }
            }
        } else {
            primitiveTy.kind
        }
        let stringVal = if (IsSingleByteStringLiteral(lce)) {
            "${lce.codepoint[0]}"
        } else {
            lce.stringValue
        }
        lce.constNumValue.asInt.InitIntLiteral(stringVal, kind)
        return
    }
    if (primitiveTy.IsFloating()) {
        let builder = StringBuilder()
        for (byte in lce.stringValue.toArray()) {
            if (byte != b'_') {
                builder.append(String.fromUtf8([byte]))
            }
        }
        let stringValue = builder.toString()
        if (let Some(value) <- Stold(stringValue)) {
            lce.constNumValue.asFloat.value = value
        } else if (FloatFormat.IsUnderFlowFloat(stringValue)) {
            lce.constNumValue.asFloat.flowStatus = FlowStatus.UNDER
            lce.constNumValue.asFloat.value = 0.0
        } else {
            lce.constNumValue.asFloat.flowStatus = FlowStatus.OVER
            let value = GetFloatTypeInfoByKind(TypeKind.TYPE_FLOAT64).inf >> 1u64
            try (valuePtr = LibC.malloc<UInt64>().asResource()) {
                unsafe { valuePtr.value.write(value) }
                lce.constNumValue.asFloat.value = unsafe { CPointer<Float64>(valuePtr.value).read() }
            }
        }
        return
    }
    if (primitiveTy.IsBoolean()) {
        lce.constNumValue.asBoolean = lce.stringValue == "true"
    }
}

private func GetPrimitiveUpperBoundTy(ty: Ty): Option<PrimitiveTy> {
    if (let Some(primitive) <- (ty as PrimitiveTy)) {
        return primitive
    }
    if (!ty.IsGeneric()) {
        return None
    }
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        if (let Some(lowerBound) <- genericTy.lowerBound) {
            if (let Some(primitive) <- (lowerBound as PrimitiveTy)) {
                return primitive
            }
        }
    }
    return None
}

public func FlattenVarWithPatternDecl(vwpDecl: VarWithPatternDecl): ArrayList<Pattern> {
    let out = ArrayList<Pattern>()
    if (let Some(pattern) <- vwpDecl.irrefutablePattern) {
        let queue = ArrayList<Pattern>()
        queue.add(pattern)
        var idx: Int64 = 0
        while (idx < queue.size) {
            let current = queue[idx]
            if (let Some(_) <- (current as WildcardPattern)) {
                out.add(current)
            } else if (let Some(_) <- (current as VarPattern)) {
                out.add(current)
            } else if (let Some(tuplePattern) <- (current as TuplePattern)) {
                for (child in tuplePattern.patterns) {
                    queue.add(child)
                }
            } else if (let Some(enumPattern) <- (current as EnumPattern)) {
                for (child in enumPattern.patterns) {
                    queue.add(child)
                }
            }
            idx++
        }
    }
    return out
}

public func GetAnnotatedDeclKindString(decl: Decl): String {
    if (decl.astKind == ASTKind.CLASS_DECL || decl.astKind == ASTKind.INTERFACE_DECL ||
        decl.astKind == ASTKind.STRUCT_DECL || decl.astKind == ASTKind.ENUM_DECL) {
        return "type"
    }
    if (decl.astKind == ASTKind.FUNC_DECL) {
        if (decl.TestAttr(Attribute.CONSTRUCTOR)) {
            return "init"
        }
        return "member function"
    }
    if (decl.astKind == ASTKind.PROP_DECL) {
        return "member property"
    }
    if (decl.astKind == ASTKind.VAR_DECL) {
        return "member variable"
    }
    if (decl.astKind == ASTKind.FUNC_PARAM) {
        return "parameter"
    }
    return ASTKindName(decl.astKind)
}

public func IterateToplevelDecls(pkg: Package, process: (Decl) -> Unit): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            process(decl)
        }
        for (decl in file.exportedInternalDecls) {
            process(decl)
        }
    }
}

private func IterateAllMembersInTypeDecl(decl: InheritableDecl, action: (Decl) -> Unit): Unit {
    for (member in decl.GetMemberDeclPtrs()) {
        if (member.astKind == ASTKind.FUNC_DECL && !member.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            action(member)
        } else if (let Some(propDecl) <- (member as PropDecl)) {
            for (getter in propDecl.getters) {
                action(getter)
            }
            for (setter in propDecl.setters) {
                action(setter)
            }
        } else if (member.astKind == ASTKind.VAR_DECL) {
            action(member)
        }
    }
}

public func IterateAllExportableDecls(pkg: Package, action: (Decl) -> Unit): Unit {
    for (file in pkg.files) {
        for (decl in file.decls) {
            action(decl)
            if (let Some(inheritable) <- (decl as InheritableDecl)) {
                IterateAllMembersInTypeDecl(inheritable, action)
            }
        }
    }
}

public func IsPackageMemberAccess(ma: MemberAccess): Bool {
    if (let Some(base) <- ma.baseExpr) {
        if (let Some(target) <- getExprTarget(base)) {
            return target.astKind == ASTKind.PACKAGE_DECL
        }
    }
    return false
}

private func getExprTarget(expr: Expr): Option<Decl> {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.ref.target
    }
    if (let Some(member) <- (expr as MemberAccess)) {
        return member.target
    }
    return None
}

public func IsThisOrSuper(expr: Expr): Bool {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.isThis || refExpr.isSuper
    }
    return false
}

public func GetAccessLevel(node: Node): AccessLevel {
    var level = if (node.astKind == ASTKind.IMPORT_SPEC) { AccessLevel.PRIVATE } else { AccessLevel.INTERNAL }
    if (node.TestAttr(Attribute.PRIVATE)) {
        level = AccessLevel.PRIVATE
    } else if (node.TestAttr(Attribute.INTERNAL)) {
        level = AccessLevel.INTERNAL
    } else if (node.TestAttr(Attribute.PROTECTED)) {
        level = AccessLevel.PROTECTED
    } else if (node.TestAttr(Attribute.PUBLIC)) {
        level = AccessLevel.PUBLIC
    }
    if (let Some(decl) <- (node as Decl)) {
        if (let Some(outer) <- decl.outerDecl) {
            if (outer.IsNominalDecl()) {
                let parentLevel = getDirectAccessLevel(outer)
                if (AccessLevelRank(parentLevel) < AccessLevelRank(level)) {
                    return parentLevel
                }
            }
        }
    }
    return level
}

private func getDirectAccessLevel(node: Node): AccessLevel {
    if (node.TestAttr(Attribute.PRIVATE)) { return AccessLevel.PRIVATE }
    if (node.TestAttr(Attribute.INTERNAL)) { return AccessLevel.INTERNAL }
    if (node.TestAttr(Attribute.PROTECTED)) { return AccessLevel.PROTECTED }
    if (node.TestAttr(Attribute.PUBLIC)) { return AccessLevel.PUBLIC }
    return AccessLevel.INTERNAL
}

private func AccessLevelRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

public func GetAttrByAccessLevel(level: AccessLevel): Attribute {
    return match (level) {
        case AccessLevel.PRIVATE => Attribute.PRIVATE
        case AccessLevel.INTERNAL => Attribute.INTERNAL
        case AccessLevel.PROTECTED => Attribute.PROTECTED
        case AccessLevel.PUBLIC => Attribute.PUBLIC
    }
}

public func GetAccessLevelStr(node: Node): String {
    return GetAccessLevelStr(node, "")
}

public func GetAccessLevelStr(node: Node, surround: String): String {
    let value = if (node.TestAttr(Attribute.PRIVATE)) {
        "private"
    } else if (node.TestAttr(Attribute.INTERNAL)) {
        "internal"
    } else if (node.TestAttr(Attribute.PROTECTED)) {
        "protected"
    } else if (node.TestAttr(Attribute.PUBLIC)) {
        "public"
    } else {
        "private"
    }
    if (surround.isEmpty()) {
        return value
    }
    return surround + value + surround
}

public func GetAccessLevelStr(pkg: Package): String {
    return match (pkg.accessible) {
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case _ => "public"
    }
}

public func GetImportedItemFullName(content: ImportContent, commonPrefix!: String = ""): String {
    let builder = StringBuilder()
    if (!commonPrefix.isEmpty()) {
        builder.append(commonPrefix)
        builder.append(".")
    }
    builder.append(content.GetPrefixPath())
    if (content.kind == ImportKind.IMPORT_ALIAS || content.kind == ImportKind.IMPORT_SINGLE) {
        builder.append(".")
        builder.append(content.identifier.Val())
    }
    return builder.toString()
}

private func NeedPoint(str: String): Bool {
    if (str.size == 0) {
        return false
    }
    let byte = str[str.size - 1]
    return (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9')
}

public func ExtractArgumentsOfDeprecatedAnno(
    annotation: Annotation,
    message: Box<String>,
    since: Box<String>,
    strict: Box<Bool>
): Unit {
    for (arg in annotation.args) {
        if (let Some(expr) <- arg.expr) {
            if (let Some(lce) <- (expr as LitConstExpr)) {
                if (arg.name.Empty() || arg.name == "message") {
                    message.value = " " + lce.stringValue
                } else if (arg.name == "since") {
                    since.value = " since " + lce.stringValue
                } else if (arg.name == "strict") {
                    strict.value = lce.ToString() == "true"
                }
            }
        }
    }

    if (NeedPoint(message.value)) {
        message.value += "."
    }
    if (NeedPoint(since.value)) {
        since.value += "."
    }
}

public func IsCondition(expr: Expr): Bool {
    if (let Some(_) <- (expr as LetPatternDestructor)) {
        return true
    }
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(child) <- parenExpr.expr) {
            return IsCondition(child)
        }
        return false
    }
    if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
        if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
            if (let Some(left) <- binaryExpr.leftExpr) {
                if (IsCondition(left)) {
                    return true
                }
            }
            if (let Some(right) <- binaryExpr.rightExpr) {
                return IsCondition(right)
            }
        }
    }
    return false
}

public func DoesNotHaveEnumSubpattern(letExpr: LetPatternDestructor): Bool {
    for (pattern in letExpr.patterns) {
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            if (!enumPattern.patterns.isEmpty()) {
                return false
            }
        }
    }
    return true
}

public func IsNestedFunc(fd: FuncDecl): Bool {
    if (fd.TestAttr(Attribute.GLOBAL)) {
        return false
    }
    if (let Some(outer) <- fd.outerDecl) {
        return outer.IsFunc()
    }
    return true
}

public func IsDefaultImplementation(decl: Decl): Bool {
    if (!decl.TestAttr(Attribute.DEFAULT)) {
        return false
    }
    if (let Some(outer) <- decl.outerDecl) {
        return outer.astKind == ASTKind.INTERFACE_DECL
    }
    return false
}

public func InsideAtJavaDecl(decl: Decl): Bool {
    if ((decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.VAR_DECL) &&
        decl.TestAttr(Attribute.IN_CLASSLIKE)) {
        if (let Some(_) <- HasJavaAttr(decl)) {
            return true
        }
        return false
    }
    if (decl.astKind == ASTKind.FUNC_PARAM) {
        if (let Some(outer) <- decl.outerDecl) {
            return InsideAtJavaDecl(outer)
        }
    }
    return false
}

public func CanBeSrcExported(fd: FuncDecl): Bool {
    if (fd.isInline) {
        return true
    }
    let hasGenericBody = if (let Some(body) <- fd.funcBody) {
        if (let Some(_) <- body.generic) { true } else { false }
    } else {
        false
    }
    let isGenericFunction = hasGenericBody || fd.TestAttr(Attribute.GENERIC)
    if ((isGenericFunction || fd.IsExportedDecl() || fd.linkage != Linkage.INTERNAL) &&
        (fd.isConst || fd.isFrozen)) {
        return true
    }
    let ownerDecl = if (let Some(ownerFunc) <- fd.ownerFunc) { ownerFunc } else { fd }
    return !IsInDeclWithAttribute(ownerDecl, Attribute.GENERIC_INSTANTIATED) &&
        IsDefaultImplementation(ownerDecl)
}

public func IsInstMemberVarInGenericDecl(vd: VarDecl): Bool {
    return vd.astKind == ASTKind.VAR_DECL && !vd.TestAttr(Attribute.STATIC) &&
        IsInDeclWithAttribute(vd, Attribute.GENERIC)
}

public func IsCommonWithoutDefault(decl: Decl): Bool {
    return decl.TestAttr(Attribute.COMMON) && !decl.TestAttr(Attribute.COMMON_WITH_DEFAULT)
}

public func IsValidCFuncConstructorCall(ce: CallExpr): Bool {
    if (!Ty.IsTyCorrect(ce.GetTy())) {
        return false
    }
    if (let Some(baseFunc) <- ce.baseFunc) {
        if (let Some(refExpr) <- (baseFunc as RefExpr)) {
            if (let Some(target) <- refExpr.ref.target) {
                if (let Some(builtinDecl) <- (target as BuiltInDecl)) {
                    return builtinDecl.IsType(BuiltInType.CFUNC)
                }
            }
        }
    }
    return false
}

public func IsVirtualMember(decl: Decl): Bool {
    if (let Some(outer) <- decl.outerDecl) {
        if (outer.astKind == ASTKind.INTERFACE_DECL) {
            return true
        }
        if (outer.astKind == ASTKind.EXTEND_DECL) {
            return false
        }
        if (outer.astKind != ASTKind.CLASS_DECL) {
            return false
        }
        if (!outer.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
            return false
        }
    } else {
        return false
    }
    if (!decl.IsFuncOrProp()) {
        return false
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        let isGenericInstantiatedNonJava = decl.TestAttr(Attribute.GENERIC_INSTANTIATED) &&
            !decl.TestAnyAttr(Attribute.JAVA_APP, Attribute.JAVA_EXT)
        if (decl.TestAttr(Attribute.CONSTRUCTOR) || funcDecl.IsFinalizer() || isGenericInstantiatedNonJava) {
            return false
        }
    }
    if (!decl.TestAttr(Attribute.STATIC)) {
        if (decl.TestAnyAttr(Attribute.PRIVATE, Attribute.INTERNAL)) {
            return false
        }
        if (!decl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
            return false
        }
    } else if (decl.TestAttr(Attribute.PRIVATE)) {
        return false
    }
    return true
}

public func IsStaticVar(decl: Decl): Bool {
    return decl.astKind == ASTKind.VAR_DECL && decl.TestAttr(Attribute.STATIC)
}

public func IsMemberVarShouldBeSrcExported(vd: VarDecl): Bool {
    if (let Some(_) <- vd.outerDecl) {
        if (let Some(_) <- vd.initializer) {
            if (vd.TestAttr(Attribute.STATIC)) {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
    if (let Some(outer) <- vd.outerDecl) {
        if (let Some(structDecl) <- (outer as StructDecl)) {
            return structDecl.HasConstOrFrozenInit()
        }
        if (let Some(classDecl) <- (outer as ClassDecl)) {
            return classDecl.HasConstOrFrozenInit()
        }
    }
    return false
}

public class VarDeclWithPosition {
    public var decl: Option<VarDecl> = None
    public var fieldPosition: UInt64 = 0

    public init() {}

    public init(decl: VarDecl, fieldPosition: UInt64) {
        this.decl = decl
        this.fieldPosition = fieldPosition
    }
}

public func GetVarsInitializationOrderWithPositions(parentDecl: Decl): ArrayList<VarDeclWithPosition> {
    let commonDecls = ArrayList<VarDeclWithPosition>()
    let specificDecls = ArrayList<VarDeclWithPosition>()
    var fieldIdx: UInt64 = 0
    for (member in parentDecl.GetMemberDecls()) {
        if (member.astKind != ASTKind.VAR_DECL || member.IsStaticOrGlobal()) {
            continue
        }
        if (let Some(varDecl) <- (member as VarDecl)) {
            if (varDecl.TestAttr(Attribute.FROM_COMMON_PART)) {
                commonDecls.add(VarDeclWithPosition(varDecl, fieldIdx))
            } else {
                specificDecls.add(VarDeclWithPosition(varDecl, fieldIdx))
            }
            fieldIdx++
        }
    }
    sort(specificDecls, by: { left: VarDeclWithPosition, right: VarDeclWithPosition =>
        let leftDecl = left.decl.getOrThrow()
        let rightDecl = right.decl.getOrThrow()
        if (leftDecl.begin < rightDecl.begin) {
            Ordering.LT
        } else if (rightDecl.begin < leftDecl.begin) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })

    let resultDecls = ArrayList<VarDeclWithPosition>()
    var specificIdx: Int64 = 0
    let emittedSpecificDeps = ArrayList<Decl>()
    for (common in commonDecls) {
        let specificDeps = ArrayList<Decl>()
        if (let Some(commonDecl) <- common.decl) {
            for (depOpt in commonDecl.dependencies) {
                if (let Some(dep) <- depOpt) {
                    if (!dep.TestAttr(Attribute.SPECIFIC)) {
                        continue
                    }
                    var inserted = true
                    for (wasSpecificVar in emittedSpecificDeps) {
                        if (wasSpecificVar == dep) {
                            inserted = false
                            break
                        }
                    }
                    if (inserted) {
                        emittedSpecificDeps.add(dep)
                        specificDeps.add(dep)
                    }
                }
            }
        }
        while (!specificDeps.isEmpty()) {
            CJC_ASSERT(specificIdx < specificDecls.size)
            let candidate = specificDecls[specificIdx]
            let candidateDecl = candidate.decl.getOrThrow()
            var depIdx: Int64 = 0
            while (depIdx < specificDeps.size) {
                if (specificDeps[depIdx] == candidateDecl) {
                    specificDeps.remove(at: depIdx)
                    break
                }
                depIdx++
            }
            resultDecls.add(candidate)
            specificIdx++
        }
        resultDecls.add(common)
    }
    while (specificIdx < specificDecls.size) {
        resultDecls.add(specificDecls[specificIdx])
        specificIdx++
    }
    return resultDecls
}

public func InsertPropGetterSignature(propDecl: PropDecl, attrToBeSet: Attribute): Unit {
    let getter = FuncDecl()
    getter.identifier = SrcIdentifier("get", INVALID_POSITION, INVALID_POSITION, false)
    getter.outerDecl = propDecl.outerDecl
    getter.propDecl = propDecl
    getter.isGetter = true
    getter.CloneAttrs(propDecl)
    getter.DisableAttr(Attribute.MUT)
    getter.EnableAttr(Attribute.COMPILER_ADD)
    getter.EnableAttr(attrToBeSet)
    if (let Some(outer) <- propDecl.outerDecl) {
        if (outer.astKind == ASTKind.INTERFACE_DECL) {
            getter.EnableAttr(Attribute.PUBLIC)
        }
    }
    let getterBody = FuncBody()
    getterBody.EnableAttr(Attribute.COMPILER_ADD)
    let params = FuncParamList()
    params.EnableAttr(Attribute.COMPILER_ADD)
    getterBody.paramLists.add(params)
    getterBody.funcDecl = getter
    getter.funcBody = getterBody
    propDecl.getters.add(getter)
}

public func InsertPropSetterSignature(propDecl: PropDecl, attrToBeSet: Attribute): Unit {
    let setter = FuncDecl()
    setter.identifier = SrcIdentifier("set", INVALID_POSITION, INVALID_POSITION, false)
    setter.outerDecl = propDecl.outerDecl
    setter.propDecl = propDecl
    setter.isSetter = true
    setter.CloneAttrs(propDecl)
    setter.DisableAttr(Attribute.MUT)
    setter.EnableAttr(Attribute.COMPILER_ADD)
    setter.EnableAttr(attrToBeSet)
    if (let Some(outer) <- propDecl.outerDecl) {
        if (outer.astKind == ASTKind.INTERFACE_DECL) {
            setter.EnableAttr(Attribute.PUBLIC)
        }
    }
    let setterBody = FuncBody()
    setterBody.EnableAttr(Attribute.COMPILER_ADD)
    let params = FuncParamList()
    params.EnableAttr(Attribute.COMPILER_ADD)
    let setterParam = FuncParam()
    setterParam.EnableAttr(Attribute.COMPILER_ADD)
    setterParam.identifier = SrcIdentifier("set", INVALID_POSITION, INVALID_POSITION, false)
    params.params.add(setterParam)
    setterBody.paramLists.add(params)
    setterBody.funcDecl = setter
    setter.funcBody = setterBody
    propDecl.setters.add(setter)
}

public func InsertMirrorVarProp(decl: ClassDecl, attrToBeSet: Attribute): Unit {
    if (let Some(body) <- decl.body) {
        let oldVars = ArrayList<VarDecl>()
        for (member in body.decls) {
            if (member.astKind == ASTKind.VAR_DECL) {
                if (let Some(varDecl) <- (member as VarDecl)) {
                    if (let Some(_) <- varDecl.typeNode) {
                        oldVars.add(varDecl)
                    }
                }
            }
        }
        for (varDecl in oldVars) {
            body.decls.add(makeMirrorPropFromVar(varDecl, attrToBeSet))
        }
        var idx: Int64 = 0
        while (idx < body.decls.size) {
            if (body.decls[idx].astKind == ASTKind.VAR_DECL) {
                body.decls.remove(at: idx)
            } else {
                idx++
            }
        }
    }
}

private func makeMirrorPropFromVar(varDecl: VarDecl, attrToBeSet: Attribute): PropDecl {
    let propNode = PropDecl()
    propNode.begin = varDecl.begin
    propNode.end = varDecl.end
    propNode.keywordPos = varDecl.keywordPos
    propNode.identifier = varDecl.identifier
    propNode.colonPos = varDecl.colonPos
    propNode.typeNode = varDecl.typeNode
    if (let Some(ty) <- varDecl.GetTy()) {
        propNode.SetTy(ty)
    }
    propNode.CloneAttrs(varDecl)
    propNode.EnableAttr(Attribute.DESUGARED_MIRROR_FIELD)
    for (modifier in varDecl.modifiers) {
        propNode.modifiers.add(modifier)
    }
    propNode.isVar = varDecl.isVar
    for (annotation in varDecl.annotations) {
        if (let Some(cloned) <- (ASTCloner.Clone(annotation) as Annotation)) {
            propNode.annotations.add(cloned)
        }
    }
    if (varDecl.isVar) {
        propNode.EnableAttr(Attribute.MUT)
        let `mut` = Modifier(TokenKind.MUT, varDecl.begin)
        `mut`.curFile = varDecl.curFile
        propNode.modifiers.add(`mut`)
    }
    propNode.outerDecl = varDecl.outerDecl
    InsertPropGetterSignature(propNode, attrToBeSet)
    if (varDecl.isVar) {
        InsertPropSetterSignature(propNode, attrToBeSet)
    }
    return propNode
}

private func SetPositionAndCurFileByProvidedNode(consumer: Node, provider: Node): Unit {
    consumer.curFile = provider.curFile
    consumer.begin = provider.begin
    consumer.end = provider.end
}

public func IsImpl(node: Node): Bool {
    return !node.TestAttr(Attribute.JAVA_MIRROR) && node.TestAttr(Attribute.JAVA_MIRROR_SUBTYPE)
}

public func IsImpl(ty: Ty): Bool {
    if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
        if (let Some(decl) <- classLikeTy.commonDecl) {
            return IsImpl(decl)
        }
    }
    return false
}

public func IsJObject(decl: Decl): Bool {
    return IsJObject(decl, decl.fullPackageName)
}

public func IsJObject(decl: Decl, packageName: String): Bool {
    return IsMirror(decl) && decl.identifier.Val() == INTEROP_JOBJECT_NAME &&
        packageName == INTEROP_JAVA_LANG_PACKAGE
}

public func IsMirror(node: Node): Bool {
    return node.TestAttr(Attribute.JAVA_MIRROR)
}

public func IsMirror(ty: Ty): Bool {
    if (let Some(classLikeTy) <- (ty as ClassLikeTy)) {
        if (let Some(decl) <- classLikeTy.commonDecl) {
            return IsMirror(decl)
        }
    }
    return false
}

public func IsCJMapping(node: Node): Bool {
    return node.TestAttr(Attribute.JAVA_CJ_MAPPING)
}

public func IsObject(node: Node): Bool {
    if (let Some(ty) <- node.GetTy()) {
        return ty.IsObject()
    }
    return false
}

public func IsFwdClass(node: Node): Bool {
    return node.TestAttr(Attribute.CJ_MIRROR_JAVA_INTERFACE_FWD)
}

public func InsertJavaRefGetterStubWithBody(decl: ClassDecl): Unit {
    let callParams = ArrayList<FuncParam>()
    let paramLists = ArrayList<FuncParamList>()
    let paramList = CreateFuncParamList(callParams)
    paramList.begin = decl.begin
    paramList.end = decl.end
    paramLists.add(paramList)

    let constructor = CreateCallExpr(CreateRefExpr(INTEROPLIB_CFFI_JAVA_ENTITY), ArrayList<FuncArg>())
    let retExpr = CreateReturnExpr(constructor)
    let nodes = ArrayList<Node>()
    nodes.add(retExpr)

    let funcBody = CreateFuncBody(paramLists, Some(CreateRefType(INTEROPLIB_CFFI_JAVA_ENTITY)),
        Some(CreateBlock(nodes)), None)
    let funcDecl = CreateFuncDecl(JAVA_REF_GETTER_FUNC_NAME, Some(funcBody), None)
    funcDecl.EnableAttr(Attribute.PUBLIC)
    funcDecl.EnableAttr(Attribute.IN_CLASSLIKE)
    funcDecl.fullPackageName = decl.fullPackageName
    if (let Some(body) <- funcDecl.funcBody) {
        body.funcDecl = funcDecl
        body.parentClassLike = decl
    }
    funcDecl.outerDecl = decl

    if (let Some(body) <- decl.body) {
        body.decls.add(funcDecl)
    }
}

public func IsDeclAppropriateForSyntheticClassGeneration(node: Node): Bool {
    return IsMirror(node) && (node.IsInterfaceDecl() || node.IsAbstractClass())
}

public func GetSyntheticNameFromClassLike(decl: ClassLikeDecl): String {
    return decl.identifier.Val() + "$impl"
}

public func InsertSyntheticClassDecl(decl: ClassLikeDecl, file: File): Unit {
    let synthetic = ClassDecl()
    if (decl.TestAttr(Attribute.PUBLIC)) {
        synthetic.EnableAttr(Attribute.PUBLIC)
    } else if (decl.TestAttr(Attribute.INTERNAL)) {
        synthetic.EnableAttr(Attribute.INTERNAL)
    } else if (decl.TestAttr(Attribute.PROTECTED)) {
        synthetic.EnableAttr(Attribute.PROTECTED)
    } else if (decl.TestAttr(Attribute.PRIVATE)) {
        synthetic.EnableAttr(Attribute.PRIVATE)
    }
    synthetic.EnableAttr(Attribute.JAVA_MIRROR)
    synthetic.EnableAttr(Attribute.JAVA_MIRROR_SUBTYPE)
    synthetic.EnableAttr(Attribute.JAVA_MIRROR_SYNTHETIC_WRAPPER)
    synthetic.EnableAttr(Attribute.COMPILER_ADD)
    synthetic.EnableAttr(Attribute.ABSTRACT)
    synthetic.identifier = SrcIdentifier(GetSyntheticNameFromClassLike(decl), decl.identifier.Begin(),
        decl.identifier.End(), decl.identifier.IsRaw())

    if (decl.astKind == ASTKind.INTERFACE_DECL) {
        let jobject = CreateRefType(INTEROP_JOBJECT_NAME)
        SetPositionAndCurFileByProvidedNode(jobject, decl)
        synthetic.inheritedTypes.add(jobject)
    }
    synthetic.inheritedTypes.add(CreateRefType(decl))

    synthetic.fullPackageName = decl.fullPackageName
    SetPositionAndCurFileByProvidedNode(synthetic, decl)

    let body = ClassBody()
    SetPositionAndCurFileByProvidedNode(body, synthetic)
    synthetic.body = body

    synthetic.moduleName = GetRootPackageName(decl.fullPackageName)
    file.decls.add(synthetic)
}

public func IsObjCDeclAppropriateForSyntheticClassGeneration(decl: Decl): Bool {
    return decl.TestAttr(Attribute.OBJ_C_MIRROR) && decl.astKind == ASTKind.INTERFACE_DECL
}

public func GetObjCSyntheticNameFromClassLike(decl: ClassLikeDecl): String {
    return decl.identifier.Val() + SYNTHETIC_CLASS_SUFFIX
}

public func InsertObjCSyntheticClassDecl(decl: ClassLikeDecl, file: File): ClassDecl {
    let synthetic = ClassDecl()
    synthetic.CloneAttrs(decl)
    synthetic.EnableAttr(Attribute.OBJ_C_MIRROR_SYNTHETIC_WRAPPER)
    synthetic.EnableAttr(Attribute.COMPILER_ADD)
    synthetic.EnableAttr(Attribute.ABSTRACT)
    synthetic.DisableAttr(Attribute.OBJ_C_MIRROR)
    synthetic.identifier = SrcIdentifier(GetObjCSyntheticNameFromClassLike(decl), decl.identifier.Begin(),
        decl.identifier.End(), decl.identifier.IsRaw())
    synthetic.inheritedTypes.add(CreateRefType(decl))
    synthetic.fullPackageName = decl.fullPackageName
    SetPositionAndCurFileByProvidedNode(synthetic, decl)

    let body = ClassBody()
    SetPositionAndCurFileByProvidedNode(body, synthetic)
    synthetic.body = body

    synthetic.moduleName = GetRootPackageName(decl.fullPackageName)
    file.decls.add(synthetic)
    return synthetic
}
