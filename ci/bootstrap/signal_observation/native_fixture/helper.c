/* Source preparation only: Darwin arm64, no retries and no product copies. */
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define SEED_SIZE 65536u
static void *seed;
static uint64_t seed_tid;
static int bridge_checked;
static int callback_rc;
static int (*managed_callback)(void);

static void record(const char *step, int rc, int saved_errno, const stack_t *s) {
    uint64_t tid = 0;
    int tid_rc = pthread_threadid_np(NULL, &tid);
    printf("FIXTURE {\"step\":\"%s\",\"rc\":%d,\"errno\":%d,"
           "\"tid_rc\":%d,\"thread_id\":%" PRIu64 ",\"sp\":%" PRIuPTR
           ",\"size\":%zu,\"flags\":%d}\n", step, rc, saved_errno,
           tid_rc, tid, s ? (uintptr_t)s->ss_sp : 0,
           s ? s->ss_size : 0, s ? s->ss_flags : 0);
    fflush(stdout);
}

/* Called from the managed callback, after the actual native-to-managed bridge.
 * This checks the input, without invoking or replacing the product function. */
int fixture_verify_seed(void) {
    stack_t current = {0};
    uint64_t tid = 0;
    int trc = pthread_threadid_np(NULL, &tid);
    if (trc != 0) { record("bridge-thread", trc, 0, NULL); return 31; }
    errno = 0;
    int rc = sigaltstack(NULL, &current);
    int saved_errno = errno;
    record("bridge-query", rc, saved_errno, &current);
    if (bridge_checked || tid != seed_tid || rc != 0 ||
        current.ss_sp != seed || current.ss_size != SEED_SIZE ||
        (current.ss_flags & (SS_ONSTACK | SS_DISABLE))) return 32;
    bridge_checked = 1;
    return 0;
}

static void *native_entry(void *unused) {
    (void)unused;
    stack_t current = {0};
    int trc = pthread_threadid_np(NULL, &seed_tid);
    if (trc != 0) { record("seed-thread", trc, 0, NULL); callback_rc = 33; return NULL; }
    errno = 0;
    int rc = sigaltstack(NULL, &current);
    int saved_errno = errno;
    record("initial-query", rc, saved_errno, &current);
    if (rc != 0 || (current.ss_flags & SS_ONSTACK)) { callback_rc = 34; return NULL; }
    stack_t input = {.ss_sp = seed, .ss_size = SEED_SIZE, .ss_flags = 0};
    errno = 0;
    rc = sigaltstack(&input, NULL);
    saved_errno = errno;
    record("seed-install", rc, saved_errno, &input);
    if (rc != 0) { callback_rc = 35; return NULL; }
    errno = 0;
    rc = sigaltstack(NULL, &current);
    saved_errno = errno;
    record("seed-query", rc, saved_errno, &current);
    if (rc != 0 || current.ss_sp != seed || current.ss_size != SEED_SIZE ||
        (current.ss_flags & (SS_ONSTACK | SS_DISABLE))) { callback_rc = 36; return NULL; }
    callback_rc = managed_callback(); /* exactly one CFunc callback */
    record("callback-return", callback_rc, 0, NULL);
    if (!bridge_checked && callback_rc == 0) callback_rc = 37;
    return NULL;
}

int fixture_run(int (*callback)(void)) {
    if (!callback || seed) return 38; /* no reentry/fallback */
    int rc = posix_memalign(&seed, 16, SEED_SIZE);
    record("allocate", rc, 0, NULL); /* POSIX APIs return the error directly */
    if (rc != 0) return 39;
    managed_callback = callback;
    pthread_t thread;
    rc = pthread_create(&thread, NULL, native_entry, NULL);
    record("pthread-create", rc, 0, NULL);
    if (rc != 0) { free(seed); seed = NULL; return 40; }
    rc = pthread_join(thread, NULL);
    record("pthread-join", rc, 0, NULL);
    if (rc != 0) return 41; /* keep seed: thread might still be alive */
    free(seed); /* only after successful join; no SS_DISABLE */
    seed = NULL;
    return callback_rc;
}
