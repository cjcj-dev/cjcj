// Self-host LLVM FFI C-shim.
//
// Bridges LLVM C++ APIs that have NO LLVM-C (C ABI) equivalent, so the
// self-hosted Cangjie CodeGen can faithfully mirror the C++ compiler.
// Linked statically into the `cjc` executable (see packages/cjc/cjpm.toml
// link-option). Undefined LLVM symbols resolve against libLLVM-15.so, which
// cjc already links at runtime.
//
// Build: runtime_shim/build_shim.sh
//
// Entries (grow as more LLVM-C gaps surface during the port):
//   R-A': GlobalVariable::addAttribute(StringRef,StringRef)  -- no LLVM-C ABI.
//         C++ use: src/CodeGen/CJNative/EmitPackageIR.cpp:701  gv->addAttribute(GC_KLASS_ATTR)
//         GC_KLASS_ATTR = "CFileKlass"  (src/CodeGen/Utils/Constants.h:35)
//   CGFunction::AddZeroInitForStructWithRefField support:
//         src/CodeGen/CGFunction.cpp:262-274, 329-350.
//   CGFunction::EraseReplaceableAlloca support:
//         src/CodeGen/CGFunction.cpp:252  specificInst->moveBefore(&entryBB.front())
//   CGCFFI ABI classifier support:
//         src/CodeGen/CJNative/CJNativeCGCFFI.cpp:542  type.getPrimitiveSizeInBits()
//   With-TypeInfo wrapper rewrite support:
//         src/CodeGen/CJNative/EmitPackageIR.cpp:526-616  llvm::CallBase/InvokeInst APIs.
//   Constant array literal support:
//         src/CodeGen/Utils/CGUtils.cpp:250-255  llvm::dyn_cast<llvm::Constant>(value).
//   IRBuilder2::IsGlobalVariableBasePtr support:
//         src/CodeGen/CJNative/CJNativeIRBuilder.cpp:456-459  Value::stripInBoundsOffsets().
//   DIBuilder subprogram support:
//         src/CodeGen/DIBuilder.cpp:204-207, 282-283, 455-476  C++ overloads not exposed exactly by LLVM-C.
//   DIBuilder composite type support:
//         src/CodeGen/DIBuilder.cpp:718-722, 899-917, 1102-1539.
//   CGFunction::RemoveUnreachableBlocks support:
//         src/CodeGen/CGFunction.cpp:211-217  llvm::removeUnreachableBlocks(Function&).

#include <llvm-c/Core.h>
#include <llvm-c/DebugInfo.h>

#include <algorithm>
#include <cstdlib>
#include <vector>

#include "llvm/ADT/StringRef.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/DIBuilder.h"
#include "llvm/IR/DebugInfoMetadata.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalObject.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Use.h"
#include "llvm/IR/User.h"
#include "llvm/Transforms/Utils/Local.h"
#include "llvm/IR/Value.h"

#include "flatbuffers/ModuleFormat_generated.h"
#include "llvm/Analysis/CallGraph.h"

using namespace llvm;

constexpr int CJOF_FB_MAX_DEPTH = 128;
constexpr int CJOF_FB_MAX_TABLES = 2000000;

namespace {
struct LLVMSelfhostLoopInfoState {
    DominatorTree domTree;
    LoopInfoBase<BasicBlock, Loop> loopInfo;

