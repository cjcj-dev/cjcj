package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public class CGStructType <: CGCustomType {
    public init(cgMod: CGModule, cgCtx: CGContext, chirType: Type) {
        super(cgMod, cgCtx, chirType)
    }
}
