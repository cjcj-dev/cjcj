package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind

public class RealMemberDecl {
    public var isGetter: Bool
    public var decl: Decl

    public init(isGetter: Bool, decl: Decl) {
        this.isGetter = isGetter
        this.decl = decl
    }
}

public class ParamTyAtIndex {
    public var ty: Ty
    public var index: Int64

    public init(ty: Ty, index: Int64) {
        this.ty = ty
        this.index = index
    }
}

private class TypeCheckUtilBoolBox {
    public var value: Bool

    public init(value: Bool) {
        this.value = value
    }
}

public func GetIdealTypesByKind(kind: TypeKind): ArrayList<TypeKind> {
    let out = ArrayList<TypeKind>()
    if (kind == TypeKind.TYPE_IDEAL_INT) {
        out.add(TypeKind.TYPE_INT8)
        out.add(TypeKind.TYPE_INT16)
        out.add(TypeKind.TYPE_INT32)
        out.add(TypeKind.TYPE_INT_NATIVE)
        out.add(TypeKind.TYPE_INT64)
        out.add(TypeKind.TYPE_UINT8)
        out.add(TypeKind.TYPE_UINT16)
        out.add(TypeKind.TYPE_UINT32)
        out.add(TypeKind.TYPE_UINT64)
        out.add(TypeKind.TYPE_UINT_NATIVE)
    } else if (kind == TypeKind.TYPE_IDEAL_FLOAT) {
        out.add(TypeKind.TYPE_FLOAT16)
        out.add(TypeKind.TYPE_FLOAT32)
        out.add(TypeKind.TYPE_FLOAT64)
    }
    return out
}

public func UpdateInstTysWithTypeArgs(expr: NameReferenceExpr): Bool {
    if (!expr.instTys.isEmpty()) {
        return true
    }
    if (HasIntersectionTy(expr.GetTypeArgs())) {
        return true
    }
    for (typeArg in expr.GetTypeArgs()) {
        if (let Some(typeArgTy) <- typeArg.GetTy()) {
            expr.instTys.add(typeArgTy)
        } else {
            expr.instTys.clear()
            return false
        }
    }
    return true
}

public func SetIsNotAlone(baseExpr: Expr): Unit {
    if (let Some(nameRef) <- (baseExpr as NameReferenceExpr)) {
        nameRef.isAlone = false
    }
}

public func HasIntersectionTy(types: ArrayList<Type>): Bool {
    for (typeNode in types) {
        if (let Some(ty) <- typeNode.GetTy()) {
            if (ty.HasIntersectionTy()) {
                return true
            }
        }
    }
    return false
}

public func NeedFurtherInstantiation(types: ArrayList<Type>): Bool {
    return types.isEmpty() || HasIntersectionTy(types)
}

public func ReplaceTarget(node: Node, target: Option<Decl>, insertTarget!: Bool = true): Unit {
    if (let None <- target) {
        if (!Ty.IsTyCorrect(node.GetTy())) {
            node.SetTy(TypeManager.GetInvalidTy())
        }
    }
    let aliasDecl: Option<TypeAliasDecl> = if (let Some(value) <- target) {
        value as TypeAliasDecl
    } else {
        None
    }
    node.SetTarget(target)
    if (let Some(refExpr) <- (node as RefExpr)) {
        if (let Some(_) <- aliasDecl) {
            refExpr.aliasTarget = aliasDecl
        } else if (let None <- target) {
            refExpr.aliasTarget = None
        }
    } else if (let Some(memberAccess) <- (node as MemberAccess)) {
        if (let Some(_) <- aliasDecl) {
            memberAccess.aliasTarget = aliasDecl
        } else if (let None <- target) {
            memberAccess.aliasTarget = None
        }
    }
    if (let Some(symbol) <- node.symbol) {
        symbol.UnbindTarget()
        if (insertTarget && node.begin.fileID != 0) {
            symbol.target = target
        }
    }
}

public func ModifyTargetOfRef(refExpr: RefExpr, target: Decl, targets: ArrayList<Decl>): Unit {
    ReplaceTarget(refExpr, Some(target))
    let copiedTargets = ArrayList<Decl>()
    for (candidate in targets) {
        copiedTargets.add(candidate)
    }
    refExpr.ref.targets.clear()
    for (candidate in copiedTargets) {
        refExpr.ref.targets.add(candidate)
    }
}