    explicit LLVMSelfhostLoopInfoState(Function& function) : domTree(function), loopInfo()
    {
        loopInfo.analyze(domTree);
    }
};

void ConvertArgsType(IRBuilder<> &builder, Function *func, std::vector<Value*> &args)
{
    auto *functionType = func->getFunctionType();
    for (size_t idx = 0; idx < args.size(); ++idx) {
        if (args[idx]->getType() == functionType->getParamType(idx)) {
            continue;
        }
        if (!args[idx]->getType()->isPointerTy()) {
            continue;
        }
        args[idx] = builder.CreatePointerCast(args[idx], functionType->getParamType(idx));
    }
}

CallInst *CreateCall(IRBuilder<> &builder, FunctionType *functionType, Value *callee, ArrayRef<Value*> args,
    const Twine &name = "")
{
    if (auto *func = dyn_cast<Function>(callee)) {
        return builder.CreateCall(func, args, name);
    }
    return builder.CreateCall(functionType, callee, args, name);
}

CallInst *CreateCall(IRBuilder<> &builder, Function *callee, ArrayRef<Value*> args, const Twine &name = "")
{
    return builder.CreateCall(callee, args, name);
}

LLVMValueRef CreateGCStaticAggCall(LLVMBuilderRef Builder, LLVMModuleRef Module, LLVMTypeRef AggType,
    LLVMValueRef Dest, LLVMValueRef Source, LLVMValueRef Size, LLVMTypeRef SizeType, Intrinsic::ID ID)
{
    auto *builder = unwrap(Builder);
    auto *module = unwrap(Module);
    auto *sizeType = unwrap<Type>(SizeType);
    auto *func = Intrinsic::getDeclaration(module, ID, {sizeType});
    std::vector<Value*> args{unwrap(Dest), unwrap(Source), unwrap(Size)};
    if (ID == Intrinsic::cj_gcwrite_static_struct) {
        if (auto *size = dyn_cast<ConstantInt>(args[2]); size && size->isZero()) {
            return nullptr;
        }
    }
    args[2] = builder->CreateZExtOrTrunc(args[2], sizeType);
    ConvertArgsType(*builder, func, args);
    auto *inst = CreateCall(*builder, func, args);
    (void)AggType;
    return wrap(inst);
}
} // namespace

using LLVMSelfhostLoopInfoRef = LLVMSelfhostLoopInfoState*;
using LLVMSelfhostLoopRef = Loop*;

// Mirror TranslateLitConstant's `static_cast<float>(strtold(...))`
// (src/CHIR/AST2CHIR/TranslateASTNode/TranslateLitConstExpr.cpp:25,80).
extern "C" double CJSelfhostStrtoldToFloat32(const char *Value)
{
    return static_cast<float>(strtold(Value, nullptr));
}

// Mirror C++ `gv->addAttribute(Kind, Val)` (llvm/IR/GlobalVariable.h:239).
// Val may be empty (KLen/VLen are explicit lengths; no NUL assumption).
extern "C" void LLVMGlobalObjectAddStringAttribute(
        LLVMValueRef GV, const char *K, unsigned KLen, const char *V, unsigned VLen) {
    unwrap<GlobalVariable>(GV)->addAttribute(StringRef(K, KLen), StringRef(V, VLen));
}

// Mirror C++ `rawGV->addAttribute(llvm::Attribute::ReadOnly)`
// (src/CodeGen/EmitGlobalVariableIR.cpp:63).
extern "C" void LLVMSelfhostGlobalVariableAddEnumAttribute(LLVMValueRef GV, unsigned KindId)
{
    unwrap<GlobalVariable>(GV)->addAttribute(static_cast<Attribute::AttrKind>(KindId));
}

extern "C" LLVMBasicBlockRef LLVMSelfhostGetNearestCommonAncestorOfBasicBlocks(
        LLVMBasicBlockRef *BBs, unsigned Count)
{
    if (Count == 0) {
        return nullptr;
    }
    auto *pre = unwrap(BBs[0]);
    auto *function = pre->getParent();
    DominatorTree dt(*function);
    for (unsigned idx = 1; idx < Count; ++idx) {
        auto *cur = unwrap(BBs[idx]);
        pre = dt.findNearestCommonDominator(pre, cur);
    }
    return wrap(pre);
}

extern "C" LLVMSelfhostLoopInfoRef LLVMSelfhostCreateLoopInfo(LLVMValueRef Fn)
{
    return new LLVMSelfhostLoopInfoState(*unwrap<Function>(Fn));
}

