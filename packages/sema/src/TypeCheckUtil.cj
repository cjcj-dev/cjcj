package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::utils.CJC_ASSERT
import cjcj::utils.GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME
import cjcj::utils.IS_SUBTYPE_TYPES_FUNC_NAME

public func IsAllFuncDecl(results: ArrayList<Decl>): Bool {
    for (result in results) {
        if (result.astKind != ASTKind.FUNC_DECL && result.astKind != ASTKind.MACRO_DECL) {
            return false
        }
    }
    return true
}

public func NeedSynOnUsed(target: Decl): Bool {
    return !target.IsTypeDecl() && target.astKind != ASTKind.FUNC_PARAM &&
        (!Ty.IsTyCorrect(target.GetTy()) || target.GetTy().getOrThrow().HasQuestTy())
}

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

// C++ src/Sema/Utils.cpp:349-365 TypeCheckUtil::GetCurFuncBody.
public func GetCurFuncBody(ctx: ASTContext, scopeName: String): Option<FuncBody> {
    if (let Some(symbol) <- ScopeManager.GetCurSymbolByKind(SymbolKind.FUNC_LIKE, ctx, scopeName)) {
        if (let Some(node) <- symbol.node) {
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                return funcDecl.funcBody
            } else if (let Some(lambdaExpr) <- (node as LambdaExpr)) {
                return lambdaExpr.funcBody
            } else if (let Some(macroDecl) <- (node as MacroDecl)) {
                return macroDecl.desugarDecl.getOrThrow().funcBody
            } else if (let Some(primaryCtorDecl) <- (node as PrimaryCtorDecl)) {
                return primaryCtorDecl.funcBody
            }
        }
    }
    return None
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

private func GENERAL_ARITHMIC_INT_TYPE_MAP(): ArrayList<(TypeKind, TypeKind)> {
    let out = ArrayList<(TypeKind, TypeKind)>()
    out.add((TypeKind.TYPE_INT8, TypeKind.TYPE_INT8))
    out.add((TypeKind.TYPE_INT16, TypeKind.TYPE_INT16))
    out.add((TypeKind.TYPE_INT32, TypeKind.TYPE_INT32))
    out.add((TypeKind.TYPE_INT64, TypeKind.TYPE_INT64))
    out.add((TypeKind.TYPE_INT_NATIVE, TypeKind.TYPE_INT_NATIVE))
    out.add((TypeKind.TYPE_IDEAL_INT, TypeKind.TYPE_IDEAL_INT))
    out.add((TypeKind.TYPE_UINT8, TypeKind.TYPE_UINT8))
    out.add((TypeKind.TYPE_UINT16, TypeKind.TYPE_UINT16))
    out.add((TypeKind.TYPE_UINT32, TypeKind.TYPE_UINT32))
    out.add((TypeKind.TYPE_UINT64, TypeKind.TYPE_UINT64))
    out.add((TypeKind.TYPE_UINT_NATIVE, TypeKind.TYPE_UINT_NATIVE))
    return out
}

private func GENERAL_ARITHMIC_TYPE_MAP(): ArrayList<(TypeKind, TypeKind)> {
    let out = GENERAL_ARITHMIC_INT_TYPE_MAP()
    out.add((TypeKind.TYPE_FLOAT16, TypeKind.TYPE_FLOAT16))
    out.add((TypeKind.TYPE_FLOAT32, TypeKind.TYPE_FLOAT32))
    out.add((TypeKind.TYPE_FLOAT64, TypeKind.TYPE_FLOAT64))
    out.add((TypeKind.TYPE_IDEAL_FLOAT, TypeKind.TYPE_IDEAL_FLOAT))
    return out
}

