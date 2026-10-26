#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

extern int CJCJ_EnsureAltSignalStack(void);
extern int __real_sigaltstack(const stack_t*, stack_t*);
extern void __real_free(void*);
extern void* __real_calloc(size_t, size_t);
extern int __real_pthread_setspecific(pthread_key_t, const void*);

static _Thread_local int fault;
static _Thread_local int calls;
static _Thread_local int slot = -1;
static pthread_barrier_t ready, releaseWorkers;
static void* installed[2];
static int freed[2], restored[2];
static stack_t observations[2];
static long tids[2];
static const char* mode;

int __wrap_sigaltstack(const stack_t* next, stack_t* old)
{
    ++calls;
    if (fault == 1 && next == NULL) { errno = EIO; return -1; }
    if (fault == 2 && next != NULL) { errno = EACCES; return -1; }
    if (fault == 3 && next == NULL) {
        *old = (stack_t){.ss_sp = (void*)(uintptr_t)1, .ss_size = 1, .ss_flags = SS_ONSTACK};
        return 0;
    }
    int rc = __real_sigaltstack(next, old);
    if (slot >= 0 && next != NULL && rc == 0 && (next->ss_flags & SS_DISABLE)) ++restored[slot];
    return rc;
}

void __wrap_free(void* p)
{
    if (slot >= 0 && p != NULL && p == installed[slot]) {
        stack_t current;
        assert(__real_sigaltstack(NULL, &current) == 0);
        assert((current.ss_flags & SS_DISABLE) || current.ss_sp != p);
        ++freed[slot];
    }
    __real_free(p);
}

void* __wrap_calloc(size_t n, size_t size)
{
    if (fault == 4) return NULL;
    return __real_calloc(n, size);
}
int __wrap_pthread_setspecific(pthread_key_t key, const void* value)
{
    if (fault == 5) return EAGAIN;
    return __real_pthread_setspecific(key, value);
}

static void* worker(void* arg)
{
    slot = (int)(intptr_t)arg;
    tids[slot] = syscall(SYS_gettid);
    stack_t initial;
    assert(__real_sigaltstack(NULL, &initial) == 0);
    assert(initial.ss_flags & SS_DISABLE);
    if (!strcmp(mode, "preserve")) {
        void* external = malloc(1024 * 1024);
        assert(external);
        stack_t next = {.ss_sp = external, .ss_size = 1024 * 1024};
        assert(__real_sigaltstack(&next, NULL) == 0);
        assert(CJCJ_EnsureAltSignalStack() == 0);
        assert(__real_sigaltstack(NULL, &observations[slot]) == 0);
        assert(observations[slot].ss_sp == external && observations[slot].ss_size == next.ss_size);
        pthread_barrier_wait(&ready);
        pthread_barrier_wait(&releaseWorkers);
        assert(__real_sigaltstack(&initial, NULL) == 0);
        free(external);
        return NULL;
    }
    if (!strcmp(mode, "errors")) {
        const int errors[] = {0, EIO, EACCES, 0, ENOMEM, EAGAIN};
        /* Allocation/key errors must run before the first successful allocation. */
        const int order[] = {1, 3, 4, 5, 2};
        for (size_t i = 0; i < sizeof(order)/sizeof(order[0]); ++i) {
            fault = order[i]; calls = 0;
            assert(CJCJ_EnsureAltSignalStack() == errors[fault]);
            if (fault == 3) assert(calls == 1); /* Active-stack branch: no install. */
            printf("ERROR_ARM tid=%ld fault=%d result=%d\n", tids[slot], fault, errors[fault]);
        }
        fault = 0;
    }
    assert(CJCJ_EnsureAltSignalStack() == 0);
    assert(__real_sigaltstack(NULL, &observations[slot]) == 0);
    assert(!(observations[slot].ss_flags & SS_DISABLE));
    assert(observations[slot].ss_sp && observations[slot].ss_size >= 8192);
    installed[slot] = observations[slot].ss_sp;
    /* Reentry must keep this thread's allocation. */
    assert(CJCJ_EnsureAltSignalStack() == 0);
    stack_t again;
    assert(__real_sigaltstack(NULL, &again) == 0);
    assert(again.ss_sp == installed[slot]);
    pthread_barrier_wait(&ready);
    pthread_barrier_wait(&releaseWorkers);
    return NULL; /* Real pthread exit invokes the product key destructor. */
}

int main(int argc, char** argv)
{
    assert(argc == 2); mode = argv[1];
    assert(!strcmp(mode, "owned") || !strcmp(mode, "preserve") || !strcmp(mode, "errors"));
    assert(pthread_barrier_init(&ready, NULL, 3) == 0);
    assert(pthread_barrier_init(&releaseWorkers, NULL, 3) == 0);
    pthread_t threads[2];
    for (intptr_t i=0;i<2;++i) assert(pthread_create(&threads[i], NULL, worker, (void*)i) == 0);
    pthread_barrier_wait(&ready);
    assert(tids[0] != tids[1]);
    uintptr_t a=(uintptr_t)observations[0].ss_sp, b=(uintptr_t)observations[1].ss_sp;
    printf("LIVE_STACKS mode=%s tid0=%ld sp0=%p size0=%zu tid1=%ld sp1=%p size1=%zu\n", mode,
           tids[0], observations[0].ss_sp, observations[0].ss_size,
           tids[1], observations[1].ss_sp, observations[1].ss_size);
    fflush(stdout);
    assert(a + observations[0].ss_size <= b || b + observations[1].ss_size <= a);
    pthread_barrier_wait(&releaseWorkers);
    for (int i=0;i<2;++i) assert(pthread_join(threads[i], NULL) == 0);
    for (int i=0;i<2;++i) {
        assert(freed[i] == (strcmp(mode,"preserve") != 0));
        assert(restored[i] == (strcmp(mode,"preserve") != 0));
    }
    printf("THREAD_EXIT mode=%s freed=%d,%d restored=%d,%d\n",mode,freed[0],freed[1],restored[0],restored[1]);
    return 0;
}
