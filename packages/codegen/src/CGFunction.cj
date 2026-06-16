package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Value

public class CGFunction <: CGValue {
    private let cgMod: CGModule
    private let chirFunc: Value
    private let cgFunctionType: Option<CGFunctionType>
    private var wrapperF: LLVMValueRef = LLVMNullValue()
    public let genericParamsMap: HashMap<String, (IRBuilder2) -> LLVMValueRef> = HashMap<String, (IRBuilder2) -> LLVMValueRef>()

    public init(function: LLVMValueRef, cgType: CGType, chirFunc: Value, cgMod: CGModule) {
        super(function, cgType)
        this.cgMod = cgMod
        this.chirFunc = chirFunc
        cgFunctionType = cgType as CGFunctionType
    }

    public func GetOriginal(): Value { return chirFunc }
    public func GetRawFunction(): LLVMValueRef { return GetRawValue() }
    public func GetCGFunctionType(): Option<CGFunctionType> { return cgFunctionType }
    public func IsSRet(): Bool {
        if (let Some(functionType) <- cgFunctionType) {
            return functionType.HasSRet()
        }
        return false
    }

    public func GetWrapperFunction(): LLVMValueRef { return wrapperF }
    public func SetWrapperFunction(wrapper: LLVMValueRef): Unit { wrapperF = wrapper }

    public func GetArgByIndexFromCHIR(index: Int64): LLVMValueRef {
        let offset = if (IsSRet()) { 1 } else { 0 }
        return unsafe { LLVMGetParam(GetRawFunction(), UInt32(index + offset)) }
    }

    public func Opt(): Unit {
        CGFunction.RemoveUnreachableBlocks(GetRawFunction())
    }

    public func DumpIR(): Unit {
        println("CGFunction " + chirFunc.GetIdentifierWithoutPrefix())
    }

    public static func RemoveUnreachableBlocks(function: LLVMValueRef): Unit {
        if (function.isNull()) {
            return
        }
        // TODO(selfhost:CodeGen): port unreachable-block removal through LLVM CFG iteration.
    }
}