public func AddFuncTargetsForMemberAccess(memberAccess: MemberAccess, targets: ArrayList<Decl>): Unit {
    let copiedTargets = ArrayList<Decl>()
    for (decl in targets) {
        copiedTargets.add(decl)
    }
    memberAccess.targets.clear()
    for (decl in copiedTargets) {
        if (memberAccess.isPattern || decl.astKind == ASTKind.FUNC_DECL) {
            memberAccess.targets.add(decl)
        }
    }
}

public func IsFuncReturnThisType(fd: FuncDecl): Bool {
    if (let Some(body) <- fd.funcBody) {
        if (let Some(retType) <- body.retType) {
            if (let Some(refType) <- (retType as RefType)) {
                return refType.ref.identifier.Val() == "This"
            }
        }
    }
    return false
}

public func CheckThisTypeCompatibility(parentFunc: FuncDecl, childFunc: FuncDecl): Bool {
    return !IsFuncReturnThisType(parentFunc) || IsFuncReturnThisType(childFunc)
}

public func HasMainDecl(pkg: Package): Bool {
    let found = TypeCheckUtilBoolBox(false)
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            if (decl.astKind == ASTKind.MAIN_DECL) {
                found.value = true
                return VisitAction.STOP_NOW
            }
            return VisitAction.SKIP_CHILDREN
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return found.value
}

public func MarkParamWithInitialValue(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(param) <- (node as FuncParam)) {
            if (let Some(_) <- param.assignment) {
                param.EnableAttr(Attribute.HAS_INITIAL)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func IsOverloadableOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR || op == TokenKind.DIV || op == TokenKind.EQUAL ||
        op == TokenKind.EXP || op == TokenKind.GE || op == TokenKind.GT ||
        op == TokenKind.LE || op == TokenKind.LSHIFT || op == TokenKind.LT ||
        op == TokenKind.MOD || op == TokenKind.MUL || op == TokenKind.NOT ||
        op == TokenKind.NOTEQ || op == TokenKind.RSHIFT || op == TokenKind.SUB
}

public func CanSkipDiag(node: Node): Bool {
    return !Ty.IsTyCorrect(node.GetTy())
}

public func IsFieldOperator(field: String): Bool {
    return field == "@" || field == "." || field == "[]" || field == "()" || field == "++" ||
        field == "--" || field == "?" || field == "!" || field == "-" || field == "**" ||
        field == "*" || field == "/" || field == "%" || field == "+" || field == "<<" ||
        field == ">>" || field == "<" || field == "<=" || field == ">" || field == ">=" ||
        field == "is" || field == "as" || field == "==" || field == "!=" || field == "&" ||
        field == "^" || field == "|" || field == ".." || field == "..=" || field == "&&" ||
        field == "||" || field == "??" || field == "~>" || field == "=" || field == "**=" ||
        field == "*=" || field == "/=" || field == "%/" || field == "+=" || field == "-=" ||
        field == "<<=" || field == ">>=" || field == "&=" || field == "^=" || field == "|="
}

public func GetFuncBodyParamTys(fb: FuncBody): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    if (fb.paramLists.isEmpty()) {
        return out
    }
    for (param in fb.paramLists[0].params) {
        if (let Some(typeNode) <- param.typeNode) {
            if (let Some(paramTy) <- typeNode.GetTy()) {
                param.SetTy(paramTy)
            }
        }
        if (let Some(ty) <- param.GetTy()) {
            out.add(ty)
        } else {
            out.add(TypeManager.GetInvalidTy())
        }
    }
    return out
}

public func GetParamTys(fd: FuncDecl): ArrayList<Ty> {
    if (fd.TestAttr(Attribute.IMPORTED)) {
        if (let Some(fdTy) <- fd.GetTy()) {
            if (let Some(funcTy) <- (fdTy as FuncTy)) {
                let importedParamTys = ArrayList<Ty>()
                for (paramTy in funcTy.paramTys) {
                    importedParamTys.add(paramTy)
                }
                return importedParamTys
            }
        }
    }
    if (let Some(body) <- fd.funcBody) {
        return GetFuncBodyParamTys(body)
    }
    return ArrayList<Ty>()
}

public func GetRealTarget(decl: Option<Decl>): Option<Decl> {
    if (let Some(value) <- decl) {
        let visited = HashSet<String>()
        return Some(GetRealTargetVisit(value, visited))
    }
    return None
}

public func GetRealTarget(decl: Decl): Decl {
    let visited = HashSet<String>()
    return GetRealTargetVisit(decl, visited)
}

