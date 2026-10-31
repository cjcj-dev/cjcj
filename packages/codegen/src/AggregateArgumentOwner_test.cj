package cjcj::codegen

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.DiagnosticEngine
import cjcj::chir.*
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::option.{GlobalOptions, TripleInfo}

// Exercise the real call emitter for Ref<Tuple>, complementing the public
// CLI's struct-method cases. No textual IR or replacement lowering is used.
@Test
public class AggregateArgumentOwnerTest {
    private func CheckTupleCall(trackOwner: Bool, copyValue!: Bool = false): Unit {
        let context = CHIRContext()
        let builder = CHIRBuilder(context)
        let pkg = builder.CreatePackage("tuple_owner_test")
        let options = GlobalOptions()
        options.host = TripleInfo()
        options.target = TripleInfo()
        let diag = DiagnosticEngine()
        let pkgContext = CGPkgContext(CHIRData(context, pkg), options, false,
            NoHeapAllocChecker(diag), NoWriteBarrierRecChecker(diag), CachedMangleMap())
        let module = CGModule(SubCHIRPackage(1), pkgContext)
        try {
            let tuple = context.GetTupleTy(ArrayList<Type>([context.GetInt64Ty(), context.GetInt64Ty()]))
            let reference = context.GetRefTy(tuple)
            let chirFunctionType = context.GetFuncTy(ArrayList<Type>([reference]), context.GetInt64Ty())
            let functionType = (CGType.GetOrCreate(module, chirFunctionType) as CGFunctionType).getOrThrow()
            @Assert(functionType.HasBasePtr())
            let caller = module.GetOrInsertFunction("caller", functionType.GetLLVMFunctionType())
            let destination = if (copyValue) {
                let dynamicTuple = context.GetTupleTy(ArrayList<Type>([context.GetGenericTy("T"), context.GetInt64Ty()]))
                let dynamicFunction = context.GetFuncTy(ArrayList<Type>([context.GetRefTy(dynamicTuple)]), context.GetInt64Ty())
                (CGType.GetOrCreate(module, dynamicFunction) as CGFunctionType).getOrThrow()
            } else { functionType }
            let callee = module.GetOrInsertFunction("callee", destination.GetLLVMFunctionType())
            @Expect(unsafe { LLVMCountParams(caller) }, 2u32)
            let payload = unsafe { LLVMGetParam(caller, 0u32) }
            let owner = unsafe { LLVMGetParam(caller, 1u32) }
            if (trackOwner) { module.GetCGContext().SetBasePtr(payload, owner) }
            try (ir = IRBuilder2(module)) {
                ir.SetInsertPoint(ir.CreateBasicBlockAtEnd(caller, "entry"))
                let argument = if (copyValue) {
                    let tupleType = CGType.GetOrCreate(module, tuple)
                    let slot = ir.CreateEntryAlloca(tupleType.GetLLVMType(), name: "source.value")
                    ir.CreateStore(unsafe { LLVMConstNull(tupleType.GetLLVMType()) }, slot)
                    CGValue(slot, tupleType)
                } else { CGValue(payload, CGType.GetOrCreate(module, reference)) }
                let call = ir.CreateCallOrInvoke(destination, callee, ArrayList<CGValue>([argument]))
                @Assert(unsafe { LLVMSelfhostIsCallInst(call) } != 0)
                let actual = unsafe { LLVMGetOperand(call, 1u32) }
                if (copyValue) {
                    let finalValue = unsafe { LLVMGetOperand(call, 0u32) }
                    @Expect(actual.toUIntNative(), finalValue.toUIntNative())
                    @Assert(unsafe { LLVMSelfhostIsCallInst(actual) } != 0)
                    @Assert(actual.toUIntNative() != payload.toUIntNative())
                } else if (trackOwner) {
                    @Expect(actual.toUIntNative(), owner.toUIntNative())
                } else {
                    @Expect(actual.toUIntNative(), unsafe {
                        LLVMConstNull(CGType.GetRefType(module.GetLLVMContext())).toUIntNative()
                    })
                }
                ir.CreateRet(call)
                println("TUPLE_OWNER_ASSERT tracked=${trackOwner} copy=${copyValue}")
            }
        } finally {
            module.Clear()
            pkgContext.Clear()
        }
    }

    @TestCase public func CopiedTupleUsesNewAllocationOwner(): Unit { CheckTupleCall(false, copyValue: true) }
    @TestCase public func ForwardedTupleKeepsExactOwner(): Unit { CheckTupleCall(true) }
    @TestCase public func UnknownTupleDoesNotInventGlobalMarker(): Unit { CheckTupleCall(false) }
}