extern "C" void LLVMSelfhostDisposeLoopInfo(LLVMSelfhostLoopInfoRef Info)
{
    delete Info;
}

extern "C" LLVMSelfhostLoopRef LLVMSelfhostLoopInfoGetLoopFor(
        LLVMSelfhostLoopInfoRef Info, LLVMBasicBlockRef BB)
{
    return Info->loopInfo.getLoopFor(unwrap(BB));
}

extern "C" LLVMSelfhostLoopRef LLVMSelfhostLoopGetOutermostLoop(LLVMSelfhostLoopRef LoopRef)
{
    return LoopRef->getOutermostLoop();
}

extern "C" LLVMBasicBlockRef LLVMSelfhostLoopGetLoopPreheader(LLVMSelfhostLoopRef LoopRef)
{
    return wrap(LoopRef->getLoopPreheader());
}

extern "C" LLVMBasicBlockRef LLVMSelfhostLoopGetHeader(LLVMSelfhostLoopRef LoopRef)
{
    return wrap(LoopRef->getHeader());
}

extern "C" int LLVMSelfhostLoopContainsBasicBlock(LLVMSelfhostLoopRef LoopRef, LLVMBasicBlockRef BB)
{
    return LoopRef->contains(unwrap(BB)) ? 1 : 0;
}

extern "C" unsigned LLVMSelfhostGetBasicBlockPredecessorCount(LLVMBasicBlockRef BB)
{
    return pred_size(unwrap(BB));
}

extern "C" void LLVMSelfhostGetBasicBlockPredecessors(LLVMBasicBlockRef BB, LLVMBasicBlockRef *Preds)
{
    unsigned idx = 0;
    for (auto *pred : predecessors(unwrap(BB))) {
        Preds[idx++] = wrap(pred);
    }
}

extern "C" LLVMBasicBlockRef LLVMSelfhostBasicBlockGetUniqueSuccessor(LLVMBasicBlockRef BB)
{
    return wrap(unwrap(BB)->getUniqueSuccessor());
}

extern "C" int LLVMSelfhostIsBranchInst(LLVMValueRef Inst)
{
    return isa<BranchInst>(unwrap<Value>(Inst)) ? 1 : 0;
}

extern "C" LLVMBasicBlockRef LLVMSelfhostSplitBasicBlock(
        LLVMBasicBlockRef BB, LLVMValueRef BeforeInst, const char *Name)
{
    return wrap(unwrap(BB)->splitBasicBlock(unwrap<Instruction>(BeforeInst), Name));
}

extern "C" void LLVMSelfhostRemoveUnreachableBlocks(LLVMValueRef Fn)
{
    auto *function = unwrap<Function>(Fn);
    if (function->isDeclaration()) {
        return;
    }
    removeUnreachableBlocks(*function);
}

extern "C" int LLVMSelfhostInstructionComesBefore(LLVMValueRef Inst, LLVMValueRef Other)
{
    return unwrap<Instruction>(Inst)->comesBefore(unwrap<Instruction>(Other)) ? 1 : 0;
}

extern "C" void LLVMSelfhostInstructionMoveBefore(LLVMValueRef Inst, LLVMValueRef Other)
{
    unwrap<Instruction>(Inst)->moveBefore(unwrap<Instruction>(Other));
}

extern "C" int LLVMSelfhostIsCallInst(LLVMValueRef Inst)
{
    return isa<CallInst>(unwrap<Value>(Inst)) ? 1 : 0;
}

extern "C" int LLVMSelfhostIsInvokeInst(LLVMValueRef Inst)
{
    return isa<InvokeInst>(unwrap<Value>(Inst)) ? 1 : 0;
}

extern "C" int LLVMSelfhostIsConstant(LLVMValueRef Val)
{
    return isa<Constant>(unwrap<Value>(Val)) ? 1 : 0;
}

extern "C" int LLVMSelfhostIsConstantInt(LLVMValueRef Val)
{
    return isa<ConstantInt>(unwrap<Value>(Val)) ? 1 : 0;
}

