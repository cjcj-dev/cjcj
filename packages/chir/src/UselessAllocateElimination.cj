package cjcj::chir

import cjcj::utils.StaticCast

public class UselessAllocateElimination {
    public init() {}

    // A TryAllocate is a terminator; once it is removed its block continues to the success block
    // (UselessAllocateElimination.cpp, upstream !2344). That needs a builder, so without one TryAllocate stays.
    public static func RunOnPackage(pkg: Package, isDebug!: Bool = false, threadNum!: Int64 = 1,
        builder!: Option<CHIRBuilder> = None): Unit {
        let withTry = builder.isSome()
        let pending = ArrayList<(Block, Block, DebugLocation)>()
        if (threadNum <= 1 || isDebug) {
            for (fn in pkg.GetGlobalFuncsWithBody()) { pending.add(all: RunOnFunc(fn, isDebug, withTry)) }
        } else {
            // No cross-function analysis: each task removes only its own unused allocation and stores.
            // Shared global operands only lose users under Value's existing lock; terminator creation
            // goes through the shared builder and is replayed serially below.
            for (gotos in RunFunctionLocalPass<ArrayList<(Block, Block, DebugLocation)>>(pkg.GetGlobalFuncsWithBody(),
                threadNum, { fn => RunOnFunc(fn, false, withTry) }, passName: "useless-allocation")) {
                pending.add(all: gotos)
            }
        }
        if (let Some(chirBuilder) <- builder) {
            for ((block, success, loc) in pending) {
                let jump = chirBuilder.CreateGoTo(success, block)
                jump.SetDebugLocation(loc)
                block.AppendExpression(jump)
            }
        }
    }

    private static func RunOnFunc(fn: Function, isDebug: Bool, withTry: Bool): ArrayList<(Block, Block, DebugLocation)> {
        let pending = ArrayList<(Block, Block, DebugLocation)>()
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                let kind = expr.GetExprKind()
                if (kind != ExprKind.ALLOCATE && !(withTry && kind == ExprKind.TRY_ALLOCATE)) {
                    continue
                }
                let allocate = StaticCast<AllocateBase>(expr)
                let allocatedTy = allocate.GetType()
                if (allocatedTy.IsClass() &&
                    StaticCast<ClassType>(allocatedTy).GetClassDef().GetFinalizer().isSome()) {
                    continue
                }
                let result = allocate.GetResult().getOrThrow()
                if (let Some(retValue) <- fn.GetReturnValue()) {
                    if (refEq(retValue, result)) {
                        continue
                    }
                }
                let users = result.GetUsers()
                var onlyBeenWritten = true
                for (user in users) {
                    if (user.GetExprKind() == ExprKind.STORE &&
                        StaticCast<Store>(user).GetLocation().nodeId == result.nodeId) {
                        continue
                    }
                    if (user.GetExprKind() == ExprKind.STORE_ELEMENT_REF &&
                        StaticCast<StoreElementRef>(user).GetLocation().nodeId == result.nodeId) {
                        continue
                    }
                    if (user.GetExprKind() == ExprKind.DEBUGEXPR) {
                        continue
                    }
                    onlyBeenWritten = false
                    break
                }
                if (onlyBeenWritten) {
                    if (let Some(tryAllocate) <- (allocate as TryAllocate)) {
                        pending.add((block, tryAllocate.GetSuccessBlock(), tryAllocate.GetDebugLocation()))
                    }
                    allocate.RemoveSelfFromBlock()
                    for (user in users) {
                        user.RemoveSelfFromBlock()
                    }
                    if (isDebug && !allocate.GetDebugLocation().GetBeginPos().IsZero()) {
                        println("[UselessAllocateElimination] Allocate" +
                            ToPosInfo(allocate.GetDebugLocation()) + " and its users have been deleted")
                    }
                }
            }
        }
        return pending
    }
}
