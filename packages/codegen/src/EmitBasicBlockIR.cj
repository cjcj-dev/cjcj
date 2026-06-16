package cangjie_compiler::codegen

import cangjie_compiler::chir.Block

public func EmitBasicBlockIR(cgMod: CGModule, builder: IRBuilder2, block: Block): Unit {
    EmitExpressionIR(cgMod, builder, block.GetExpressions())
}