private func GetRealTargetVisit(decl: Decl, visited: HashSet<String>): Decl {
    let key = TypeCheckUtilDeclKey(decl)
    if (visited.contains(key)) {
        return decl
    }
    visited.add(key)
    if (let Some(aliasDecl) <- (decl as TypeAliasDecl)) {
        if (!aliasDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
            if (let Some(typeNode) <- aliasDecl.typeNode) {
                if (let Some(realTarget) <- typeNode.GetTarget()) {
                    return GetRealTargetVisit(realTarget, visited)
                }
            }
        }
    }
    return decl
}

public func GetRealMemberDecl(decl: Decl): RealMemberDecl {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(propDecl) <- funcDecl.propDecl) {
            return RealMemberDecl(funcDecl.isGetter, propDecl)
        }
    }
    return RealMemberDecl(false, decl)
}

public func GetUsedMemberDecl(decl: Decl, isGetter: Bool): Decl {
    if (let Some(propDecl) <- (decl as PropDecl)) {
        let funcs = if (isGetter) { propDecl.getters } else { propDecl.setters }
        if (!funcs.isEmpty()) {
            return funcs[0]
        }
    }
    return decl
}

public func DeclKindToString(decl: Decl): String {
    return match (decl.astKind) {
        case ASTKind.CLASS_DECL => "class"
        case ASTKind.ENUM_DECL => "enum"
        case ASTKind.EXTEND_DECL => "extend"
        case ASTKind.FUNC_DECL => "function"
        case ASTKind.FUNC_PARAM => "parameter"
        case ASTKind.INTERFACE_DECL => "interface"
        case ASTKind.MACRO_DECL => "macro"
        case ASTKind.MAIN_DECL => "main"
        case ASTKind.PACKAGE_DECL => "package"
        case ASTKind.PRIMARY_CTOR_DECL => "primary constructor"
        case ASTKind.PROP_DECL => "property"
        case ASTKind.STRUCT_DECL => "struct"
        case ASTKind.TYPE_ALIAS_DECL => "type alias"
        case ASTKind.VAR_DECL => "variable"
        case ASTKind.VAR_WITH_PATTERN_DECL => "variable"
        case _ => decl.identifier.Val()
    }
}

public func GetTypesStr(decls: ArrayList<Decl>): String {
    let seen = HashSet<String>()
    let parts = ArrayList<String>()
    for (decl in decls) {
        let text = DeclKindToString(decl)
        if (!seen.contains(text)) {
            seen.add(text)
            parts.add(text)
        }
    }
    return JoinStrings(parts, " ")
}

private func FindValidPropAccessor(classDecl: ClassDecl, isGetter: Bool, name: String): Option<FuncDecl> {
    var current: Option<ClassDecl> = Some(classDecl)
    while (let Some(curClass) <- current) {
        for (member in curClass.GetMemberDecls()) {
            if (member.identifier.Val() != name) {
                continue
            }
            let found = GetUsedMemberDecl(member, isGetter)
            if (let Some(funcDecl) <- (found as FuncDecl)) {
                return Some(funcDecl)
            }
        }
        current = curClass.GetSuperClassDecl()
    }
    return None
}

public func GetUsableGetterForProperty(propDecl: PropDecl): Option<FuncDecl> {
    if (!propDecl.getters.isEmpty()) {
        return Some(propDecl.getters[0])
    }
    if (let Some(outer) <- propDecl.outerDecl) {
        if (let Some(classDecl) <- (outer as ClassDecl)) {
            return FindValidPropAccessor(classDecl, true, propDecl.identifier.Val())
        }
    }
    return None
}

public func GetUsableSetterForProperty(propDecl: PropDecl): Option<FuncDecl> {
    if (!propDecl.setters.isEmpty()) {
        return Some(propDecl.setters[0])
    }
    if (let Some(outer) <- propDecl.outerDecl) {
        if (let Some(classDecl) <- (outer as ClassDecl)) {
            return FindValidPropAccessor(classDecl, false, propDecl.identifier.Val())
        }
    }
    return None
}

public func GetUsableGetterSetterForProperty(propDecl: PropDecl): (Option<FuncDecl>, Option<FuncDecl>) {
    return (GetUsableGetterForProperty(propDecl), GetUsableSetterForProperty(propDecl))
}

public func CountOptionNestedLevel(ty: Ty): Int64 {
    var level: Int64 = 0
    var current: Option<Ty> = Some(ty)
    while (let Some(currentTy) <- current) {
        if (!currentTy.IsCoreOptionType() || currentTy.typeArgs.size != 1) {
            break
        }
        level++
        current = Some(currentTy.typeArgs[0])
    }
    return level
}

