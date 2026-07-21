package cjcj::codegen

import cjcj::chir.Attribute
import cjcj::chir.Function
import cjcj::option.MockMode

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
        let rawFunction = cgFunc.GetRawFunction()
        let options = cgMod.GetCGContext().GetCompileOptions()
        let isMockMode = options.mock == MockMode.ON || options.enableCompileTest
        let shouldGenDebugInfo = isMockMode || chirFunc.IsFuncWithBody()
        if (shouldGenDebugInfo) {
            if (let Some(diBuilder) <- cgMod.GetDIBuilder()) {
                diBuilder.SetSubprogram(chirFunc, rawFunction)
            }
        }
        if (let Some(body) <- chirFunc.GetBody()) {
            cgMod.MapFunctionParameters(chirFunc, cgFunc)
            if (!ShouldReturnVoid(chirFunc)) {
                SetSRetAttrForStructReturnType(chirFunc.GetFuncType().getOrThrow(), rawFunction)
            }
            if (let Some(entryBlock) <- body.GetEntryBlock()) {
                EmitBasicBlockIR(cgMod, entryBlock)
            }
            if (!unsafe { LLVMGetSubprogram(rawFunction) }.isNull()) {
                cgMod.GetCGContext().debugValue = LLVMNullValue()
                if (let Some(diBuilder) <- cgMod.GetDIBuilder()) {
                    diBuilder.FinalizeSubProgram(rawFunction)
                }
            }
        } else {
            // Declarations are materialized by GetOrInsertCGFunction and have no body to emit.
        }
        if ((options.enableTimer || options.enableMemoryCollect)) {
            if (let Some(genericDecl) <- chirFunc.GetGenericDecl()) {
                if (genericDecl.TestAttr(Attribute.IMPORTED)) {
                    AddFnAttr(rawFunction, GENERIC_DECL_IN_IMPORTED_PKG_ATTR)
                } else {
                    AddFnAttr(rawFunction, GENERIC_DECL_IN_CURRENT_PKG_ATTR)
                }
            }
        }
        if (chirFunc.IsLambda()) {
            AddFnAttr(rawFunction, FUNC_USED_BY_CLOSURE)
        }
    }

    public func GetCGFunction(): Option<CGFunction> {
        return cgFunction
    }
}

public func EmitFunctionIR(cgMod: CGModule, chirFunc: Function): Option<CGFunction> {
    let generator = FunctionGeneratorImpl(cgMod, chirFunc)
    IRGenerator(generator).EmitIR()
    if (let Some(body) <- chirFunc.GetBody()) {
        cgMod.GetCGContext().GetCHIRBuilder().context.FreeMemoryInFunc(body)
        chirFunc.DestroyFuncBody()
    }
    return generator.GetCGFunction()
}
