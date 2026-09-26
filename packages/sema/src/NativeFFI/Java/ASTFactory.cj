package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{InteropLibBridge, MemberJNISignature, WithinFile}

public class ASTFactory {
    private let ilib: InteropLibBridge

    public init(ilib: InteropLibBridge) {
        this.ilib = ilib
    }

    public func CreateInstanceJavaFieldSetCall(curFile: File, jobjectInstance: Expr,
        field: MemberJNISignature, ty: Ty, value: Expr): Option<Block> {
        return CreateJavaFieldSetCall(curFile, Some(jobjectInstance), field, ty, value, isStatic: false)
    }

    public func CreateStaticJavaFieldSetCall(curFile: File, field: MemberJNISignature, ty: Ty,
        value: Expr): Option<Block> {
        return CreateJavaFieldSetCall(curFile, None, field, ty, value, isStatic: true)
    }

    public func CreateJavaFieldSetCall(curFile: File, jobjectInstance: Option<Expr>, field: MemberJNISignature,
        ty: Ty, value: Expr, isStatic!: Bool): Option<Block> {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        let block = CreateBlock(ArrayList<Node>(), Some(unitTy))
        let jniValue = if (ty.IsPrimitive()) {
            ilib.CreateJValueExpr(value)
        } else {
            ilib.CreateJObjectExpr(value)
        }
        if (let None <- jniValue) {
            return None
        }
        let envCall = ilib.CreateGetJniEnvCall(Some(curFile))
        if (let None <- envCall) {
            return None
        }
        var setCall: Option<CallExpr> = None
        if (isStatic) {
            setCall = ilib.CreateSetStaticFieldCall(envCall.getOrThrow(), field.classTypeSignature, field.name,
                field.signature, jniValue.getOrThrow())
        } else {
            if (let Some(obj) <- jobjectInstance) {
                setCall = ilib.CreateSetFieldCall(envCall.getOrThrow(), obj, field, jniValue.getOrThrow())
            }
        }
        if (let None <- setCall) {
            return None
        }
        block.body.add(setCall.getOrThrow())
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(
            (ASTCloner.Clone(envCall.getOrThrow()) as Expr).getOrThrow())) {
            block.body.add(pending)
        }
        return Some(block)
    }

    public func CreateParamsUsage(paramList: FuncParamList): ArrayList<Expr> {
        let args = ArrayList<Expr>()
        for (param in paramList.params) {
            args.add(WithinFile<RefExpr>(CreateRefExpr(param), paramList.curFile))
        }
        return args
    }

    public func CreateNewJavaObjectCall(ctx: AfterTypeCheckContext, curFile: File, constructor: JavaMemberSignature,
        args: ArrayList<Expr>): Option<Block> {
        let _ = ctx
        let envCall = ilib.CreateGetJniEnvCall(Some(curFile))
        if (let None <- envCall) {
            return None
        }
        let env = envCall.getOrThrow()
        let wrapped = ArrayList<Expr>()
        for (arg in args) {
            if (let None <- arg.GetTy()) {
                return None
            }
            if (InteropLibBridge.IsJavaEntityTy(arg.GetTy().getOrThrow())) {
                wrapped.add(arg)
            } else {
                if (let Some(entity) <- ilib.WrapJavaEntity(arg)) {
                    wrapped.add(entity)
                } else {
                    return None
                }
            }
        }
        let local = ilib.CreateNewJavaObjectCall(env, constructor.classTypeJniName, constructor.signature, wrapped)
        if (let None <- local) {
            return None
        }
        let block = CreateBlock(ArrayList<Node>(), ilib.GetJavaEntityTy())
        let callRes = CreateTmpVarDecl(None, Some((local.getOrThrow() as Expr).getOrThrow()))
        callRes.curFile = Some(curFile)
        if (let Some(ty) <- local.getOrThrow().GetTy()) {
            callRes.SetTy(ty)
        }
        block.body.add(callRes)
        let pendingEnv = (ASTCloner.Clone(env) as Expr).getOrThrow()
        if (let Some(pending) <- ilib.CreateJNIHandlePendingExceptionCall(pendingEnv)) {
            block.body.add(pending)
        }
        let asObj = ilib.CreateAsJniJobjectCall(WithinFile<RefExpr>(CreateRefExpr(callRes), curFile))
        if (let None <- asObj) {
            return None
        }
        let swapEnv = (ASTCloner.Clone(env) as Expr).getOrThrow()
        let swapped = ilib.CreateSwapLocalWithGlobalRefCall(swapEnv, asObj.getOrThrow())
        if (let None <- swapped) {
            return None
        }
        let entity = ilib.CreateJavaEntityJobjectCall(swapped.getOrThrow())
        if (let None <- entity) {
            return None
        }
        let gref = CreateTmpVarDecl(None, entity)
        gref.curFile = Some(curFile)
        if (let Some(ty) <- entity.getOrThrow().GetTy()) {
            gref.SetTy(ty)
        }
        block.body.add(gref)
        block.body.add(WithinFile<RefExpr>(CreateRefExpr(gref), curFile))
        if (let Some(ty) <- ilib.GetJavaEntityTy()) {
            block.SetTy(ty)
        }
        return Some(block)
    }
}
