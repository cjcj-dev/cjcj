package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.*
import cjcj::mangle.ASTMangler
import cjcj::utils.CJC_ASSERT

public func PrintDecl(decl: Decl): String {
    let out = StringBuilder()
    if (!decl.identifier.Empty()) {
        out.append(decl.identifier.Val() + " ")
    }
    out.append(decl.rawMangleName + " ")
    if (let Some(file) <- decl.curFile) {
        out.append(file.fileName + " ")
    }
    if (!decl.begin.IsZero()) {
        out.append(decl.begin.line.toString())
    }
    return out.toString()
}

public func IsVirtual(decl: Decl): Bool {
    if (IsImported(decl)) {
        return decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT)
    }
    if (let None <- decl.outerDecl) {
        return false
    }
    let outerDecl = decl.outerDecl.getOrThrow()
    if (outerDecl.astKind != ASTKind.CLASS_DECL && outerDecl.astKind != ASTKind.INTERFACE_DECL) {
        return false
    }
    if (outerDecl.astKind == ASTKind.INTERFACE_DECL && !decl.TestAttr(Attribute.STATIC)) {
        return true
    }
    if (decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR)) {
        return false
    }
    if (outerDecl.TestAttr(Attribute.ABSTRACT) && !decl.TestAttr(Attribute.STATIC)) {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(funcBody) <- funcDecl.funcBody) {
                if (let None <- funcBody.body) {
                    return true
                }
            }
        }
        if (let Some(propDecl) <- (decl as PropDecl)) {
            if (propDecl.getters.isEmpty() && propDecl.setters.isEmpty()) {
                return true
            }
        }
    }
    return decl.TestAttr(Attribute.OPEN) || decl.TestAttr(Attribute.ABSTRACT)
}

public func IsImported(decl: Decl): Bool {
    return decl.TestAttr(Attribute.IMPORTED)
}

public func IsInstance(decl: Decl): Bool {
    return !decl.TestAttr(Attribute.STATIC) && !decl.TestAttr(Attribute.CONSTRUCTOR)
}

public func IsTyped(decl: Decl): Bool {
    if (decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
        return true
    }
    if (let Some(patternDecl) <- (decl as VarWithPatternDecl)) {
        return patternDecl.typeNode.isSome() || IsImported(patternDecl)
    }
    if (let Some(varDecl) <- (decl as VarDecl)) {
        if (let Some(outerDecl) <- varDecl.outerDecl) {
            if (let Some(patternDecl) <- (outerDecl as VarWithPatternDecl)) {
                return IsTyped(patternDecl)
            }
        }
        return varDecl.typeNode.isSome() || IsImported(varDecl)
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        let funcBody = funcDecl.funcBody.getOrThrow()
        return funcBody.retType.isSome() || funcDecl.isGetter || funcDecl.isSetter ||
            funcDecl.TestAttr(Attribute.CONSTRUCTOR) || funcDecl.IsFinalizer()
    }
    return true
}

public func IsUntyped(decl: Decl): Bool {
    return !IsTyped(decl)
}

public func IsEnumConstructor(decl: Decl): Bool {
    return decl.TestAttr(Attribute.ENUM_CONSTRUCTOR)
}

public func GetMembers(decl: Decl): ArrayList<Decl> {
    if (let Some(enumDecl) <- (decl as EnumDecl)) {
        let result = ArrayList<Decl>()
        for (member in enumDecl.members) {
            result.add(member)
        }
        return result
    }
    if (let Some(propDecl) <- (decl as PropDecl)) {
        let result = ArrayList<Decl>()
        for (getter in propDecl.getters) {
            result.add(getter)
        }
        for (setter in propDecl.setters) {
            result.add(setter)
        }
        return result
    }
    if (let Some(varWithPatternDecl) <- (decl as VarWithPatternDecl)) {
        let result = ArrayList<Decl>()
        Walker(varWithPatternDecl.irrefutablePattern.getOrThrow(), visitPre: { node: Node =>
            if (let Some(varDecl) <- (node as VarDecl)) {
                result.add(varDecl)
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        return result
    }
    return decl.GetMemberDeclPtrs()
}

public func IsOOEAffectedDecl(decl: Decl): Bool {
    CJC_ASSERT(!decl.TestAttr(Attribute.IMPORTED) || decl.TestAttr(Attribute.FROM_COMMON_PART))
    if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
        return varDecl.initializer.isSome()
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return funcDecl.funcBody.getOrThrow().body.isSome()
    }
    if (decl.astKind == ASTKind.MACRO_DECL || decl.astKind == ASTKind.MAIN_DECL ||
        decl.astKind == ASTKind.PRIMARY_CTOR_DECL) {
        return true
    }
    return false
}

// C++ Sema/IncrementalUtils.cpp:161-171. This leaf dependency is shared here because
// cjcj::sema already depends on cjcj::incremental_compilation.
public func GetTypeRawMangleName(ty: Ty): String {
    if (let Some(boxDecl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        return boxDecl.rawMangleName
    }
    CJC_ASSERT(ty.IsBuiltin())
    return ASTMangler.MangleBuiltinType(Ty.KindName(ty.kind))
}
