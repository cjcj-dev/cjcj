package cangjie_compiler::codegen

import cangjie_compiler::chir.Function

private class FunctionGeneratorImpl <: IRGeneratorImpl {
    private let cgMod: CGModule
    private let chirFunc: Function
    private var cgFunction: Option<CGFunction> = None

    public init(cgMod: CGModule, chirFunc: Function) {
        this.cgMod = cgMod
        this.chirFunc = chirFunc
    }

    public func EmitIR(): Unit {
        let cgFunc = cgMod.GetOrInsertCGFunction(chirFunc)
        cgFunction = cgFunc
        if (let Some(body) <- chirFunc.GetBody()) {
            cgMod.MapFunctionParameters(chirFunc, cgFunc)
            if (!ShouldReturnVoid(chirFunc)) {
                SetSRetAttrForStructReturnType(chirFunc.GetFuncType().getOrThrow(), cgFunc.GetRawFunction())
            }
            if (let Some(entryBlock) <- body.GetEntryBlock()) {
                EmitBasicBlockIR(cgMod, entryBlock)
            }
        } else {
            // Declarations are materialized by GetOrInsertCGFunction and have no body to emit.
        }
    }

    public func GetCGFunction(): Option<CGFunction> {
        return cgFunction
    }
}

public func EmitFunctionIR(cgMod: CGModule, chirFunc: Function): Option<CGFunction> {
    let generator = FunctionGeneratorImpl(cgMod, chirFunc)
    IRGenerator(generator).EmitIR()
    return generator.GetCGFunction()
}
