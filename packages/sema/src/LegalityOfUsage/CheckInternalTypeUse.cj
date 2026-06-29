package cangjie_compiler::sema.LegalityOfUsage

import std.collection.*
import cangjie_compiler::ast.*

public class AccessLevelViolation {
    public var useSite: Node
    public var limitedDecl: Decl
    public var isHint: Bool

    public init(useSite: Node, limitedDecl: Decl, isHint!: Bool = false) {
        this.useSite = useSite
        this.limitedDecl = limitedDecl
        this.isHint = isHint
    }
}

private func AccessRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

public func IsCompatibleAccessLevel(srcLevel: AccessLevel, targetLevel: AccessLevel): Bool {
    return AccessRank(srcLevel) <= AccessRank(targetLevel)
}

private func DeclOfNominalTy(typeValue: Ty): Option<Decl> {
    if (let Some(classTy) <- (typeValue as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return decl
        }
    }
    if (let Some(interfaceTy) <- (typeValue as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl
        }
    }
    if (let Some(structTy) <- (typeValue as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return decl
        }
    }
    if (let Some(enumTy) <- (typeValue as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return decl
        }
    }
    return None
}

private func FindInaccessibleTypeInArgs(typeValue: Ty, srcLevel: AccessLevel): Option<Decl> {
    for (arg in typeValue.typeArgs) {
        if (Ty.IsTyCorrect(arg)) {
            if (let Some(decl) <- FindInaccessibleType(arg, srcLevel)) {
                return decl
            }
        }
    }
    return None
}

public func FindInaccessibleType(typeValue: Option<Ty>, srcLevel: AccessLevel): Option<Decl> {
    if (let Some(realTy) <- typeValue) {
        return FindInaccessibleType(realTy, srcLevel)
    }
    return None
}

public func FindInaccessibleType(typeValue: Ty, srcLevel: AccessLevel): Option<Decl> {
    if (!Ty.IsTyCorrect(typeValue)) {
        return None
    }
    if (let Some(decl) <- FindInaccessibleTypeInArgs(typeValue, srcLevel)) {
        return decl
    }
    if (typeValue.IsNominal()) {
        if (let Some(decl) <- DeclOfNominalTy(typeValue)) {
            if (!IsCompatibleAccessLevel(srcLevel, GetAccessLevel(decl))) {
                return decl
            }
        }
    }
    return None
}

private func AddViolation(out: ArrayList<AccessLevelViolation>, useSite: Node, limitedDecl: Decl,
    isHint!: Bool = false): Unit {
    out.add(AccessLevelViolation(useSite, limitedDecl, isHint: isHint))
}

public func CollectGenericTyAccessibility(decl: Decl, out: ArrayList<AccessLevelViolation>): Unit {
    if (let Some(generic) <- decl.GetGeneric()) {
        let declLevel = GetAccessLevel(decl)
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                if (let Some(upperTy) <- upperBound.GetTy()) {
                    if (let Some(limitedDecl) <- FindInaccessibleType(upperTy, declLevel)) {
                        AddViolation(out, upperBound, limitedDecl)
                    }
                }
            }
        }
    }
}

private func CollectPatternVarDecls(pattern: Pattern, out: ArrayList<VarDecl>): Unit {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        if (let Some(varDecl) <- varPattern.varDecl) {
            out.add(varDecl)
        }
        return
    }
    if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
        for (child in tuplePattern.patterns) {
            CollectPatternVarDecls(child, out)
        }
    } else if (let Some(typePattern) <- (pattern as TypePattern)) {
        if (let Some(child) <- typePattern.pattern) {
            CollectPatternVarDecls(child, out)
        }
        if (let Some(desugared) <- typePattern.desugarVarPattern) {
            CollectPatternVarDecls(desugared, out)
        }
    } else if (let Some(enumPattern) <- (pattern as EnumPattern)) {
        for (child in enumPattern.patterns) {
            CollectPatternVarDecls(child, out)
        }
    } else if (let Some(varOrEnumPattern) <- (pattern as VarOrEnumPattern)) {
        if (let Some(child) <- varOrEnumPattern.pattern) {
            CollectPatternVarDecls(child, out)
        }
    } else if (let Some(exceptTypePattern) <- (pattern as ExceptTypePattern)) {
        if (let Some(child) <- exceptTypePattern.pattern) {
            CollectPatternVarDecls(child, out)
        }
    } else if (let Some(commandTypePattern) <- (pattern as CommandTypePattern)) {
        if (let Some(child) <- commandTypePattern.pattern) {
            CollectPatternVarDecls(child, out)
        }
    }
}

