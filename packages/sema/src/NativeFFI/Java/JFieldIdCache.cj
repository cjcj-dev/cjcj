package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateIsPtrNullCheckCall, InteropLibBridge, WithinFile}

public class JFieldIdCache {
    private static var nextId: Int64 = 0
    private let importManager: SemaImportManager
    private let typeManager: TypeManager
    private let ilib: InteropLibBridge
    private let cache: HashMap<String, VarDecl> = HashMap<String, VarDecl>()

    public init(importManager: SemaImportManager, typeManager: TypeManager, ilib: InteropLibBridge) {
        this.importManager = importManager
        this.typeManager = typeManager
        this.ilib = ilib
    }

    public func Clear(): Unit {
        cache.clear()
    }

    private func GetNewAccessorName(field: JavaMemberSignature): String {
        let id = JFieldIdCache.nextId
        JFieldIdCache.nextId = id + 1
        return "jfield$" + field.UnqualifiedTypeName() + "$$" + field.name + "${id}"
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

    private func GetOrPut(ctx: AfterTypeCheckContext, field: JavaMemberSignature, curFile: File): VarDecl {
        let key = field.CacheKey()
        if (let Some(found) <- cache.get(key)) {
            return found
        }
        let idTy = ilib.GetJniJfieldIdTy()
        let nullPtr = PointerExpr()
        nullPtr.SetTy(idTy)
        nullPtr.curFile = Some(curFile)
        let varDecl = CreateVarDecl(GetNewAccessorName(field), Some(nullPtr), None)
        varDecl.EnableAttr(Attribute.INTERNAL)
        varDecl.EnableAttr(Attribute.GLOBAL)
        varDecl.EnableAttr(Attribute.INITIALIZED)
        varDecl.EnableAttr(Attribute.NO_REFLECT_INFO)
        varDecl.isVar = true
        varDecl.curFile = Some(curFile)
        varDecl.fullPackageName = PackageName(curFile)
        varDecl.SetTy(idTy)
        cache[key] = varDecl
        ctx.AddGeneratedDecl(varDecl)
        return varDecl
    }

    public func CreateJFieldIdAccess(ctx: AfterTypeCheckContext, field: JavaMemberSignature, jclass: Expr,
        envPtr: Expr): Option<Expr> {
        if (let None <- envPtr.curFile) {
            return None
        }
        let curFile = envPtr.curFile.getOrThrow()
        let fieldVar = GetOrPut(ctx, field, curFile)
        let idTy = ilib.GetJniJfieldIdTy()
        let loaded = ilib.CreateGetFieldIdCall((ASTCloner.Clone(envPtr) as Expr).getOrThrow(),
            (ASTCloner.Clone(jclass) as Expr).getOrThrow(), field.name, field.signature, field.isStatic)
        if (let None <- loaded) {
            return None
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let ifNull = ArrayList<Node>()
        let assign = CreateAssignExpr(WithinFile<RefExpr>(CreateRefExpr(fieldVar), curFile),
            (loaded.getOrThrow() as Expr).getOrThrow(), Some(unitTy))
        assign.curFile = Some(curFile)
        ifNull.add(assign)
        ifNull.add(WithinFile<RefExpr>(CreateRefExpr(fieldVar), curFile))
        let ifNotNull = ArrayList<Node>()
        ifNotNull.add(WithinFile<RefExpr>(CreateRefExpr(fieldVar), curFile))
        let cond = CreateIsPtrNullCheckCall(importManager, typeManager,
            WithinFile<RefExpr>(CreateRefExpr(fieldVar), curFile))
        let ifExpr = CreateIfExpr(cond, CreateBlock(ifNull, Some(idTy)),
            Some(CreateBlock(ifNotNull, Some(idTy))), Some(idTy))
        ifExpr.curFile = Some(curFile)
        return Some(ifExpr)
    }
}
