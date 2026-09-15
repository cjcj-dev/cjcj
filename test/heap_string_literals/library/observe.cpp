#include "Cangjie.h"
#include "PackageInitTest.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <thread>
#include <fstream>
#include <string>
static std::atomic<int> inits[2], reads[2], gcDone;
static int checks, failures;
static void check(bool ok, const char* name) {
    ++checks; failures += !ok;
    std::printf("ASSERT library.%s %s\n", name, ok ? "PASS" : "FAIL"); std::fflush(stdout);
}
extern "C" int64_t recordLibraryInit(int32_t tag) { return ++inits[tag]; }
extern "C" int32_t recordLibraryBytes(const unsigned char* p, int64_t n, int32_t tag) {
    const char* expected = tag ? "control-世界" : "plugin-世界";
    bool ok = n == static_cast<int64_t>(std::strlen(expected)) && p && !std::memcmp(p, expected, n);
    check(ok, tag ? "control.bytes" : "probe.bytes"); ++reads[tag]; return ok ? 0 : 1;
}
extern "C" void recordLibraryGC() { ++gcDone; }
template<class F> static bool await(F f) {
    auto end = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (!f()) {
        if (std::chrono::steady_clock::now() >= end) return false;
        std::this_thread::yield();
    }
    return true;
}
static bool run(CJTaskFunc fn, void* arg=nullptr) {
    if (!fn) return false;
    auto handle = RunCJTask(fn, arg); if (!handle) return false;
    void* result=nullptr; auto rc=GetTaskRet(handle, &result); ReleaseHandle(handle);
    return rc == 0;
}
static void resetDone(void* ptr) { ++*static_cast<int*>(ptr); }
extern "C" int exerciseLibrary(const char* probe, const char* control, bool concurrent) {
    check(LoadCJLibrary(probe)==0, "load.probe");
    check(LoadCJLibrary(control)==0, "load.control");
    auto packageAddr = reinterpret_cast<void*(*)()>(FindCJSymbol(probe,"literalProbePackage"));
    auto unitAddr = reinterpret_cast<void*(*)()>(FindCJSymbol(probe,"literalProbeUnit"));
    auto resetAddr = reinterpret_cast<void*(*)()>(FindCJSymbol(probe,"literalProbeReset"));
    auto read = reinterpret_cast<CJTaskFunc>(FindCJSymbol(probe,"libraryRead"));
    auto controlRead = reinterpret_cast<CJTaskFunc>(FindCJSymbol(control,"controlRead"));
    auto collect = reinterpret_cast<CJTaskFunc>(FindCJSymbol(control,"libraryGC"));
    check(packageAddr && unitAddr && resetAddr && read && controlRead && collect, "symbols");
    if (failures) return 1;
    using Arm = bool(*)(const void*,const void*,uint32_t);
    auto arm = reinterpret_cast<Arm>(dlsym(RTLD_DEFAULT,"MRT_PackageInitArmCompletePause"));
    auto reached = reinterpret_cast<bool(*)()>(dlsym(RTLD_DEFAULT,"MRT_PackageInitCompletePauseReached"));
    auto release = reinterpret_cast<void(*)()>(dlsym(RTLD_DEFAULT,"MRT_PackageInitReleaseCompletePause"));
    if (concurrent) {
        check(arm && reached && release, "pause.exports"); if (failures) return 1;
        check(arm(packageAddr(),unitAddr(),0), "pause.armed");
    }
    check(InitCJLibrary(control)==0, "control.init");
    check(run(controlRead), "control.task");
    check(inits[1]==1, "control.once");
    if (std::getenv("LITERAL_FAIL_BODY")) {
        int first=InitCJLibrary(probe);
        check(first!=0, "failure.original.returned");
        check(inits[0]==0 && reads[0]==0, "failure.no.consumer");
        std::puts("FAILURE_RETRY entering actual InitCJLibrary"); std::fflush(stdout);
        int retry=InitCJLibrary(probe);
        check(false, "failure.retry.must.abort70");
        std::printf("FAILURE_RETRY unexpected return=%d\n",retry);
        return 1;
    }
    if (concurrent) {
        check(!reached(), "pause.exact.identity");
        std::atomic<bool> ownerDone{false}, waiterDone{false}, waiterStarted{false};
        int ownerRc=-1, waiterRc=-1;
        std::thread owner([&]{ ownerRc=InitCJLibrary(probe); ownerDone=true; });
        bool stopped=await([&]{return reached();}); check(stopped, "owner.before.complete");
        if (!stopped) { release(); owner.join(); return 1; }
        std::thread waiter([&]{ waiterStarted=true; waiterRc=InitCJLibrary(probe); waiterDone=true; });
        check(await([&]{return waiterStarted.load();}), "waiter.started");
        // A runtime read-only waiter observation may be supplied by #646. A
        // started native thread alone is deliberately not a completion proof.
        using Waiting = bool(*)(const void*,const void*,uint32_t);
        auto waiting = reinterpret_cast<Waiting>(dlsym(RTLD_DEFAULT,"MRT_PackageInitHasWaiter"));
        if (waiting) {
            bool observed=await([&]{return waiterDone.load() || waiting(packageAddr(),unitAddr(),0);});
            check(observed && !waiterDone && waiting(packageAddr(),unitAddr(),0), "waiter.inside.begin");
        }
        else std::puts("OBSERVATION waiter.inside.begin UNAVAILABLE");
        check(run(collect), "gc.task.while.parked");
        check(gcDone==1, "gc.completed.while.parked");
        check(!ownerDone && !waiterDone, "no.return.before.complete");
        check(inits[0]==0 && reads[0]==0, "no.consumer.before.complete");
        release(); owner.join(); waiter.join();
        check(ownerRc==0 && waiterRc==0, "both.init.return");
        check(run(read) && run(read), "both.read.tasks");
    } else {
        check(InitCJLibrary(probe)==0, "first.init");
        check(run(read), "first.read.task");
    }
    check(InitCJLibrary(probe)==0, "repeat.init");
    check(inits[0]==1, "ordinary.body.once");
    check(run(read), "repeat.read.task");
    int resets=0; struct { void(*callback)(void*); void* context; } param{resetDone,&resets};
    check(run(reinterpret_cast<CJTaskFunc>(resetAddr()),&param), "reset.task");
    check(resets==1, "reset.callback");
    check(run(read), "reset.read.task");
    check(run(collect), "gc.after.reset.task");
    check(run(read), "gc.after.reset.read.task");
    if (const char* maps=std::getenv("LITERAL_MAPS")) {
        std::ifstream from("/proc/self/maps"); std::ofstream to(maps); to << from.rdbuf();
    }
    std::printf("LIBRARY_RESULT checks=%d failures=%d\n",checks,failures);
    return failures ? 1 : 0;
}