private func GENERAL_RELATION_NUMERIC_TYPE_MAP(): ArrayList<(TypeKind, TypeKind)> {
    let out = ArrayList<(TypeKind, TypeKind)>()
    out.add((TypeKind.TYPE_INT8, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_INT16, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_INT32, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_INT64, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_INT_NATIVE, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_IDEAL_INT, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_UINT8, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_UINT16, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_UINT32, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_UINT64, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_UINT_NATIVE, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_FLOAT16, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_FLOAT32, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_FLOAT64, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_IDEAL_FLOAT, TypeKind.TYPE_BOOLEAN))
    out.add((TypeKind.TYPE_RUNE, TypeKind.TYPE_BOOLEAN))
    return out
}

private func EMPTY_KIND_MAP(): ArrayList<(TypeKind, TypeKind)> {
    return ArrayList<(TypeKind, TypeKind)>()
}

private func UNARY_EXPR_TYPE_MAP(op: TokenKind): ArrayList<(TypeKind, TypeKind)> {
    if (op == TokenKind.SUB) {
        return GENERAL_ARITHMIC_TYPE_MAP()
    } else if (op == TokenKind.NOT) {
        let out = GENERAL_ARITHMIC_INT_TYPE_MAP()
        out.add((TypeKind.TYPE_BOOLEAN, TypeKind.TYPE_BOOLEAN))
        return out
    } else if (op == TokenKind.BITNOT) {
        return GENERAL_ARITHMIC_INT_TYPE_MAP()
    } else if (op == TokenKind.INCR || op == TokenKind.DECR) {
        return GENERAL_ARITHMIC_INT_TYPE_MAP()
    }
    return EMPTY_KIND_MAP()
}

private func BINARY_EXPR_TYPE_MAP(op: TokenKind): ArrayList<(TypeKind, TypeKind)> {
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        return GENERAL_ARITHMIC_TYPE_MAP()
    } else if (op == TokenKind.MOD || op == TokenKind.LSHIFT || op == TokenKind.RSHIFT ||
        op == TokenKind.BITAND || op == TokenKind.BITXOR || op == TokenKind.BITOR) {
        return GENERAL_ARITHMIC_INT_TYPE_MAP()
    } else if (op == TokenKind.EXP) {
        let out = ArrayList<(TypeKind, TypeKind)>()
        out.add((TypeKind.TYPE_INT64, TypeKind.TYPE_INT64))
        out.add((TypeKind.TYPE_IDEAL_INT, TypeKind.TYPE_IDEAL_INT))
        out.add((TypeKind.TYPE_FLOAT64, TypeKind.TYPE_FLOAT64))
        out.add((TypeKind.TYPE_IDEAL_FLOAT, TypeKind.TYPE_IDEAL_FLOAT))
        return out
    } else if (op == TokenKind.EQUAL || op == TokenKind.NOTEQ) {
        let out = GENERAL_RELATION_NUMERIC_TYPE_MAP()
        out.add((TypeKind.TYPE_UNIT, TypeKind.TYPE_BOOLEAN))
        out.add((TypeKind.TYPE_BOOLEAN, TypeKind.TYPE_BOOLEAN))
        return out
    } else if (op == TokenKind.LT || op == TokenKind.LE || op == TokenKind.GT || op == TokenKind.GE) {
        return GENERAL_RELATION_NUMERIC_TYPE_MAP()
    } else if (op == TokenKind.AND || op == TokenKind.OR) {
        let out = ArrayList<(TypeKind, TypeKind)>()
        out.add((TypeKind.TYPE_BOOLEAN, TypeKind.TYPE_BOOLEAN))
        return out
    }
    return EMPTY_KIND_MAP()
}

private func SEMA_EXP_TYPES(leftKind: TypeKind, rightKind: TypeKind): Bool {
    if (leftKind == TypeKind.TYPE_INT64) {
        return rightKind == TypeKind.TYPE_UINT64
    }
    if (leftKind == TypeKind.TYPE_FLOAT64) {
        return rightKind == TypeKind.TYPE_FLOAT64 || rightKind == TypeKind.TYPE_INT64
    }
    return false
}

