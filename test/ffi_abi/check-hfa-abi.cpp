#include "llvm/IR/Module.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"
#include <fstream>
#include <string>
#include <vector>
using namespace llvm;

// Compare register classes with the real Clang C ABI, allowing the equivalent
// LLVM struct/array spelling of an HFA and i128/two-i64 integer containers.
static void slots(Type *type, std::vector<std::string> &out) {
    if (type->isVoidTy()) return;
    if (auto *a = dyn_cast<ArrayType>(type)) {
        for (uint64_t i=0;i<a->getNumElements();++i) slots(a->getElementType(),out);
    } else if (auto *s=dyn_cast<StructType>(type)) {
        for (auto *field:s->elements()) slots(field,out);
    } else if (type->isFloatingPointTy()) {
        out.push_back("FP"+std::to_string(type->getPrimitiveSizeInBits().getFixedValue()));
    } else if (type->isIntegerTy()) {
        for (unsigned i=0;i<type->getIntegerBitWidth();i+=64) out.push_back("GPR");
    } else if (type->isPointerTy()) out.push_back("INDIRECT");
    else out.push_back("UNSUPPORTED");
}
static std::string shape(Function &function, bool result) {
    std::vector<std::string> parts;
    if (result) {
        bool sret=false;
        for (auto &arg:function.args()) sret |= arg.hasStructRetAttr();
        if (sret) parts.push_back("SRET"); else slots(function.getReturnType(),parts);
    } else for (auto &arg:function.args()) if (!arg.hasStructRetAttr()) slots(arg.getType(),parts);
    std::string out;
    for (auto &part:parts) out+=part+",";
    return out.empty()?"VOID":out;
}
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    LLVMContext context;SMDiagnostic error;
    auto c=parseIRFile(argv[1],error,context),cj=parseIRFile(argv[2],error,context);
    if(!c||!cj){error.print(argv[0],errs());return 2;}
    if(c->getTargetTriple().find("aarch64")!=0||cj->getTargetTriple().find("aarch64")!=0)return 2;
    std::ifstream names(argv[3]);std::string name;unsigned cases=0,checks=0,failures=0;
    while(std::getline(names,name)){
        if(name.empty())continue;++cases;
        auto *oracle=c->getFunction("c_echo_"+name);
        if(!oracle){errs()<<"missing C oracle "<<name<<'\n';return 2;}
        for(const auto &prefix:{"c_echo_","cj_echo_","cj_call_","cj_ret_","cj_values_"}){
            auto *function=cj->getFunction(std::string(prefix)+name);
            auto *expected=std::string(prefix)=="cj_values_"?c->getFunction("cj_values_"+name):oracle;
            if(!function||!expected){errs()<<"missing actual consumer "<<prefix<<name<<'\n';return 2;}
            for(bool result:{false,true}){
                if(!result&&std::string(prefix)=="cj_ret_")continue;
                const auto want=shape(*expected,result),got=shape(*function,result);++checks;
                if(want!=got||got.find("UNSUPPORTED")!=std::string::npos){
                    ++failures;outs()<<"ABI_MISMATCH "<<prefix<<name<<(result?" return":" args")<<" expected="<<want<<" actual="<<got<<'\n';
                }
            }
        }
        outs()<<"CASE "<<name<<" C.args="<<shape(*oracle,false)<<" C.return="<<shape(*oracle,true)<<'\n';
    }
    outs()<<"SUMMARY cases="<<cases<<" checks="<<checks<<" mismatches="<<failures<<'\n';
    return !cases||!checks?2:failures?1:0;
}
