package cjcj::sema.NativeFFI.Java

import std.collection.*
import cjcj::ast.*
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{InteropLibBridge, MemberJNISignature}

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
}
