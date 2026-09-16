#include "Cangjie.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
extern "C" uintptr_t g_cjHeapRangeCount, g_cjHeapRangeStart[], g_cjHeapRangeEnd[];
static unsigned checks, failures;
static void check(bool ok,const char* name) {
    ++checks; failures+=!ok; std::printf("ASSERT unload.%s %s\n",name,ok?"PASS":"FAIL"); std::fflush(stdout);
}
extern "C" void observeRetainedLiteral(const unsigned char* p,int64_t size) {
    const char expected[]="unload-世界";
    bool heap=false;
    for (uintptr_t i=0;i<g_cjHeapRangeCount;i++)
        if ((uintptr_t)p>=g_cjHeapRangeStart[i] && (uintptr_t)p<g_cjHeapRangeEnd[i]) heap=true;
    check(heap,"retained.heap");
    check(p && size==sizeof(expected)-1 && !std::memcmp(p,expected,sizeof(expected)-1),"retained.bytes");
}
static bool task(CJTaskFunc fn) {
    if (!fn) return false;
    auto handle=RunCJTask(fn,nullptr); if (!handle) return false;
    void* result=nullptr; int rc=GetTaskRet(handle,&result); ReleaseHandle(handle); return rc==0;
}
static std::string maps(const std::string& destination) {
    std::ifstream input("/proc/self/maps"); std::ostringstream contents; contents<<input.rdbuf();
    std::ofstream output(destination); output<<contents.str(); return contents.str();
}
int main(int argc,char** argv) {
    if (argc!=4) return 64;
    const char* holder=argv[1]; const char* producer=argv[2]; std::string out=argv[3];
    RuntimeParam param{}; param.coParam.processorNum=1;
    check(InitCJRuntime(&param)==0,"runtime");
    check(LoadCJLibrary(holder)==0,"load.holder");
    check(LoadCJLibrary(producer)==0,"load.producer");
    check(InitCJLibrary(producer)==0,"init.producer");
    auto publish=reinterpret_cast<CJTaskFunc>(FindCJSymbol(producer,"publishRetainedLiteral"));
    auto read=reinterpret_cast<CJTaskFunc>(FindCJSymbol(holder,"readRetainedLiteral"));
    auto collect=reinterpret_cast<CJTaskFunc>(FindCJSymbol(holder,"collectRetainedLiteral"));
    check(publish && read && collect,"actual.symbols");
    if (failures) return 1;
    check(task(publish),"copy.into.heap.field");
    check(task(read),"read.before.unload");
    check(maps(out+"/before.maps").find(producer)!=std::string::npos,"producer.mapped.control");
    check(UnloadCJLibrary(producer)==0,"unload.return");
    publish=nullptr;
    check(maps(out+"/after.maps").find(producer)==std::string::npos,"producer.unmapped");
    check(task(collect),"gc.after.unload");
    check(task(read),"read.after.unload");
    std::printf("UNLOAD_RESULT checks=%u failures=%u\n",checks,failures);
    return failures?1:0;
}
