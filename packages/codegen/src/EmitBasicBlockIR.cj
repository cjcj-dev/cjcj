package cangjie_compiler::codegen

import cangjie_compiler::chir.Block
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKind

public func EmitBasicBlockIR(cgMod: CGModule, builder: IRBuilder2, block: Block): Unit {
    for (expr in block.GetExpressions()) {
        let emitted = DispatchExpression(builder, expr)
        if (let Some(resultValue) <- expr.GetResult()) {
            let resultType = if (let Some(valueType) <- resultValue.GetType()) {
                CGType.GetOrCreate(cgMod, valueType)
            } else {
                CGType(cgMod, cgMod.GetCGContext(), Type(TypeKind.TYPE_INVALID))
            }
            cgMod.SetOrUpdateMappedCGValue(resultValue, CGValue(emitted, resultType))
        }
    }
}