public func CheckPatternVarAccessLevelValidity(pattern: Pattern): ArrayList<AccessLevelViolation> {
    let out = ArrayList<AccessLevelViolation>()
    let vars = ArrayList<VarDecl>()
    CollectPatternVarDecls(pattern, vars)
    for (varDecl in vars) {
        if (let Some(limitedDecl) <- FindInaccessibleType(varDecl.GetTy(), GetAccessLevel(varDecl))) {
            AddViolation(out, varDecl, limitedDecl)
        }
    }
    return out
}

private func AppendAll(out: ArrayList<AccessLevelViolation>, values: ArrayList<AccessLevelViolation>): Unit {
    for (value in values) {
        out.add(value)
    }
}

private func CheckFuncParamList(fd: FuncDecl, params: FuncParamList, out: ArrayList<AccessLevelViolation>): Unit {
    if (fd.TestAttr(Attribute.FROM_COMMON_PART)) {
        return
    }
    for (param in params.params) {
        if (let Some(limitedDecl) <- FindInaccessibleType(param.GetTy(), GetAccessLevel(fd))) {
            if (let Some(typeNode) <- param.typeNode) {
                AddViolation(out, typeNode, limitedDecl)
            } else {
                AddViolation(out, param, limitedDecl)
            }
        }
    }
}

public func CheckFuncAccessLevelValidity(fd: FuncDecl): ArrayList<AccessLevelViolation> {
    let out = ArrayList<AccessLevelViolation>()
    if (let Some(body) <- fd.funcBody) {
        if (let Some(retType) <- body.retType) {
            if (let Some(limitedDecl) <- FindInaccessibleType(retType.GetTy(), GetAccessLevel(fd))) {
                if (retType.TestAttr(Attribute.COMPILER_ADD)) {
                    AddViolation(out, fd, limitedDecl, isHint: true)
                } else {
                    AddViolation(out, retType, limitedDecl)
                }
            }
        }
        if (!body.paramLists.isEmpty()) {
            CheckFuncParamList(fd, body.paramLists[0], out)
        }
    }
    CollectGenericTyAccessibility(fd, out)
    return out
}

public func CheckNominalDeclAccessLevelValidity(id: InheritableDecl): ArrayList<AccessLevelViolation> {
    let out = ArrayList<AccessLevelViolation>()
    if (id.astKind == ASTKind.EXTEND_DECL) {
        return out
    }
    CollectGenericTyAccessibility(id, out)
    for (member in id.GetMemberDeclPtrs()) {
        if (!member.TestAttr(Attribute.PRIVATE) && !member.TestAttr(Attribute.FROM_COMMON_PART)) {
            AppendAll(out, CheckNonPrivateDeclAccessLevelValidity(member))
        }
    }
    return out
}

public func CheckNonPrivateDeclAccessLevelValidity(decl: Decl): ArrayList<AccessLevelViolation> {
    let out = ArrayList<AccessLevelViolation>()
    if (!Ty.IsTyCorrect(decl.GetTy())) {
        return out
    }
    if (let Some(id) <- (decl as InheritableDecl)) {
        return CheckNominalDeclAccessLevelValidity(id)
    }
    if (let Some(fd) <- (decl as FuncDecl)) {
        return CheckFuncAccessLevelValidity(fd)
    }
    if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            return CheckPatternVarAccessLevelValidity(pattern)
        }
        return out
    }
    if (let Some(tad) <- (decl as TypeAliasDecl)) {
        if (let Some(typeNode) <- tad.typeNode) {
            if (let Some(limitedDecl) <- FindInaccessibleType(typeNode.GetTy(), GetAccessLevel(tad))) {
                AddViolation(out, typeNode, limitedDecl)
            }
        }
        CollectGenericTyAccessibility(tad, out)
        return out
    }
    if (let Some(pd) <- (decl as PropDecl)) {
        if (let Some(limitedDecl) <- FindInaccessibleType(pd.GetTy(), GetAccessLevel(pd))) {
            if (let Some(typeNode) <- pd.typeNode) {
                AddViolation(out, typeNode, limitedDecl)
            } else {
                AddViolation(out, pd, limitedDecl)
            }
        }
        return out
    }
    if (let Some(vd) <- (decl as VarDecl)) {
        if (let Some(limitedDecl) <- FindInaccessibleType(vd.GetTy(), GetAccessLevel(vd))) {
            if (let Some(typeNode) <- vd.typeNode) {
                AddViolation(out, typeNode, limitedDecl)
            } else {
                AddViolation(out, vd, limitedDecl)
            }
        }
    }
    return out
}

public func CheckAccessLevelValidity(pkg: Package): ArrayList<AccessLevelViolation> {
    let out = ArrayList<AccessLevelViolation>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.TestAttr(Attribute.PRIVATE) || decl.TestAttr(Attribute.FROM_COMMON_PART)) {
                continue
            }
            AppendAll(out, CheckNonPrivateDeclAccessLevelValidity(decl))
        }
    }
    return out
}