extern "C" int LLVMSelfhostIsNullConstant(LLVMValueRef Val)
{
    auto *constant = dyn_cast<Constant>(unwrap<Value>(Val));
    return constant && constant->isNullValue() ? 1 : 0;
}

extern "C" int LLVMSelfhostCallBaseHasStructRetAttr(LLVMValueRef Call)
{
    return unwrap<CallBase>(Call)->hasStructRetAttr() ? 1 : 0;
}

extern "C" int LLVMSelfhostFunctionHasStructRetAttr(LLVMValueRef Fn)
{
    return unwrap<Function>(Fn)->hasStructRetAttr() ? 1 : 0;
}

extern "C" unsigned LLVMSelfhostCallBaseArgSize(LLVMValueRef Call)
{
    return unwrap<CallBase>(Call)->arg_size();
}

extern "C" LLVMValueRef LLVMSelfhostCallBaseGetArgOperand(LLVMValueRef Call, unsigned Index)
{
    return wrap(unwrap<CallBase>(Call)->getArgOperand(Index));
}

extern "C" LLVMAttributeRef LLVMSelfhostCallBaseGetStructRetAttr(LLVMValueRef Call)
{
    return wrap(unwrap<CallBase>(Call)->getAttributeAtIndex(AttributeList::FirstArgIndex, Attribute::StructRet));
}

extern "C" void LLVMSelfhostCallBaseAddAttributeAtIndex(LLVMValueRef Call, unsigned Index, LLVMAttributeRef Attr)
{
    unwrap<CallBase>(Call)->addAttributeAtIndex(Index, unwrap(Attr));
}

extern "C" LLVMBasicBlockRef LLVMSelfhostInvokeGetNormalDest(LLVMValueRef Inst)
{
    return wrap(cast<InvokeInst>(unwrap<Value>(Inst))->getNormalDest());
}

extern "C" LLVMBasicBlockRef LLVMSelfhostInvokeGetUnwindDest(LLVMValueRef Inst)
{
    return wrap(cast<InvokeInst>(unwrap<Value>(Inst))->getUnwindDest());
}

extern "C" LLVMValueRef LLVMSelfhostBasicBlockGetFirstInsertionPoint(LLVMBasicBlockRef BB)
{
    BasicBlock *block = unwrap(BB);
    auto insertPoint = block->getFirstInsertionPt();
    if (insertPoint == block->end()) {
        return nullptr;
    }
    return wrap(&*insertPoint);
}

extern "C" LLVMValueRef LLVMSelfhostGetInsertPointInstruction(LLVMBuilderRef Builder)
{
    auto *builder = unwrap(Builder);
    auto *block = builder->GetInsertBlock();
    if (block == nullptr) {
        return nullptr;
    }
    auto insertPoint = builder->GetInsertPoint();
    if (insertPoint == block->end()) {
        return nullptr;
    }
    return wrap(&*insertPoint);
}

