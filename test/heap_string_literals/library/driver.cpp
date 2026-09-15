#include "Cangjie.h"
#include <cstdio>
extern "C" int exerciseLibrary(const char*,const char*,bool);
int main(int argc,char** argv) {
    if (argc != 4) return 64;
    RuntimeParam param{}; param.coParam.processorNum=1;
    int rc=InitCJRuntime(&param);
    std::printf("InitCJRuntime rc=%d processors=1\n",rc); std::fflush(stdout);
    if (rc) return rc;
    return exerciseLibrary(argv[1],argv[2],argv[3][0]=='1');
}
