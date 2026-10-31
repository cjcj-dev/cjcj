package cjcj::chir

import std.collection.*

public class GetRefToArrayElem {
    public init() {}

    public static func RunOnPackage(pkg: Package, builder: CHIRBuilder, threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        if (threadNum <= 1) {
            for (fn in pkg.GetGlobalFuncsWithBody()) { changed += GetRefToArrayElem.RunOnFunc(fn, builder) }
            return changed
        }
        let runs = RunFunctionLocalPass<(Int64, CHIRBuilder, ArrayList<(Value, Expression)>)>(
            pkg.GetGlobalFuncsWithBody(), threadNum, { fn =>
                let worker = CHIRBuilder(builder.context)
                worker.SetCompileTimeValueMark(builder.GetCompileTimeValueMark())
                let users = ArrayList<(Value, Expression)>()
                (GetRefToArrayElem.RunOnFunc(fn, worker, users), worker, users)
            })
        for ((count, worker, users) in runs) {
            changed += count
            for ((value, user) in users) { value.MoveUserToTail(user) }
            worker.MergeAllocatedInstance()
        }
        return changed
    }

    public static func RunOnFunc(fn: Function, builder: CHIRBuilder): Int64 {
        return RunOnFunc(fn, builder, ArrayList<(Value, Expression)>())
    }

    private static func RunOnFunc(fn: Function, builder: CHIRBuilder,
        users: ArrayList<(Value, Expression)>): Int64 {
        var changed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocks()) {
                let exprs = block.GetExpressions()
                for (expr in exprs) {
                    if (let Some(intrinsic) <- (expr as Intrinsic)) {
                        if (TryRewriteArrayGetUnchecked(intrinsic, builder, users)) {
                            changed++
                        }
                    }
                }
            }
        }
        return changed
    }

    private static func TryRewriteArrayGetUnchecked(intrinsic: Intrinsic, builder: CHIRBuilder,
        users: ArrayList<(Value, Expression)>): Bool {
        if (intrinsic.GetIntrinsicKind() != IntrinsicKind.ARRAY_GET_UNCHECKED) {
            return false
        }
        let result = if (let Some(intrinsicResult) <- intrinsic.GetResult()) {
            intrinsicResult
        } else {
            return false
        }
        let resultTy = if (let Some(ty) <- result.GetType()) {
            ty
        } else {
            return false
        }
        let parentBlock = if (let Some(block) <- intrinsic.GetParentBlock()) {
            block
        } else {
            return false
        }
        let fieldUsers = CollectFieldUsers(result.GetUsers())
        if (fieldUsers.isNone()) {
            return false
        }

        let callContext = IntrisicCallContext(kind: IntrinsicKind.ARRAY_GET_REF_UNCHECKED,
            args: intrinsic.GetOperands())
        let arrayGetRef = builder.CreateIntrinsic(builder.context.GetRefTy(resultTy), callContext, parentBlock)
        for (operand in arrayGetRef.GetOperands()) {
            if (operand.IsGlobal()) { users.add((operand, arrayGetRef)) }
        }
        arrayGetRef.CopyBaseInfoFrom(intrinsic)
        let arrayGetRefResult = if (let Some(newResult) <- arrayGetRef.GetResult()) {
            newResult
        } else {
            return false
        }

        arrayGetRef.MoveBefore(intrinsic)
        if (let Some(fields) <- fieldUsers) {
            for (field in fields) {
                RewriteFieldUser(field, arrayGetRefResult, intrinsic, builder)
            }
        }
        intrinsic.RemoveSelfFromBlock()
        return true
    }

    private static func CollectFieldUsers(users: ArrayList<Expression>): Option<ArrayList<Field>> {
        let fields = ArrayList<Field>()
        for (user in users) {
            if (let Some(field) <- (user as Field)) {
                if (field.GetResultType().isNone() || field.GetParentBlock().isNone()) {
                    return None
                }
                fields.add(field)
            } else {
                return None
            }
        }
        return fields
    }

    private static func RewriteFieldUser(field: Field, arrayGetRefResult: LocalVar, snapshot: Intrinsic,
        builder: CHIRBuilder): Unit {
        let fieldTy = if (let Some(ty) <- field.GetResultType()) {
            ty
        } else {
            throw IllegalArgumentException("field rewrite requires a result type")
        }
        let parentBlock = if (let Some(block) <- snapshot.GetParentBlock()) {
            block
        } else {
            throw IllegalArgumentException("field rewrite requires a parent block")
        }
        let getElemRef = builder.CreateGetElementRef(builder.context.GetRefTy(fieldTy), arrayGetRefResult,
            field.GetPath(), parentBlock)
        getElemRef.CopyBaseInfoFrom(field)
        if (let Some(getElemRefResult) <- getElemRef.GetResult()) {
            getElemRefResult.EnableAttr(Attribute.READONLY)
            let load = builder.CreateLoad(fieldTy, getElemRefResult, parentBlock)
            load.CopyBaseInfoFrom(field)
            // Read the fields at the original value snapshot, not at a later use
            // which may follow an array write (including a write through an alias).
            getElemRef.MoveBefore(snapshot)
            load.MoveBefore(snapshot)
            field.GetResult().getOrThrow().ReplaceWith(load.GetResult().getOrThrow())
            field.RemoveSelfFromBlock()
        } else {
            throw IllegalArgumentException("GetElementRef rewrite requires a result")
        }
    }
}