extern "C" LLVMValueRef LLVMSelfhostCreateCall(LLVMBuilderRef Builder, LLVMTypeRef FunctionTy, LLVMValueRef Callee,
    LLVMValueRef *Args, unsigned NumArgs, const char *Name)
{
    auto *builder = unwrap(Builder);
    std::vector<Value*> args;
    args.reserve(NumArgs);
    for (unsigned idx = 0; idx < NumArgs; ++idx) {
        args.push_back(unwrap(Args[idx]));
    }
    auto *callee = unwrap<Value>(Callee);
    if (auto *func = dyn_cast<Function>(callee)) {
        return wrap(CreateCall(*builder, func, args, Name));
    }
    return wrap(CreateCall(*builder, unwrap<FunctionType>(FunctionTy), callee, args, Name));
}

	extern "C" LLVMValueRef LLVMSelfhostCreatePointerCast(
	    LLVMBuilderRef Builder, LLVMValueRef Value, LLVMTypeRef DestTy, const char *Name)
	{
	    return wrap(unwrap(Builder)->CreatePointerCast(unwrap(Value), unwrap<Type>(DestTy), Name));
	}

	extern "C" void LLVMSelfhostSetAnyRegCallingConv(LLVMValueRef Inst)
	{
	    if (auto *callBase = dyn_cast<CallBase>(unwrap<Value>(Inst))) {
	        callBase->setCallingConv(CallingConv::AnyReg);
	    }
	}

	extern "C" LLVMTypeRef LLVMSelfhostGetGEPResultElementType(LLVMValueRef Gep)
	{
	    if (auto *gep = dyn_cast<GetElementPtrInst>(unwrap<Value>(Gep))) {
	        return wrap(gep->getResultElementType());
	    }
	    return nullptr;
	}

	extern "C" LLVMValueRef LLVMSelfhostStripInBoundsOffsets(LLVMValueRef Value)
	{
	    return wrap(unwrap(Value)->stripInBoundsOffsets());
	}

	extern "C" LLVMValueRef LLVMSelfhostCreateAtomicCmpXchg(
	    LLVMBuilderRef Builder, LLVMValueRef Ptr, LLVMValueRef Cmp, LLVMValueRef NewVal)
	{
	    auto *builder = unwrap(Builder);
	    return wrap(builder->CreateAtomicCmpXchg(unwrap(Ptr), unwrap(Cmp), unwrap(NewVal), MaybeAlign(),
	        AtomicOrdering::SequentiallyConsistent, AtomicOrdering::SequentiallyConsistent));
	}

	extern "C" LLVMValueRef LLVMSelfhostCreateAtomicRMW(
	    LLVMBuilderRef Builder, unsigned Op, LLVMValueRef Ptr, LLVMValueRef Val)
	{
	    auto *builder = unwrap(Builder);
	    return wrap(builder->CreateAtomicRMW(static_cast<AtomicRMWInst::BinOp>(Op), unwrap(Ptr), unwrap(Val),
	        MaybeAlign(), AtomicOrdering::SequentiallyConsistent));
	}

	extern "C" LLVMValueRef LLVMSelfhostCreateAtomicLoad(
	    LLVMBuilderRef Builder, LLVMTypeRef ValueTy, LLVMValueRef Ptr, unsigned AlignBytes, const char *Name)
	{
	    auto *builder = unwrap(Builder);
	    auto *load = builder->CreateLoad(unwrap<Type>(ValueTy), unwrap(Ptr), Name);
	    load->setAlignment(Align(AlignBytes));
	    load->setAtomic(AtomicOrdering::SequentiallyConsistent);
	    return wrap(load);
	}

	extern "C" LLVMValueRef LLVMSelfhostCreateAtomicStore(
	    LLVMBuilderRef Builder, LLVMValueRef Val, LLVMValueRef Ptr, unsigned AlignBytes)
	{
	    auto *builder = unwrap(Builder);
	    auto *store = builder->CreateStore(unwrap(Val), unwrap(Ptr));
	    store->setAlignment(Align(AlignBytes));
	    store->setAtomic(AtomicOrdering::SequentiallyConsistent);
	    return wrap(store);
	}

extern "C" void LLVMSelfhostInstructionSetMetadata(
    LLVMValueRef Inst, const char *Kind, unsigned KindLen, LLVMMetadataRef Metadata)
{
    if (Inst == nullptr || Metadata == nullptr) {
        return;
    }
    auto *node = cast<MDNode>(unwrap(Metadata));
    auto *value = unwrap<Value>(Inst);
    if (auto *instruction = dyn_cast<Instruction>(value)) {
        instruction->setMetadata(StringRef(Kind, KindLen), node);
        return;
    }
    if (auto *globalObject = dyn_cast<GlobalObject>(value)) {
        globalObject->setMetadata(StringRef(Kind, KindLen), node);
    }
}

