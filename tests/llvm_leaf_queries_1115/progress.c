#define _POSIX_C_SOURCE 200809L
#include <stdatomic.h>
#include <time.h>

/* Test-only ordinary native wait. It never calls CJ or holds CJ references. */
static _Atomic int started;
static _Atomic int complete;
void leaf_control_reset(void) {
    atomic_store(&started, 0);
    atomic_store(&complete, 0);
}
static int wait_flag(_Atomic int *flag) {
    const struct timespec delay = {0, 1000000};
    for (int i = 0; i < 10000; ++i) {
        if (atomic_load(flag)) return 1;
        nanosleep(&delay, 0);
    }
    return 0;
}
int leaf_control_wait_started(void) { return wait_flag(&started); }
void leaf_control_complete(void) { atomic_store(&complete, 1); }
int leaf_control_wait_gc(void) {
    atomic_store(&started, 1);
    return wait_flag(&complete);
}
