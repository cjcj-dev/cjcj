// LLVM CallGraph C bindings for GenerateBinarySectionInfo.

#include <llvm-c/Core.h>

#include "llvm/Analysis/CallGraph.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalObject.h"
#include "llvm/IR/Module.h"

using namespace llvm;

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
