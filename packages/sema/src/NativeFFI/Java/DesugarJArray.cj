package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{AreParamTypeKindsValid, CreateThisCall, CreateThrowExceptionCall, CreateType,
    GetJavaMirrorWrappingConstructor, GetStringDecl, InteropLibBridge, IsJArray, WithinFile, WrapReturningLambdaCall}

public class DesugarJArray {
    private let typeManager: TypeManager
    private let importManager: SemaImportManager
    private let ilib: InteropLibBridge

    public init(typeManager: TypeManager, importManager: SemaImportManager, ilib: InteropLibBridge) {
        this.typeManager = typeManager
        this.importManager = importManager
        this.ilib = ilib
    }

    private func InFilePackage(node: Node, file: File): Bool {
        if (let None <- file.curPackage) {
            return true
        }
        if (let None <- node.curFile) {
            return true
        }
        let nodeFile = node.curFile.getOrThrow()
        if (let None <- nodeFile.curPackage) {
            return true
        }
        return nodeFile.curPackage.getOrThrow().fullPackageName == file.curPackage.getOrThrow().fullPackageName
    }

    private func IsJArrayConstructor(constr: FuncDecl): Bool {
        if (!constr.TestAttr(Attribute.CONSTRUCTOR)) {
            return false
        }
        if (let Some(outer) <- constr.outerDecl) {
            return IsJArray(outer)
        }
        return false
    }

    private func IsSizeConstructor(constr: FuncDecl): Bool {
        let kinds = ArrayList<TypeKind>()
        kinds.add(TypeKind.TYPE_INT32)
        return IsJArrayConstructor(constr) && AreParamTypeKindsValid(constr, kinds)
    }

    private func IsSizeJNITypeConstructor(constr: FuncDecl): Bool {
        if (!IsJArrayConstructor(constr) || !constr.TestAttr(Attribute.COMPILER_ADD)) {
            return false
        }
        let kinds = ArrayList<TypeKind>()
        kinds.add(TypeKind.TYPE_INT32)
        kinds.add(TypeKind.TYPE_STRUCT)
        if (!AreParamTypeKindsValid(constr, kinds)) {
            return false
        }
        let strTy = GetStringDecl(importManager).GetTy().getOrThrow()
        let params = constr.funcBody.getOrThrow().paramLists[0].params
        if (let Some(ty) <- params[1].GetTy()) {
            return ty == strTy
        }
        return false
    }

