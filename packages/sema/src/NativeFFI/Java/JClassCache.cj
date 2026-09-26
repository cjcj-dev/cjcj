package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateIsPtrNullCheckCall, InteropLibBridge, WithinFile}

public class JClassCache {
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

    private func GetNewAccessorName(classTypeJniName: String): String {
        let id = JClassCache.nextId
        JClassCache.nextId = id + 1
        return "jclass$" + UnqualifiedJniTypeName(classTypeJniName) + "${id}"
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

    private func GetOrPut(ctx: AfterTypeCheckContext, classTypeJniName: String, curFile: File): VarDecl {
        if (let Some(found) <- cache.get(classTypeJniName)) {
            return found
        }
        let jclassTy = ilib.GetJniJClassTy()
        let nullPtr = PointerExpr()
        nullPtr.SetTy(jclassTy)
        nullPtr.curFile = Some(curFile)
        let varDecl = CreateVarDecl(GetNewAccessorName(classTypeJniName), Some(nullPtr), None)
        varDecl.EnableAttr(Attribute.INTERNAL)
        varDecl.EnableAttr(Attribute.GLOBAL)
        varDecl.EnableAttr(Attribute.INITIALIZED)
        varDecl.EnableAttr(Attribute.NO_REFLECT_INFO)
        varDecl.isVar = true
        varDecl.curFile = Some(curFile)
        varDecl.fullPackageName = PackageName(curFile)
        varDecl.SetTy(jclassTy)
        cache[classTypeJniName] = varDecl
        ctx.AddGeneratedDecl(varDecl)
        return varDecl
    }

    public func CreateJClassAccess(ctx: AfterTypeCheckContext, classTypeJniName: String, envPtr: Expr): Option<Expr> {
        if (let None <- envPtr.curFile) {
            return None
        }
        let curFile = envPtr.curFile.getOrThrow()
        let classVar = GetOrPut(ctx, classTypeJniName, curFile)
        let jclassTy = ilib.GetJniJClassTy()
        let getClass = ilib.CreateGetClassCall(classTypeJniName, (ASTCloner.Clone(envPtr) as Expr).getOrThrow(), curFile)
        if (let None <- getClass) {
            return None
        }
        let swapped = ilib.CreateSwapLocalWithGlobalRefCall((ASTCloner.Clone(envPtr) as Expr).getOrThrow(),
            getClass.getOrThrow())
        if (let None <- swapped) {
            return None
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let ifNull = ArrayList<Node>()
        let assign = CreateAssignExpr(WithinFile<RefExpr>(CreateRefExpr(classVar), curFile),
            (swapped.getOrThrow() as Expr).getOrThrow(), Some(unitTy))
        assign.curFile = Some(curFile)
        ifNull.add(assign)
        ifNull.add(WithinFile<RefExpr>(CreateRefExpr(classVar), curFile))
        let ifNotNull = ArrayList<Node>()
        ifNotNull.add(WithinFile<RefExpr>(CreateRefExpr(classVar), curFile))
        let cond = CreateIsPtrNullCheckCall(importManager, typeManager,
            WithinFile<RefExpr>(CreateRefExpr(classVar), curFile))
        let ifExpr = CreateIfExpr(cond, CreateBlock(ifNull, Some(jclassTy)),
            Some(CreateBlock(ifNotNull, Some(jclassTy))), Some(jclassTy))
        ifExpr.curFile = Some(curFile)
        return Some(ifExpr)
    }
}
