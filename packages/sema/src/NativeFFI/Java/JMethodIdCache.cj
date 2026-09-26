package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateIsPtrNullCheckCall, InteropLibBridge, WithinFile}

public class JMethodIdCache {
    private static var nextId: Int64 = 0
    private let importManager: SemaImportManager
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let cache: HashMap<JavaMemberSignature, VarDecl> = HashMap<JavaMemberSignature, VarDecl>()

    public init(importManager: SemaImportManager, typeManager: TypeManager, ilib: InteropLibBridge) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.ilib = ilib
    }

    public func Clear(): Unit {
        cache.clear()
    }

    private func GetNewAccessorName(method: JavaMemberSignature): String {
        let id = JMethodIdCache.nextId
        JMethodIdCache.nextId = id + 1
        return "jmethod$" + method.UnqualifiedTypeName() + "$$" + method.name + "${id}"
    }

    private func PackageName(curFile: File): String {
        var name = curFile.GetFullPackageName()
        if (name.isEmpty()) {
            if (let Some(pkg) <- curFile.curPackage) {
                name = pkg.fullPackageName
            }
        }
        return name
    }

    private func GetOrPut(ctx: AfterTypeCheckContext, method: JavaMemberSignature, curFile: File): VarDecl {
        if (let Some(found) <- cache.get(method)) {
            return found
        }
        let idTy = ilib.GetJniJmethodIdTy()
        let nullPtr = PointerExpr()
        nullPtr.SetTy(idTy)
        nullPtr.curFile = Some(curFile)
        let varDecl = CreateVarDecl(GetNewAccessorName(method), Some(nullPtr), None)
        varDecl.EnableAttr(Attribute.INTERNAL)
        varDecl.EnableAttr(Attribute.GLOBAL)
        varDecl.EnableAttr(Attribute.INITIALIZED)
        varDecl.EnableAttr(Attribute.NO_REFLECT_INFO)
        varDecl.isVar = true
        varDecl.curFile = Some(curFile)
        varDecl.fullPackageName = PackageName(curFile)
        varDecl.SetTy(idTy)
        cache[method] = varDecl
        ctx.AddGeneratedDecl(varDecl)
        return varDecl
    }

    public func CreateJMethodIdAccess(ctx: AfterTypeCheckContext, method: JavaMemberSignature, jclass: Expr,
        envPtr: Expr): Option<Expr> {
        if (let None <- envPtr.curFile) {
            return None
        }
        let curFile = envPtr.curFile.getOrThrow()
        let methodVar = GetOrPut(ctx, method, curFile)
        let idTy = ilib.GetJniJmethodIdTy()
        let loaded = ilib.CreateGetMethodIdCall((ASTCloner.Clone(envPtr) as Expr).getOrThrow(),
            (ASTCloner.Clone(jclass) as Expr).getOrThrow(), method.name, method.signature, method.isStatic)
        if (let None <- loaded) {
            return None
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let ifNull = ArrayList<Node>()
        let assign = CreateAssignExpr(WithinFile<RefExpr>(CreateRefExpr(methodVar), curFile),
            (loaded.getOrThrow() as Expr).getOrThrow(), Some(unitTy))
        assign.curFile = Some(curFile)
        ifNull.add(assign)
        ifNull.add(WithinFile<RefExpr>(CreateRefExpr(methodVar), curFile))
        let ifNotNull = ArrayList<Node>()
        ifNotNull.add(WithinFile<RefExpr>(CreateRefExpr(methodVar), curFile))
        let cond = CreateIsPtrNullCheckCall(importManager, typeManager,
            WithinFile<RefExpr>(CreateRefExpr(methodVar), curFile))
        let ifExpr = CreateIfExpr(cond, CreateBlock(ifNull, Some(idTy)),
            Some(CreateBlock(ifNotNull, Some(idTy))), Some(idTy))
        ifExpr.curFile = Some(curFile)
        return Some(ifExpr)
    }
}