    private func FindSizeJNITypeConstructor(jarray: ClassDecl): Option<FuncDecl> {
        for (member in jarray.GetMemberDecls()) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (IsSizeJNITypeConstructor(fd)) {
                    return Some(fd)
                }
            }
        }
        return None
    }

    private func InsertJniTypeParamIntoConstructor(constr: FuncDecl): Unit {
        let strTy = GetStringDecl(importManager).GetTy().getOrThrow()
        let jniTypeParam = CreateFuncParam("$jniType", Some(CreateType(strTy)), None, Some(strTy))
        constr.funcBody.getOrThrow().paramLists[0].params.add(jniTypeParam)
        if (let Some(declTy) <- constr.GetTy()) {
            if (let Some(fty) <- (declTy as FuncTy)) {
            let paramTys = ArrayList<Ty>()
            for (ty in fty.paramTys) {
                paramTys.add(ty)
            }
            paramTys.add(strTy)
            if (let Some(outer) <- constr.outerDecl) {
                if (let Some(retTy) <- outer.GetTy()) {
                    constr.SetTy(typeManager.GetFunctionTy(paramTys.toArray(), retTy))
                }
            }
            }
        }
    }

    private func InsertConstructorBody(constr: FuncDecl): Unit {
        if (ilib.GetJniEnvPtrDecl().isNone()) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let curFile = constr.curFile.getOrThrow()
        let envCall = ilib.CreateGetJniEnvCall(Some(curFile))
        if (let None <- envCall) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let jniEnvVar = CreateTmpVarDecl(None, Some((envCall.getOrThrow() as Expr).getOrThrow()))
        jniEnvVar.curFile = Some(curFile)
        let paramList = constr.funcBody.getOrThrow().paramLists[0]
        let envRef = WithinFile<RefExpr>(CreateRefExpr(jniEnvVar), curFile)
        let arrayCall = ilib.CreateCFFINewJavaArrayCall(envRef, paramList)
        if (let None <- arrayCall) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let asObj = ilib.CreateAsJniJobjectCall(arrayCall.getOrThrow())
        if (let None <- asObj) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let swapEnv = WithinFile<RefExpr>(CreateRefExpr(jniEnvVar), curFile)
        let swapped = ilib.CreateSwapLocalWithGlobalRefCall(swapEnv, asObj.getOrThrow())
        if (let None <- swapped) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        let javaref = ilib.CreateJavaEntityJobjectCall(swapped.getOrThrow())
        if (let None <- javaref) {
            constr.EnableAttr(Attribute.IS_BROKEN)
            return
        }
        if (let Some(outer) <- constr.outerDecl) {
            if (let Some(classLike) <- (outer as ClassLikeDecl)) {
                if (let Some(wrapping) <- GetJavaMirrorWrappingConstructor(classLike)) {
                    if (let Some(wrappingTy) <- wrapping.GetTy()) {
                        constr.constructorCall = ConstructorCall.OTHER_INIT
                        let nodes = ArrayList<Node>()
                        nodes.add(jniEnvVar)
                        nodes.add(javaref.getOrThrow())
                        let thisCall = CreateThisCall(outer, wrapping, wrappingTy, curFile)
                        thisCall.args.add(CreateFuncArg(WrapReturningLambdaCall(typeManager, nodes)))
                        let body = constr.funcBody.getOrThrow().body.getOrThrow()
                        body.body.clear()
                        body.body.add(thisCall)
                        return
                    }
                }
            }
        }
        constr.EnableAttr(Attribute.IS_BROKEN)
    }

    private func GenerateJniTypeConstructor(jarray: ClassDecl): Unit {
        var found: Option<FuncDecl> = None
        for (member in jarray.GetMemberDecls()) {
            if (let Some(fd) <- (member as FuncDecl)) {
                if (IsSizeConstructor(fd)) {
                    found = Some(fd)
                    break
                }
            }
        }
        if (let Some(sizeCtor) <- found) {
            if (let Some(cloned) <- (ASTCloner.Clone(sizeCtor) as FuncDecl)) {
                cloned.outerDecl = Some(jarray)
                cloned.curFile = jarray.curFile
                cloned.fullPackageName = jarray.fullPackageName
                cloned.EnableAttr(Attribute.COMPILER_ADD)
                InsertJniTypeParamIntoConstructor(cloned)
                InsertConstructorBody(cloned)
                jarray.GetMemberDecls().add(cloned)
            }
        }
    }

    private func InsertOriginalSizeConstructorBody(constr: FuncDecl): Unit {
        if (!IsSizeConstructor(constr)) {
            return
        }
        if (let Some(curFile) <- constr.curFile) {
            let throwExpr = CreateThrowExceptionCall(importManager, typeManager,
                "Internal error: unhandled call to JArray constructor", curFile)
            constr.funcBody.getOrThrow().body.getOrThrow().body.add(throwExpr)
        }
    }

    private func FillDesugarArgs(call: CallExpr): Unit {
        let args = ArrayList<Option<FuncArg>>()
        for (arg in call.args) {
            args.add(Some(arg))
        }
        call.desugarArgs = Some(args)
    }

    private func TransformConstructorCallsToPassJNIParam(file: File): Unit {
        Walker(file, visitPre: { node: Node =>
            if (!InFilePackage(node, file)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (let Some(funcDecl) <- callExpr.resolvedFunction) {
                    if (IsSizeConstructor(funcDecl)) {
                        if (let Some(outer) <- funcDecl.outerDecl) {
                            if (let Some(jarray) <- (outer as ClassDecl)) {
                                if (let Some(jniCtor) <- FindSizeJNITypeConstructor(jarray)) {
                                    if (let Some(newCall) <- (ASTCloner.Clone(callExpr) as CallExpr)) {
                                        newCall.resolvedFunction = jniCtor
                                        if (let Some(baseExpr) <- newCall.baseFunc) {
                                        if (let Some(base) <- (baseExpr as RefExpr)) {
                                            if (base.instTys.size == 1) {
                                                let elementTy = base.instTys[0]
                                                base.ref.target = jniCtor
                                                if (let Some(jniTy) <- jniCtor.GetTy()) {
                                                    base.SetTy(jniTy)
                                                }
                                                let jniType = ilib.SelectJSigByTypeKind(elementTy.kind, elementTy)
                                                jniType.curFile = Some(file)
                                                newCall.args.add(CreateFuncArg(jniType))
                                                FillDesugarArgs(newCall)
                                                callExpr.desugarExpr = Some(newCall)
                                            }
                                        }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func ReplaceCallsWithArrayJavaEntityGet(file: File): Unit {
        Walker(file, visitPre: { node: Node =>
            if (!InFilePackage(node, file)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (let Some(funcDecl) <- callExpr.resolvedFunction) {
                    if (let Some(outer) <- funcDecl.outerDecl) {
                        if (IsJArray(outer) && funcDecl.identifier.Val() == "[]" && callExpr.args.size == 1) {
                            if (let Some(baseNode) <- callExpr.baseFunc) {
                            if (let Some(ma) <- (baseNode as MemberAccess)) {
                                if (let Some(baseExpr) <- ma.baseExpr) {
                                    if (let Some(baseTy) <- baseExpr.GetTy()) {
                                        if (!baseTy.typeArgs.isEmpty()) {
                                            ReplaceGet(callExpr, outer, baseTy.typeArgs[0])
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func ReplaceGet(callExpr: CallExpr, outer: Decl, elementTy: Ty): Unit {
        if (!elementTy.IsClass() && !elementTy.IsCoreOptionType() && !elementTy.IsString()) {
            return
        }
        if (let Some(jarray) <- (outer as ClassDecl)) {
            if (let Some(getDecl) <- ilib.FindArrayJavaEntityGetDecl(jarray)) {
                if (let Some(newCall) <- (ASTCloner.Clone(callExpr) as CallExpr)) {
                    newCall.resolvedFunction = getDecl
                    if (let Some(baseNode) <- newCall.baseFunc) {
                    if (let Some(base) <- (baseNode as MemberAccess)) {
                        base.target = getDecl
                        if (let Some(getTy) <- getDecl.GetTy()) {
                            base.SetTy(getTy)
                        }
                    }
                    }
                    var entityCall: Expr = newCall
                    if (IsMirror(elementTy) || IsImpl(elementTy) || elementTy.IsCoreOptionType()) {
                        if (let Some(asObj) <- ilib.CreateAsJniJobjectCall(newCall)) {
                            if (let Some(env) <- ilib.CreateGetJniEnvCall(callExpr.curFile)) {
                                if (let Some(swapped) <- ilib.CreateSwapLocalWithGlobalRefCall(env, asObj)) {
                                    if (let Some(entity) <- ilib.CreateJavaEntityJobjectCall(swapped)) {
                                        entityCall = entity
                                    }
                                }
                            }
                        }
                    }
                    if (let Some(unwrapped) <- ilib.UnwrapJavaEntity(entityCall, elementTy, outer)) {
                        callExpr.desugarExpr = Some(unwrapped)
                    }
                    callExpr.desugarArgs = None
                }
            }
        }
    }

    private func ReplaceArgExpr(call: CallExpr, index: Int64, expr: Expr): Unit {
        let rebuilt = ArrayList<FuncArg>()
        var i: Int64 = 0
        for (arg in call.args) {
            if (i == index) {
                let cloned = (ASTCloner.Clone(arg) as FuncArg).getOrThrow()
                cloned.expr = Some(expr)
                rebuilt.add(cloned)
            } else {
                rebuilt.add(arg)
            }
            i = i + 1
        }
        call.args.clear()
        for (arg in rebuilt) {
            call.args.add(arg)
        }
    }

    private func ReplaceCallsWithArrayJavaEntitySet(file: File): Unit {
        Walker(file, visitPre: { node: Node =>
            if (!InFilePackage(node, file)) {
                return VisitAction.WALK_CHILDREN
            }
            if (let Some(callExpr) <- (node as CallExpr)) {
                if (let Some(funcDecl) <- callExpr.resolvedFunction) {
                    if (let Some(outer) <- funcDecl.outerDecl) {
                        if (IsJArray(outer) && funcDecl.identifier.Val() == "[]" && callExpr.args.size == 2) {
                            if (let Some(baseNode) <- callExpr.baseFunc) {
                            if (let Some(ma) <- (baseNode as MemberAccess)) {
                                if (let Some(baseExpr) <- ma.baseExpr) {
                                    if (let Some(baseTy) <- baseExpr.GetTy()) {
                                        if (!baseTy.typeArgs.isEmpty()) {
                                            ReplaceSet(callExpr, outer, baseTy.typeArgs[0])
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }
            VisitAction.WALK_CHILDREN
        }).Walk()
    }

    private func ReplaceSet(callExpr: CallExpr, outer: Decl, elementTy: Ty): Unit {
        if (!elementTy.IsClass() && !elementTy.IsCoreOptionType() && !elementTy.IsString()) {
            return
        }
        if (let Some(jarray) <- (outer as ClassDecl)) {
            if (let Some(setDecl) <- ilib.FindArrayJavaEntitySetDecl(jarray)) {
                if (let Some(newCall) <- (ASTCloner.Clone(callExpr) as CallExpr)) {
                    newCall.resolvedFunction = setDecl
                    if (let Some(value) <- newCall.args[1].expr) {
                        if (let Some(wrapped) <- ilib.WrapJavaEntity(value)) {
                            ReplaceArgExpr(newCall, 1, wrapped)
                        }
                    }
                    newCall.desugarArgs = None
                    if (let Some(baseNode) <- newCall.baseFunc) {
                    if (let Some(base) <- (baseNode as MemberAccess)) {
                        base.target = setDecl
                        if (let Some(setTy) <- setDecl.GetTy()) {
                            base.SetTy(setTy)
                        }
                    }
                    }
                    if (let Some(clonedArg) <- (ASTCloner.Clone(newCall.args[1]) as FuncArg)) {
                        ReplaceArgExpr(callExpr, 1, clonedArg.expr.getOrThrow())
                    }
                    if (let Some(clonedBase) <- (ASTCloner.Clone(newCall.baseFunc.getOrThrow()) as Expr)) {
                        callExpr.baseFunc = Some(clonedBase)
                    }
                    callExpr.resolvedFunction = setDecl
                    callExpr.desugarArgs = None
                    callExpr.desugarExpr = Some(newCall)
                }
            }
        }
    }

    public func Process(ctx: AfterTypeCheckContext): Unit {
        for (mirror in ctx.GetJavaMirrors()) {
            if (!IsJArray(mirror)) {
                continue
            }
            if (let Some(jarray) <- (mirror as ClassDecl)) {
                let members = ArrayList<Decl>()
                for (member in jarray.GetMemberDecls()) {
                    members.add(member)
                }
                for (member in members) {
                    if (let Some(fd) <- (member as FuncDecl)) {
                        InsertOriginalSizeConstructorBody(fd)
                    }
                }
                GenerateJniTypeConstructor(jarray)
            }
        }
        for (file in ctx.pkg.files) {
            ReplaceCallsWithArrayJavaEntityGet(file)
            ReplaceCallsWithArrayJavaEntitySet(file)
            TransformConstructorCallsToPassJNIParam(file)
        }
    }
}
