package cangjie_compiler::sema.Desugar.AfterTypeCheck

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func declOfTy(ty: Ty): Option<Decl> {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(decl) <- classTy.declPtr) {
            return decl
        }
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(decl) <- interfaceTy.declPtr) {
            return decl
        }
    }
    if (let Some(structTy) <- (ty as StructTy)) {
        if (let Some(decl) <- structTy.declPtr) {
            return decl
        }
    }
    if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let Some(decl) <- enumTy.declPtr) {
            return decl
        }
    }
    if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
        if (let Some(decl) <- aliasTy.declPtr) {
            return decl
        }
    }
    return None
}

private func isFinalRuntimeTy(ty: Ty): Bool {
    if (ty.IsStruct() || ty.IsEnum() || ty.IsPointer() || ty.IsCString() || ty.IsPrimitive() ||
        ty.IsArray() || ty.kind == TypeKind.TYPE_VARRAY) {
        return true
    }
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(classDecl) <- classTy.declPtr) {
            return !classDecl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)
        }
    }
    return false
}

public func IsNeedRuntimeCheck(typeManager: TypeManager, srcTy: Ty, targetTy: Ty): Bool {
    if (isFinalRuntimeTy(srcTy) && isFinalRuntimeTy(targetTy)) {
        if (let Some(srcDecl) <- declOfTy(srcTy)) {
            if (let Some(targetDecl) <- declOfTy(targetTy)) {
                return refEq(srcDecl, targetDecl)
            }
            return false
        }
        if (let Some(_) <- declOfTy(targetTy)) {
            return false
        }
    }
    return (srcTy.IsClassLike() && targetTy.IsClassLike()) || srcTy.IsGeneric() || targetTy.IsGeneric() ||
        srcTy.HasGeneric() || targetTy.HasGeneric() ||
        typeManager.IsSubtype(srcTy, targetTy, implicitBoxed: true, allowOptionBox: false) ||
        typeManager.IsSubtype(targetTy, srcTy, implicitBoxed: true, allowOptionBox: false)
}

public func CreateRuntimePreparedTypePattern(typeManager: TypeManager, pattern: Pattern, typeNode: Type,
    selector: Expr): TypePattern {
    let typePattern = CreateTypePattern(pattern, typeNode, selector)
    if (let Some(selectorTy) <- selector.GetTy()) {
        if (let Some(patternTy) <- typePattern.GetTy()) {
            typePattern.matchBeforeRuntime =
                typeManager.IsSubtype(selectorTy, patternTy, implicitBoxed: true, allowOptionBox: false)
            typePattern.needRuntimeTypeCheck =
                !typePattern.matchBeforeRuntime && IsNeedRuntimeCheck(typeManager, selectorTy, patternTy)
        } else {
            typePattern.matchBeforeRuntime = false
            typePattern.needRuntimeTypeCheck = false
        }
    } else {
        typePattern.matchBeforeRuntime = false
        typePattern.needRuntimeTypeCheck = false
    }
    return typePattern
}