public func TypeMapToTys(m: ArrayList<(TypeKind, TypeKind)>, fromKey: Bool): TySet {
    let result = TySet()
    for (entry in m) {
        let operandKind = entry[0]
        let retKind = entry[1]
        let _ = result.Add(TypeManager.GetPrimitiveTy(if (fromKey) { operandKind } else { retKind }))
    }
    return result
}

public func GetBinaryOpTypeCandidates(op: TokenKind): ArrayList<(TypeKind, TypeKind)> {
    return BINARY_EXPR_TYPE_MAP(op)
}

public func GetUnaryOpTypeCandidates(op: TokenKind): ArrayList<(TypeKind, TypeKind)> {
    return UNARY_EXPR_TYPE_MAP(op)
}

private func TypeKindInMap(m: ArrayList<(TypeKind, TypeKind)>, kind: TypeKind): Bool {
    for (entry in m) {
        if (entry[0] == kind) {
            return true
        }
    }
    return false
}

public func IsUnaryOperator(op: TokenKind): Bool {
    return !UNARY_EXPR_TYPE_MAP(op).isEmpty()
}

public func IsBinaryOperator(op: TokenKind): Bool {
    return !BINARY_EXPR_TYPE_MAP(op).isEmpty()
}

public func IsBuiltinUnaryExpr(op: TokenKind, ty: Ty): Bool {
    let typeCandidate = UNARY_EXPR_TYPE_MAP(op)
    if (typeCandidate.isEmpty()) {
        return false
    }
    if (Ty.IsTyCorrect(ty) && TypeKindInMap(typeCandidate, ty.kind)) {
        return true
    }
    return false
}