extern "C" void LLVMSelfhostInstructionCopyMetadata(LLVMValueRef Dest, LLVMValueRef Src)
{
    if (Dest == nullptr || Src == nullptr) {
        return;
    }
    auto *destValue = unwrap<Value>(Dest);
    auto *srcValue = unwrap<Value>(Src);
    auto *destInst = dyn_cast<Instruction>(destValue);
    auto *srcInst = dyn_cast<Instruction>(srcValue);
    if (destInst == nullptr || srcInst == nullptr) {
        return;
    }
    destInst->copyMetadata(*srcInst);
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderCreateSubroutineType(
    LLVMDIBuilderRef Builder, LLVMMetadataRef *Types, size_t Count, unsigned Flags)
{
    auto *builder = unwrap(Builder);
    std::vector<Metadata*> eltTys;
    eltTys.reserve(Count);
    for (size_t idx = 0; idx < Count; ++idx) {
        eltTys.push_back(Types[idx] == nullptr ? nullptr : unwrap(Types[idx]));
    }
    auto diFlags = static_cast<DINode::DIFlags>(Flags);
    return wrap(builder->createSubroutineType(builder->getOrCreateTypeArray(eltTys), diFlags));
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderCreateFunction(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope,
    const char *Name, size_t NameLen, const char *LinkageName, size_t LinkageNameLen, LLVMMetadataRef File,
    unsigned LineNo, LLVMMetadataRef Ty, unsigned ScopeLine, unsigned Flags, unsigned SPFlags,
    LLVMMetadataRef TParams, LLVMMetadataRef Decl)
{
    auto *builder = unwrap(Builder);
    auto *scope = unwrap<DIScope>(Scope);
    auto *file = unwrap<DIFile>(File);
    auto *type = unwrap<DISubroutineType>(Ty);
    auto diFlags = static_cast<DINode::DIFlags>(Flags);
    auto spFlags = static_cast<DISubprogram::DISPFlags>(SPFlags);
    auto *templateParams = TParams == nullptr ? nullptr : unwrap<MDTuple>(TParams);
    auto *declaration = Decl == nullptr ? nullptr : unwrap<DISubprogram>(Decl);
    return wrap(builder->createFunction(scope, StringRef(Name, NameLen), StringRef(LinkageName, LinkageNameLen),
        file, LineNo, type, ScopeLine, diFlags, spFlags, templateParams, declaration));
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderCreateMethod(LLVMDIBuilderRef Builder, LLVMMetadataRef Scope,
    const char *Name, size_t NameLen, const char *LinkageName, size_t LinkageNameLen, LLVMMetadataRef File,
    unsigned LineNo, LLVMMetadataRef Ty, unsigned VTableIndex, int ThisAdjustment, LLVMMetadataRef VTableHolder,
    unsigned Flags, unsigned SPFlags)
{
    auto *builder = unwrap(Builder);
    auto *scope = unwrap<DIScope>(Scope);
    auto *file = unwrap<DIFile>(File);
    auto *type = unwrap<DISubroutineType>(Ty);
    auto *vtableHolder = VTableHolder == nullptr ? nullptr : unwrap<DIType>(VTableHolder);
    auto diFlags = static_cast<DINode::DIFlags>(Flags);
    auto spFlags = static_cast<DISubprogram::DISPFlags>(SPFlags);
    return wrap(builder->createMethod(scope, StringRef(Name, NameLen), StringRef(LinkageName, LinkageNameLen), file,
        LineNo, type, VTableIndex, ThisAdjustment, vtableHolder, diFlags, spFlags));
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderReplaceArrays(
    LLVMDIBuilderRef Builder, LLVMMetadataRef Composite, LLVMMetadataRef Elements)
{
    auto *builder = unwrap(Builder);
    auto *composite = unwrap<DICompositeType>(Composite);
    auto *elements = Elements == nullptr ? nullptr : unwrap<MDTuple>(Elements);
    builder->replaceArrays(composite, DINodeArray(elements));
    return wrap(composite);
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderCreateArrayType(LLVMDIBuilderRef Builder,
    uint64_t SizeInBits, uint32_t AlignInBits, LLVMMetadataRef Ty, LLVMMetadataRef Subscripts)
{
    auto *builder = unwrap(Builder);
    auto *subscripts = Subscripts == nullptr ? nullptr : unwrap<MDTuple>(Subscripts);
    return wrap(builder->createArrayType(
        SizeInBits, AlignInBits, unwrap<DIType>(Ty), DINodeArray(subscripts)));
}

extern "C" LLVMMetadataRef LLVMSelfhostMDNodeReplaceWithDistinct(LLVMMetadataRef Composite)
{
    auto *composite = unwrap<DICompositeType>(Composite);
    return wrap(MDNode::replaceWithDistinct(TempDICompositeType(composite)));
}

extern "C" LLVMMetadataRef LLVMSelfhostDIBuilderCreateEnumerationType(LLVMDIBuilderRef Builder,
    LLVMMetadataRef Scope, const char *Name, size_t NameLen, LLVMMetadataRef File, unsigned LineNo,
    uint64_t SizeInBits, uint32_t AlignInBits, LLVMMetadataRef *Elements, size_t Count,
    LLVMMetadataRef UnderlyingType, const char *UniqueIdentifier, size_t UniqueIdentifierLen, bool IsScoped)
{
    auto *builder = unwrap(Builder);
    std::vector<Metadata*> elements;
    elements.reserve(Count);
    for (size_t idx = 0; idx < Count; ++idx) {
        elements.push_back(unwrap(Elements[idx]));
    }
    return wrap(builder->createEnumerationType(unwrap<DIScope>(Scope), StringRef(Name, NameLen),
        unwrap<DIFile>(File), LineNo, SizeInBits, AlignInBits, builder->getOrCreateArray(elements),
        unwrap<DIType>(UnderlyingType), StringRef(UniqueIdentifier, UniqueIdentifierLen), IsScoped));
}

extern "C" size_t LLVMSelfhostDICompositeTypeGetElements(
    LLVMMetadataRef Composite, LLVMMetadataRef *Elements, size_t Capacity)
{
    auto elements = unwrap<DICompositeType>(Composite)->getElements();
    size_t count = elements.size();
    size_t outputCount = std::min(count, Capacity);
    for (size_t idx = 0; idx < outputCount; ++idx) {
        Elements[idx] = wrap(elements[idx]);
    }
    return count;
}

extern "C" unsigned LLVMSelfhostDINodeGetTag(LLVMMetadataRef Node)
{
    return unwrap<DINode>(Node)->getTag();
}

extern "C" LLVMMetadataRef LLVMSelfhostDIDerivedTypeGetBaseType(LLVMMetadataRef Type)
{
    return wrap(unwrap<DIDerivedType>(Type)->getBaseType());
}

extern "C" const char *LLVMSelfhostDISubprogramGetLinkageName(LLVMMetadataRef Subprogram, size_t *Length)
{
    StringRef name = unwrap<DISubprogram>(Subprogram)->getLinkageName();
    *Length = name.size();
    return name.data();
}

extern "C" LLVMMetadataRef LLVMSelfhostDILocationGet(LLVMContextRef Context, unsigned Line, unsigned Column,
    LLVMMetadataRef Scope, LLVMMetadataRef InlinedAt, bool IsImplicitCode)
{
    auto *scope = unwrap<Metadata>(Scope);
    auto *inlinedAt = InlinedAt == nullptr ? nullptr : unwrap<DILocation>(InlinedAt);
    return wrap(DILocation::get(*unwrap(Context), Line, Column, scope, inlinedAt, IsImplicitCode));
}

extern "C" LLVMValueRef LLVMSelfhostCreateGCReadStaticAgg(LLVMBuilderRef Builder, LLVMModuleRef Module,
    LLVMTypeRef Type, LLVMValueRef Dest, LLVMValueRef Source, LLVMValueRef Size, LLVMTypeRef SizeType)
{
    return CreateGCStaticAggCall(Builder, Module, Type, Dest, Source, Size, SizeType,
        Intrinsic::cj_gcread_static_struct);
}

extern "C" LLVMValueRef LLVMSelfhostCreateGCWriteStaticAgg(LLVMBuilderRef Builder, LLVMModuleRef Module,
    LLVMTypeRef Type, LLVMValueRef Dest, LLVMValueRef Source, LLVMValueRef Size, LLVMTypeRef SizeType)
{
    return CreateGCStaticAggCall(Builder, Module, Type, Dest, Source, Size, SizeType,
        Intrinsic::cj_gcwrite_static_struct);
}

extern "C" uint64_t LLVMSelfhostGetPrimitiveSizeInBits(LLVMTypeRef Ty)
{
    return unwrap<Type>(Ty)->getPrimitiveSizeInBits().getFixedSize();
}

extern "C" LLVMUseRef LLVMSelfhostGetFirstUse(LLVMValueRef Val)
{
    auto *value = unwrap(Val);
    auto iter = value->use_begin();
    if (iter == value->use_end()) {
        return nullptr;
    }
    return wrap(&*iter);
}

extern "C" LLVMUseRef LLVMSelfhostGetNextUse(LLVMUseRef UseRef)
{
    auto *next = unwrap(UseRef)->getNext();
    if (next) {
        return wrap(next);
    }
    return nullptr;
}

extern "C" LLVMValueRef LLVMSelfhostGetUserInstruction(LLVMUseRef UseRef)
{
    return wrap(dyn_cast<Instruction>(unwrap(UseRef)->getUser()));
}

extern "C" int CJOFVerifyPackageBuffer(const unsigned char *Data, size_t Size)
{
    if (Data == nullptr) {
        return 0;
    }
    flatbuffers::Verifier verifier(Data, Size, CJOF_FB_MAX_DEPTH, CJOF_FB_MAX_TABLES);
    return PackageFormat::VerifyPackageBuffer(verifier) ? 1 : 0;
}

// ---------------------------------------------------------------------------
// LLVM CallGraph C bindings for GenerateBinarySectionInfo.
// Merged in from the former binsecinfo_llvmshim.cpp (0713): keeping the shim as
// two objects meant a missing binsecinfo_llvmshim.o failed the top-level link
// with an error that pointed nowhere near the real cause.
// ---------------------------------------------------------------------------

extern "C" CallGraphWrapperPass *LLVMSelfhostCreateCallGraphWrapperPass(LLVMModuleRef ModuleRef)
{
    auto *callGraph = new CallGraphWrapperPass();
    callGraph->runOnModule(*unwrap(ModuleRef));
    return callGraph;
}

extern "C" void LLVMSelfhostDisposeCallGraphWrapperPass(CallGraphWrapperPass *CallGraph)
{
    delete CallGraph;
}

extern "C" CallGraphNode *LLVMSelfhostCallGraphGetNode(CallGraphWrapperPass *CallGraph, LLVMValueRef FunctionRef)
{
    return (*CallGraph)[unwrap<Function>(FunctionRef)];
}

extern "C" unsigned LLVMSelfhostCallGraphNodeSize(CallGraphNode *Node)
{
    return Node->size();
}

extern "C" CallGraphNode *LLVMSelfhostCallGraphNodeGetCallee(CallGraphNode *Node, unsigned Index)
{
    return (*Node)[Index];
}

extern "C" LLVMValueRef LLVMSelfhostCallGraphNodeGetFunction(CallGraphNode *Node)
{
    return wrap(Node->getFunction());
}

extern "C" int LLVMSelfhostGlobalObjectHasEmptySection(LLVMValueRef GlobalObjectRef)
{
    return unwrap<GlobalObject>(GlobalObjectRef)->getSection().empty() ? 1 : 0;
}
