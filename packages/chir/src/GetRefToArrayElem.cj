package cangjie_compiler::chir

import std.collection.*

public class GetRefToArrayElem {
    public init() {}

    public static func RunOnPackage(pkg: Package, builder: CHIRBuilder): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += GetRefToArrayElem.RunOnFunc(fn, builder)
        }
        return changed
    }

    public static func RunOnFunc(fn: Function, builder: CHIRBuilder): Int64 {
        var changed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            for (block in body.GetBlocks()) {
                let exprs = block.GetExpressions()
                for (expr in exprs) {
                    if (let Some(intrinsic) <- (expr as Intrinsic)) {
                        if (TryRewriteArrayGetUnchecked(intrinsic, builder)) {
                            changed++
                        }
                    }
                }
            }
        }
        return changed
    }

    private static func TryRewriteArrayGetUnchecked(intrinsic: Intrinsic, builder: CHIRBuilder): Bool {
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
        arrayGetRef.CopyBaseInfoFrom(intrinsic)
        let arrayGetRefResult = if (let Some(newResult) <- arrayGetRef.GetResult()) {
            newResult
        } else {
            return false
        }

        if (let Some(fields) <- fieldUsers) {
            for (field in fields) {
                RewriteFieldUser(field, arrayGetRefResult, builder)
            }
        }
        intrinsic.ReplaceWith(arrayGetRef)
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

    private static func RewriteFieldUser(field: Field, arrayGetRefResult: LocalVar, builder: CHIRBuilder): Unit {
        let fieldTy = if (let Some(ty) <- field.GetResultType()) {
            ty
        } else {
            throw IllegalArgumentException("field rewrite requires a result type")
        }
        let parentBlock = if (let Some(block) <- field.GetParentBlock()) {
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
            getElemRef.MoveBefore(field)
            field.ReplaceWith(load)
        } else {
            throw IllegalArgumentException("GetElementRef rewrite requires a result")
        }
    }
}
