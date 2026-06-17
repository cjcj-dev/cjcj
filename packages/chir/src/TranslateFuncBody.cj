package cangjie_compiler::chir

import std.collection.*

extend AST2CHIRDeclTranslator {
    // Emit a real CHIR body for the first real-expression slice from `spec.bodyStatements`.
    // Supported grammar (Int64-only), in order:
    //   - LocalLetLiteral(name, value):   slot = Allocate(Ref<Int64>); c = Constant(value);
    //                                      Store(c, slot); locals[name] = slot
    //   - LocalLetBinary(name, op, l, r): vl = Load(l); vr = Load(r);
    //                                      sum = BinaryExpression(op, vl, vr);
    //                                      slot = Allocate(Ref<Int64>); Store(sum, slot);
    //                                      locals[name] = slot
    //   - ReturnExpr(operand):            v = (Load(slot) | Constant); Exit(Some(v))
    // The arithmetic is a genuine runtime CHIR `Add` — no constant folding here.
    public func CreateRealBody(fn: Function, spec: AST2CHIRFunctionSpec): Unit {
        let body = builder.CreateBlockGroup(fn.GetIdentifier() + ".body")
        fn.InitBody(body)
        let entry = builder.CreateBlock("entry", body)
        EnsureReturnSlot(fn, entry)

        let int64Ty = builder.context.GetInt64Ty()
        let refInt64Ty = builder.context.GetRefTy(int64Ty)
        // Maps a local name to its allocated slot (a Ref<Int64> Value).
        let locals = HashMap<String, Value>()

        var emittedExit = false
        for (stmt in spec.bodyStatements) {
            if (stmt.IsLetLiteral()) {
                let slot = AllocateInt64Slot(refInt64Ty, int64Ty, entry)
                let constant = builder.CreateConstant(int64Ty, IntLiteral(stmt.literalValue), entry)
                if (let Some(constResult) <- constant.GetResult()) {
                    builder.CreateStore(constResult, slot, entry)
                }
                locals[stmt.name] = slot
                continue
            }
            if (stmt.IsLetBinary()) {
                let lhsValue = LoadOperand(stmt.lhsIsLiteral, stmt.lhsName, stmt.lhsLiteral, locals, int64Ty, entry)
                let rhsValue = LoadOperand(stmt.rhsIsLiteral, stmt.rhsName, stmt.rhsLiteral, locals, int64Ty, entry)
                if (let (Some(lv), Some(rv)) <- (lhsValue, rhsValue)) {
                    let binary = builder.CreateBinaryExpression(stmt.op, int64Ty, lv, rv, entry)
                    let slot = AllocateInt64Slot(refInt64Ty, int64Ty, entry)
                    if (let Some(sumResult) <- binary.GetResult()) {
                        builder.CreateStore(sumResult, slot, entry)
                    }
                    locals[stmt.name] = slot
                }
                continue
            }
            if (stmt.IsReturn()) {
                let value = LoadOperand(stmt.lhsIsLiteral, stmt.lhsName, stmt.lhsLiteral, locals, int64Ty, entry)
                if (let Some(v) <- value) {
                    builder.CreateExit(Some(v), entry)
                } else {
                    builder.CreateExit(None, entry)
                }
                emittedExit = true
            }
        }
        if (!emittedExit) {
            builder.CreateExit(None, entry)
        }
    }

    private func AllocateInt64Slot(refInt64Ty: Type, int64Ty: Type, entry: Block): Value {
        let allocate = builder.CreateAllocate(refInt64Ty, int64Ty, entry)
        return allocate.GetResult().getOrThrow()
    }

    // Materialize an operand as an Int64 Value: a Load of the named local's slot, or a Constant.
    private func LoadOperand(isLiteral: Bool, name: String, literal: Int64, locals: HashMap<String, Value>,
        int64Ty: Type, entry: Block): Option<Value> {
        if (isLiteral) {
            let constant = builder.CreateConstant(int64Ty, IntLiteral(literal), entry)
            if (let Some(result) <- constant.GetResult()) {
                return Some(result)
            }
            return None
        }
        if (let Some(slot) <- locals.get(name)) {
            let load = builder.CreateLoad(int64Ty, slot, entry)
            if (let Some(result) <- load.GetResult()) {
                return Some(result)
            }
            return None
        }
        return None
    }
}
