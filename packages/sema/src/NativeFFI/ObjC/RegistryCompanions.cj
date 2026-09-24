package cjcj::sema.NativeFFI.ObjC

import std.collection.HashMap
import cjcj::ast.*
import cjcj::utils.CJC_NULLPTR_CHECK

// Upstream a51ced71, AfterTypeCheck/Interop/PropagateBrokenToSubtypes.cpp:23-72.
private func IsObjCClass(decl: ClassDecl): Bool {
    return IsObjCImpl(decl) || IsObjCMirror(decl)
}

private func HasBrokenObjCSuperClass(decl: ClassDecl): Bool {
    var parent = decl.GetSuperClassDecl()
    while (let Some(value) <- parent) {
        if (!IsObjCClass(value)) {
            break
        }
        if (value.TestAttr(Attribute.IS_BROKEN)) {
            return true
        }
        parent = value.GetSuperClassDecl()
    }
    return false
}

private func MarkIfParentIsBroken(decl: ClassDecl): Unit {
    if (decl.TestAttr(Attribute.IS_BROKEN)) {
        return
    }
    if (HasBrokenObjCSuperClass(decl)) {
        decl.EnableAttr(Attribute.IS_BROKEN)
    }
}

public class PropagateBrokenToSubtypes <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (mirror in ctx.mirrors) {
            if (let Some(cd) <- (mirror as ClassDecl)) {
                MarkIfParentIsBroken(cd)
            }
        }
        for (impl in ctx.impls) {
            MarkIfParentIsBroken(impl)
        }
    }
}

// Upstream a51ced71, AfterTypeCheck/Interop/MapImplToRegCompanion.cpp:26-56.
private func GetRegistryCompanionDecl(regCompByName: HashMap<String, ClassDecl>,
    impl: ClassDecl): Option<ClassDecl> {
    return regCompByName.get(NameGenerator.GenerateRegistryCompanionName(impl))
}

public class MapImplToRegCompanion <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        let regCompanionsByName = HashMap<String, ClassDecl>()
        for (regComp in ctx.regCompanions) {
            regCompanionsByName[regComp.identifier.Val()] = regComp
        }
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let regCompanion = GetRegistryCompanionDecl(regCompanionsByName, impl)
            CJC_NULLPTR_CHECK(regCompanion)
            ctx.implToRegCompanion[impl] = regCompanion.getOrThrow()
        }
    }
}

// Upstream a51ced71, AfterTypeCheck/Interop/RestoreRegCompanionsTypeHierarchy.cpp:22-61.
private func ReplaceSuperClassDecl(target: ClassDecl, newSuperClass: ClassDecl): Unit {
    for (i in 0..target.inheritedTypes.size) {
        if (let Some(ty) <- target.inheritedTypes[i].GetTy()) {
            if (ty.kind == TypeKind.TYPE_CLASS) {
                target.inheritedTypes[i] = CreateRefType(newSuperClass)
                return
            }
        }
    }
}

public class RestoreRegCompanionsTypeHierarchy <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let implParent = impl.GetSuperClassDecl()
            if (implParent.isNone() || !IsObjCImpl(implParent.getOrThrow())) {
                continue
            }
            let parentRegCompanion = ctx.GetRegCompanion(implParent.getOrThrow())
            let regCompanion = ctx.GetRegCompanion(impl)
            if (parentRegCompanion.isNone() || regCompanion.isNone()) {
                continue
            }
            ReplaceSuperClassDecl(regCompanion.getOrThrow(), parentRegCompanion.getOrThrow())
            parentRegCompanion.getOrThrow().subDecls.add(regCompanion.getOrThrow())
        }
    }
}

// Upstream a51ced71, AfterTypeCheck/Interop/InsertObjCImplRegCompanionField.cpp:23-36.
public class InsertObjCImplRegCompanionField <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (impl in ctx.impls) {
            if (impl.TestAttr(Attribute.IS_BROKEN)) {
                continue
            }
            let regCompanion = ctx.implToRegCompanion.get(impl).getOrThrow()
            let field = CreateVarDecl("")
            ctx.astTransformer.TransformToObjCImplRegCompanionField(field, regCompanion)
            ctx.astInserter.InsertInto(impl, field)
        }
    }
}

// Upstream a51ced71, AfterTypeCheck/Interop/RestoreCurFile.cpp:20-25.
public class RestoreCurFile <: Handler<InteropContext> {
    public func HandleImpl(ctx: InteropContext): Unit {
        for (file in ctx.pkg.files) { AddCurFile(file, file: Some(file)) }
    }
}