public func UnboxOptionType(ty: Ty): Ty {
    var current = ty
    var keepGoing = true
    while (keepGoing) {
        keepGoing = false
        if (Ty.IsTyCorrect(current) && current.IsCoreOptionType() && current.typeArgs.size == 1) {
            current = current.typeArgs[0]
            keepGoing = true
        }
    }
    return current
}

public func GetFuncTargets(node: Node): ArrayList<FuncDecl> {
    let out = ArrayList<FuncDecl>()
    if (let Some(refExpr) <- (node as RefExpr)) {
        for (target in refExpr.ref.targets) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                out.add(funcDecl)
            }
        }
    } else if (let Some(memberAccess) <- (node as MemberAccess)) {
        for (target in memberAccess.targets) {
            if (let Some(funcDecl) <- (target as FuncDecl)) {
                out.add(funcDecl)
            }
        }
    }
    return out
}

public func FindModifier(decl: Decl, kind: TokenKind): Option<Modifier> {
    var found: Option<Modifier> = None
    for (modifier in decl.modifiers) {
        if (modifier.modifier == kind) {
            found = Some(modifier)
        }
    }
    return found
}

public func FindFirstAnnotation(decl: Decl, kind: AstAnnotationKind): Option<Annotation> {
    for (annotation in decl.annotations) {
        if (annotation.kind == kind) {
            return Some(annotation)
        }
    }
    return None
}

public func GetParamTyAccordingToArgName(fd: FuncDecl, argName: String): Option<ParamTyAtIndex> {
    if (argName.isEmpty()) {
        return None
    }
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            var idx: Int64 = 0
            while (idx < body.paramLists[0].params.size) {
                let param = body.paramLists[0].params[idx]
                if (param.identifier.Val() == argName) {
                    if (let Some(typeNode) <- param.typeNode) {
                        if (let Some(typeTy) <- typeNode.GetTy()) {
                            return Some(ParamTyAtIndex(typeTy, idx))
                        }
                    }
                    if (let Some(paramTy) <- param.GetTy()) {
                        return Some(ParamTyAtIndex(paramTy, idx))
                    }
                    return Some(ParamTyAtIndex(TypeManager.GetInvalidTy(), idx))
                }
                idx++
            }
        }
    }
    return None
}

public func GetArgName(fd: FuncDecl, arg: FuncArg): String {
    if (arg.TestAttr(Attribute.IMPLICIT_ADD)) {
        if (let Some(body) <- fd.funcBody) {
            if (!body.paramLists.isEmpty() && !body.paramLists[0].params.isEmpty()) {
                let lastParam = body.paramLists[0].params[body.paramLists[0].params.size - 1]
                if (lastParam.isNamedParam) {
                    return lastParam.identifier.Val()
                }
            }
        }
        return ""
    }
    return if (arg.name.Empty()) { "" } else { arg.name.Val() }
}

public func GetCurrentGeneric(fd: FuncDecl, ce: CallExpr): Option<Generic> {
    if (let Some(body) <- fd.funcBody) {
        if (let Some(generic) <- body.generic) {
            return Some(generic)
        }
    }
    if (let Some(outer) <- fd.outerDecl) {
        if (IsTypeObjectCreation(fd, ce)) {
            return outer.GetGeneric()
        }
    }
    return None
}

public func GetParamTysInArgsOrder(typeManager: TypeManager, ce: CallExpr, fd: FuncDecl): ArrayList<Ty> {
    let empty = ArrayList<Ty>()
    if (let None <- fd.funcBody) {
        return empty
    }
    let body = fd.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        return empty
    }
    let paramList = body.paramLists[0]
    let paramHasTy = ArrayList<Bool>()
    for (param in paramList.params) {
        paramHasTy.add(param.TestAttr(Attribute.HAS_INITIAL))
    }
    var namedArgFound = false
    let tyInArgOrder = ArrayList<Ty>()
    var argIdx: Int64 = 0
    while (argIdx < ce.args.size) {
        let argName = GetArgName(fd, ce.args[argIdx])
        if (argName.isEmpty()) {
            if (namedArgFound) {
                return empty
            }
            if (argIdx < paramList.params.size) {
                let param = paramList.params[argIdx]
                if (let Some(paramTy) <- param.GetTy()) {
                    tyInArgOrder.add(paramTy)
                } else {
                    tyInArgOrder.add(TypeManager.GetInvalidTy())
                }
                paramHasTy[argIdx] = true
            } else if (fd.TestAttr(Attribute.C)) {
                tyInArgOrder.add(typeManager.GetCTypeTy())
            } else if (HasJavaAttr(fd)) {
                tyInArgOrder.add(typeManager.GetAnyTy())
            } else {
                return empty
            }
        } else {
            namedArgFound = true
            if (let Some(paramInfo) <- GetParamTyAccordingToArgName(fd, argName)) {
                tyInArgOrder.add(paramInfo.ty)
                if (paramInfo.index < paramHasTy.size) {
                    paramHasTy[paramInfo.index] = true
                }
            } else {
                return empty
            }
        }
        argIdx++
    }
    for (hasTy in paramHasTy) {
        if (!hasTy) {
            return empty
        }
    }
    return tyInArgOrder
}