public func IsBuiltinBinaryExpr(op: TokenKind, leftTy: Ty, rightTy: Ty): Bool {
    let tys = ArrayList<Ty>()
    tys.add(leftTy)
    tys.add(rightTy)
    if (!Ty.AreTysCorrect(tys)) {
        return false
    }
    if (op == TokenKind.LSQUARE) {
        return leftTy.kind == TypeKind.TYPE_ARRAY && rightTy.kind == TypeKind.TYPE_INT64
    } else if (op == TokenKind.EXP) {
        return SEMA_EXP_TYPES(leftTy.kind, rightTy.kind)
    }
    let typeCandidate = BINARY_EXPR_TYPE_MAP(op)
    if (typeCandidate.isEmpty()) {
        return false
    }
    if (op == TokenKind.LSHIFT || op == TokenKind.RSHIFT) {
        return TypeKindInMap(typeCandidate, leftTy.kind) && TypeKindInMap(typeCandidate, rightTy.kind)
    } else if (leftTy == rightTy) {
        if (leftTy.kind == TypeKind.TYPE_UNIT && (op == TokenKind.EQUAL || op == TokenKind.NOTEQ)) {
            return true
        }
        if (TypeKindInMap(typeCandidate, leftTy.kind)) {
            return true
        }
    }
    return false
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

public func ModifyTargetOfRef(refExpr: RefExpr, target: Decl, targets: ArrayList<Option<Decl>>): Unit {
    ReplaceTarget(refExpr, Some(target))
    let copiedTargets = ArrayList<Option<Decl>>()
    for (candidate in targets) {
        copiedTargets.add(candidate)
    }
    refExpr.ref.targets.clear()
    for (candidate in copiedTargets) {
        refExpr.ref.targets.add(candidate)
    }
}

public func AddFuncTargetsForMemberAccess<T>(memberAccess: MemberAccess, targets: ArrayList<Option<T>>): Unit where T <: Decl {
    let copiedTargets = ArrayList<Option<T>>()
    for (decl in targets) {
        copiedTargets.add(decl)
    }
    memberAccess.targets.clear()
    for (declOpt in copiedTargets) {
        if (let Some(decl) <- declOpt) {
            if (memberAccess.isPattern || decl.astKind == ASTKind.FUNC_DECL) {
                memberAccess.targets.add(Some((decl as FuncDecl).getOrThrow()))
            }
        }
    }
}

public func AddFuncTargetsForMemberAccess(memberAccess: MemberAccess, targets: ArrayList<Decl>): Unit {
    memberAccess.targets.clear()
    for (decl in targets) {
        if (memberAccess.isPattern || decl.astKind == ASTKind.FUNC_DECL) {
            memberAccess.targets.add(Some((decl as FuncDecl).getOrThrow()))
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
        op == TokenKind.LE || op == TokenKind.LSHIFT || op == TokenKind.LSQUARE ||
        op == TokenKind.LT || op == TokenKind.MOD || op == TokenKind.MUL ||
        op == TokenKind.NOT || op == TokenKind.NOTEQ || op == TokenKind.RSHIFT ||
        op == TokenKind.SUB
}

public func CanSkipDiag(node: Node): Bool {
    return !Ty.IsTyCorrect(node.GetTy())
}

public func IsNode1ScopeVisibleForNode2(node1: Node, node2: Node): Bool {
    let scopeName1 = GetScopeNameWithoutTail(node1.scopeName)
    let scopeName2 = GetScopeNameWithoutTail(node2.scopeName)
    return scopeName2.startsWith(scopeName1)
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

// C++ src/Sema/TypeCheckUtil.h:86-90 TypeCheckUtil::GetInstanationTys.
public func GetInstanationTys(expr: Expr): ArrayList<Ty> {
    if (let Some(refExpr) <- (expr as NameReferenceExpr)) {
        return refExpr.instTys
    }
    return ArrayList<Ty>()
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
    var res = ""
    for (decl in decls) {
        let text = ASTKindName(decl.astKind)
        if (!seen.contains(text)) {
            seen.add(text)
            res += text + " "
        }
    }
    return res
}

public func GetMemberDecl<T>(decl: Decl, identifier: String, paramTys: ArrayList<Ty>,
    typeManager: TypeManager): Option<T> where T <: Decl {
    for (member in decl.GetMemberDecls()) {
        if (member.identifier.Val() != identifier) {
            continue
        }
        var isSuitableDecl = true
        if (let Some(funcMember) <- (member as FuncDecl)) {
            let originalParamTys = (funcMember.GetTy().getOrThrow() as FuncTy).getOrThrow().paramTys
            if (originalParamTys.size != paramTys.size) {
                continue
            }
            var idx: Int64 = 0
            while (idx < paramTys.size) {
                if (originalParamTys[idx].IsObject() && paramTys[idx].IsClass()) {
                    idx++
                    continue
                }
                if (!typeManager.IsSubtype(paramTys[idx], originalParamTys[idx])) {
                    isSuitableDecl = false
                }
                idx++
            }
        }
        if (isSuitableDecl) {
            return member as T
        }
    }
    return None
}

public func FindInitDecl(decl: InheritableDecl, typeManager: TypeManager, valueArgs: ArrayList<Expr>,
    instTys!: ArrayList<Ty> = ArrayList<Ty>()): Option<(FuncDecl, Ty)> {
    let valueParamTys = ArrayList<Ty>()
    for (arg in valueArgs) {
        valueParamTys.add(arg.GetTy().getOrThrow())
    }
    return FindInitDecl(decl, typeManager, valueParamTys, instTys: instTys)
}

public func FindInitDecl(decl: InheritableDecl, typeManager: TypeManager, valueParamTys: ArrayList<Ty>,
    instTys!: ArrayList<Ty> = ArrayList<Ty>()): Option<(FuncDecl, Ty)> {
    let initFuncDecl = GetMemberDecl<FuncDecl>(decl, "init", valueParamTys, typeManager)
    if (let None <- initFuncDecl) {
        return None
    }
    let initDecl = initFuncDecl.getOrThrow()
    return Some((initDecl, typeManager.GetInstantiatedTy(initDecl.GetTy().getOrThrow(),
        GenerateTypeMapping(decl, instTys))))
}

// C++: Sema/TypeCheckUtil.cpp:1075-1096.
public func CreateInitCall(initDeclInfo: (FuncDecl, Ty), valueArgs: ArrayList<Expr>, curFile: File,
    instTys!: ArrayList<Ty> = ArrayList<Ty>()): CallExpr {
    let valueFuncArgs = ArrayList<FuncArg>()
    for (arg in valueArgs) {
        valueFuncArgs.add(CreateFuncArg(arg))
    }
    let call = CallExpr()
    let initDecl = initDeclInfo[0]
    let ty = initDeclInfo[1]
    let refExpr = CreateRefExpr(initDecl)
    refExpr.SetTy(ty)
    refExpr.curFile = curFile
    for (instTy in instTys) {
        refExpr.instTys.add(instTy)
    }
    call.baseFunc = refExpr
    call.curFile = curFile
    call.resolvedFunction = initDecl
    CJC_ASSERT(ty.IsFunc())
    call.SetTy((ty as FuncTy).getOrThrow().retTy)
    for (valueFuncArg in valueFuncArgs) {
        call.args.add(valueFuncArg)
    }
    return call
}

// C++: Sema/TypeCheckUtil.cpp:1098-1106.
public func CreateThrowException(exceptionDecl: ClassDecl, args: ArrayList<Expr>, curFile: File,
    typeManager: TypeManager): ThrowExpr {
    let throwExpr = ThrowExpr()
    throwExpr.expr = CreateInitCall(FindInitDecl(exceptionDecl, typeManager, args).getOrThrow(), args, curFile)
    throwExpr.SetTy(TypeManager.GetNothingTy())
    throwExpr.curFile = curFile
    return throwExpr
}

public func CreateGenericParamDecl(decl: Decl, name: String, typeManager: TypeManager): GenericParamDecl {
    let typeParam = GenericParamDecl()
    typeParam.identifier = SrcIdentifier(name)
    typeParam.SetTy(typeManager.GetGenericsTy(typeParam))
    typeParam.outerDecl = decl
    typeParam.fullPackageName = decl.fullPackageName
    return typeParam
}

public func CreateGenericParamDecl(decl: Decl, typeManager: TypeManager): GenericParamDecl {
    return CreateGenericParamDecl(decl, "T", typeManager)
}

public func GenerateGetTypeForTypeParamIntrinsic(pkg: Package, typeManager: TypeManager): FuncDecl {
    let file = pkg.files[0]
    let retTy = TypeManager.GetCStringTy()
    let funcTy = typeManager.GetFunctionTy(Array<Ty>(), retTy)
    let decl = FuncDecl()
    let funcBody = FuncBody()
    funcBody.paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
    let retType = RefType()
    retType.SetTy(retTy)
    retType.EnableAttr(Attribute.COMPILER_ADD)
    funcBody.retType = retType
    let generic = Generic()
    generic.typeParameters.add(CreateGenericParamDecl(decl, typeManager))
    funcBody.generic = generic
    funcBody.SetTy(funcTy)

    decl.curFile = file
    decl.begin = file.begin
    decl.end = file.begin
    decl.identifier = SrcIdentifier(GET_TYPE_FOR_TYPE_PARAMETER_FUNC_NAME)
    decl.fullPackageName = pkg.fullPackageName
    decl.SetTy(funcTy)
    decl.funcBody = funcBody
    decl.EnableAttr(Attribute.INTRINSIC)
    decl.EnableAttr(Attribute.GENERIC)

    file.decls.add(decl, at: 0)
    return decl
}

public func GenerateIsSubtypeTypesIntrinsic(pkg: Package, typeManager: TypeManager): FuncDecl {
    let file = pkg.files[0]
    let retTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
    let funcTy = typeManager.GetFunctionTy(Array<Ty>(), retTy)
    let decl = FuncDecl()
    let funcBody = FuncBody()
    funcBody.paramLists.add(CreateFuncParamList(ArrayList<FuncParam>()))
    let retType = RefType()
    retType.SetTy(retTy)
    funcBody.retType = retType
    let generic = Generic()
    generic.typeParameters.add(CreateGenericParamDecl(decl, "T1", typeManager))
    generic.typeParameters.add(CreateGenericParamDecl(decl, "T2", typeManager))
    funcBody.generic = generic
    funcBody.SetTy(funcTy)

    AddCurFile(decl, file: file)
    decl.begin = file.begin
    decl.end = file.begin
    decl.identifier = SrcIdentifier(IS_SUBTYPE_TYPES_FUNC_NAME)
    decl.fullPackageName = pkg.fullPackageName
    decl.SetTy(funcTy)
    decl.funcBody = funcBody
    decl.EnableAttr(Attribute.INTRINSIC)
    decl.EnableAttr(Attribute.GENERIC)
    decl.EnableAttr(Attribute.COMPILER_ADD)

    file.decls.add(decl, at: 0)
    return decl
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

public func GetFullInheritedTy(`extend`: ExtendDecl): String {
    var fullType = PosSearchApi.PosToStr(`extend`.begin)
    for (interfaceType in `extend`.inheritedTypes) {
        fullType += interfaceType.GetTy().getOrThrow().String()
    }
    return fullType
}

public func GetFuncTargets(node: Node): ArrayList<Option<FuncDecl>> {
    let out = ArrayList<Option<FuncDecl>>()
    if (let Some(refExpr) <- (node as RefExpr)) {
        for (target in refExpr.ref.targets) {
            if (let Some(decl) <- target) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    out.add(Some(funcDecl))
                }
            }
        }
    } else if (let Some(memberAccess) <- (node as MemberAccess)) {
        for (target in memberAccess.targets) {
            out.add(target)
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

// C2a: substitution-pack + generic-parameter helpers, 1:1 from C++.

// C++ src/Sema/TypeCheckUtil.cpp:723 HasTyVarsToSolve.
public func HasTyVarsToSolve(maps: SubstPack): Bool {
    for ((_, ty) in maps.u2i.entries) {
        let solved = if (let Some(tv) <- (ty as GenericsTy)) {
            maps.inst.Get(tv).isSome()
        } else {
            false
        }
        if (!solved) {
            return true
        }
    }
    return false
}

// C++ src/Sema/TypeCheckUtil.cpp:733 HasUnsolvedTyVars.
public func HasUnsolvedTyVars(subst: TypeSubst, tyVars: ArrayList<GenericsTy>): Bool {
    for (tyVar in tyVars) {
        if (let None <- subst.Get(tyVar)) {
            return true
        }
        for ((_, ty) in subst.entries) {
            if (ty.Contains(tyVar)) {
                return true
            }
        }
    }
    return false
}

// C++ src/Sema/TypeCheckUtil.cpp:743 GetTyVarsToSolve.
public func GetTyVarsToSolve(maps: SubstPack): ArrayList<GenericsTy> {
    let ret = ArrayList<GenericsTy>()
    for ((_, ty) in maps.u2i.entries) {
        if (let Some(tv) <- (ty as GenericsTy)) {
            if (let None <- maps.inst.Get(tv)) {
                ret.add(tv)
            }
        }
    }
    return ret
}

// C++ src/Sema/TypeCheckUtil.cpp:924 LessThanAll.
public func LessThanAll(ty: Ty, tys: TySet, lessThan: (Ty, Ty) -> Bool): Bool {
    for (element in tys.values) {
        if (!lessThan(ty, element)) {
            return false
        }
    }
    return true
}

// C++ src/Sema/TypeCheckUtil.cpp:930 FindSmallestTy.
public func FindSmallestTy(tys: TySet, lessThan: (Ty, Ty) -> Bool): Ty {
    if (tys.values.isEmpty()) {
        return TypeManager.GetNothingTy()
    }
    var bubble: Option<Ty> = None
    for (ty in tys.values) {
        if (let Some(bubbleTy) <- bubble) {
            if (lessThan(bubbleTy, ty)) {
                continue
            } else if (lessThan(ty, bubbleTy)) {
                bubble = Some(ty)
            } else {
                bubble = None
            }
        } else {
            bubble = Some(ty)
        }
    }
    if (let Some(bubbleTy2) <- bubble) {
        if (LessThanAll(bubbleTy2, tys, lessThan)) {
            return bubbleTy2
        }
    }
    return TypeManager.GetInvalidTy()
}

// C++ src/Sema/TypeCheckUtil.cpp:958 TryEnforceCandidate.
public func TryEnforceCandidate(tv: GenericsTy, candidates: ArrayList<Decl>, tyMgr: TypeManager): Unit {
    if (candidates.isEmpty()) {
        return
    }
    let declTys = TySet()
    for (decl in candidates) {
        if (let Some(declTy) <- decl.GetTy()) {
            declTys.Add(declTy)
        }
    }
    let promotion = Promotion(tyMgr)
    let isSuperDecl = { sup: Ty, sub: Ty =>
        !promotion.Promote(sub, sup).values.isEmpty()
    }
    let uniq = FindSmallestTy(declTys, isSuperDecl)
    if (Ty.IsTyCorrect(uniq)) {
        let _ = tyMgr.ConstrainByCtor(tv, uniq)
    } else {
        let tyArgs = ArrayList<GenericsTy>()
        tyMgr.constraints.GetOrCreate(tv).sum.softClear()
        for (declTy2 in declTys.values) {
            let _ = tyMgr.AddSumByCtor(tv, declTy2, tyArgs)
        }
    }
}

// C++ src/Sema/TypeCheckUtil.cpp:993 GetGenericParamsForDecl.
public func GetGenericParamsForDecl(decl: Decl): TySet {
    let ret = TySet()
    if (let Some(generic) <- decl.generic) {
        for (gp in generic.typeParameters) {
            if (let Some(ty) <- gp.GetTy()) {
                ret.Add(ty)
            }
        }
    }
    if (let Some(ed) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- ed.extendedType) {
            if (let Some(target) <- extendedType.GetTarget()) {
                ret.AddAll(GetGenericParamsForDecl(GetRealTarget(target)))
            }
        }
    } else if (let Some(fd) <- (decl as FuncDecl)) {
        if (let Some(funcBody) <- fd.funcBody) {
            if (let Some(generic) <- funcBody.generic) {
                for (gp in generic.typeParameters) {
                    if (let Some(ty) <- gp.GetTy()) {
                        ret.Add(ty)
                    }
                }
            }
        }
    }
    if (let Some(outer) <- decl.outerDecl) {
        ret.AddAll(GetGenericParamsForDecl(outer))
    }
    return ret
}

// C++ src/Sema/TypeCheckUtil.cpp:1017 GetGenericParamsForTy.
public func GetGenericParamsForTy(ty: Ty): TySet {
    if (let Some(id) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
        return GetGenericParamsForDecl(id)
    }
    return TySet()
}

// C++ src/Sema/TypeCheckUtil.cpp:1025 GetGenericParamsForCall.
public func GetGenericParamsForCall(ce: CallExpr, fd: FuncDecl): TySet {
    let ret = GetGenericParamsForDecl(fd)
    var base: Option<Expr> = ce.baseFunc
    while (let Some(b) <- base) {
        if (let Some(bty) <- b.GetTy()) {
            ret.AddAll(GetGenericParamsForTy(bty))
        }
        if (let Some(ma) <- (b as MemberAccess)) {
            if (let Some(target) <- ma.target) {
                ret.AddAll(GetGenericParamsForDecl(target))
            }
            base = ma.baseExpr
        } else if (let Some(ce0) <- (b as CallExpr)) {
            base = ce0.baseFunc
        } else if (let Some(re) <- (b as RefExpr)) {
            if (let Some(target) <- re.ref.target) {
                ret.AddAll(GetGenericParamsForDecl(target))
            }
            base = None
        } else {
            base = None
        }
    }
    return ret
}
