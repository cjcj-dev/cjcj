// Consumer-side observation only: actual concurrent macro bodies and carriers.
#include <atomic>
#include <cstdio>
#include <unistd.h>
#include <sys/syscall.h>
static std::atomic<int> active{0}, peak{0}, entered{0}, left{0};
extern "C" void CleanerMacroEnter() {
    int n = ++active; ++entered;
    int old = peak.load(); while (old < n && !peak.compare_exchange_weak(old, n)) {}
    std::fprintf(stderr, "MACRO_BODY_BEGIN tid=%ld active=%d\n", syscall(SYS_gettid), n);
    usleep(100000);
}
extern "C" void CleanerMacroLeave() {
    ++left; int n = --active;
    std::fprintf(stderr, "MACRO_BODY_END tid=%ld active=%d\n", syscall(SYS_gettid), n);
}
__attribute__((destructor)) static void FinishProbe() {
    std::fprintf(stderr, "MACRO_PROBE_FINI entered=%d left=%d active=%d peak=%d\n",
        entered.load(), left.load(), active.load(), peak.load());
}