public func IsEnumCtorWithoutTypeArgs(expr: Expr, target: Option<Decl>): Bool {
    if (let Some(decl) <- target) {
        if (!decl.TestAttr(Attribute.ENUM_CONSTRUCTOR) || (let None <- decl.GetGeneric())) {
            return false
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            return refExpr.GetTypeArgs().isEmpty()
        }
        if (let Some(memberAccess) <- (expr as MemberAccess)) {
            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                if (baseExpr.IsReferenceExpr()) {
                    return NeedFurtherInstantiation(baseExpr.GetTypeArgs()) && expr.GetTypeArgs().isEmpty()
                }
            }
        }
    }
    return false
}

public func IsQuestableNode(node: Node): Bool {
    return node.astKind == ASTKind.FUNC_ARG || node.astKind == ASTKind.PAREN_EXPR ||
        node.astKind == ASTKind.LAMBDA_EXPR || node.astKind == ASTKind.CALL_EXPR ||
        node.astKind == ASTKind.TRAIL_CLOSURE_EXPR
}

public func AcceptPlaceholderTarget(node: Node): Bool {
    return node.astKind == ASTKind.PATTERN || node.astKind == ASTKind.VAR_PATTERN ||
        node.astKind == ASTKind.CONST_PATTERN || node.astKind == ASTKind.TUPLE_PATTERN ||
        node.astKind == ASTKind.ENUM_PATTERN || node.astKind == ASTKind.VAR_OR_ENUM_PATTERN ||
        node.astKind == ASTKind.TYPE_PATTERN || node.astKind == ASTKind.EXCEPT_TYPE_PATTERN ||
        node.astKind == ASTKind.WILDCARD_PATTERN || node.astKind == ASTKind.CALL_EXPR ||
        node.astKind == ASTKind.PAREN_EXPR || node.astKind == ASTKind.MEMBER_ACCESS ||
        node.astKind == ASTKind.REF_EXPR || node.astKind == ASTKind.OPTIONAL_EXPR ||
        node.astKind == ASTKind.OPTIONAL_CHAIN_EXPR || node.astKind == ASTKind.MATCH_EXPR ||
        node.astKind == ASTKind.BLOCK || node.astKind == ASTKind.IF_EXPR ||
        node.astKind == ASTKind.TRY_EXPR || node.astKind == ASTKind.LAMBDA_EXPR ||
        node.astKind == ASTKind.TRAIL_CLOSURE_EXPR || node.astKind == ASTKind.SPAWN_EXPR ||
        node.astKind == ASTKind.MATCH_CASE || node.astKind == ASTKind.MATCH_CASE_OTHER ||
        node.astKind == ASTKind.FUNC_ARG || node.astKind == ASTKind.FUNC_BODY ||
        node.astKind == ASTKind.FUNC_PARAM
}

private func IsTypeObjectCreation(fd: FuncDecl, ce: CallExpr): Bool {
    if (ce.callKind == CallKind.CALL_OBJECT_CREATION || ce.callKind == CallKind.CALL_STRUCT_CREATION) {
        return true
    }
    return fd.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR)
}

private func HasJavaAttr(fd: FuncDecl): Bool {
    return fd.TestAnyAttr(Attribute.JAVA_APP, Attribute.JAVA_EXT)
}

private func TypeCheckUtilDeclKey(decl: Decl): String {
    return "${ASTKindIndex(decl.astKind)}:${decl.fullPackageName}:${decl.identifier.Val()}:" +
        "${decl.begin.ToString()}:${decl.end.ToString()}"
}

public func SelfhostPortStatus_TypeCheckUtil(): Bool {
    return true
}
