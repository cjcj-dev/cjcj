#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>
extern int __real_CJCJ_EnsureAltSignalStack(void);
int __wrap_CJCJ_EnsureAltSignalStack(void)
{
    stack_t before, after;
    if (sigaltstack(NULL, &before) != 0) abort();
    long tid = syscall(SYS_gettid);
    int rc = getenv("CJCJ_TEST_SIGNAL_ERROR") ? EIO : __real_CJCJ_EnsureAltSignalStack();
    if (sigaltstack(NULL, &after) != 0 || syscall(SYS_gettid) != tid) abort();
    fprintf(stderr, "ALTSTACK_CALL tid=%ld before=%p/%zu/%d after=%p/%zu/%d rc=%d\n",
        tid, before.ss_sp, before.ss_size, before.ss_flags, after.ss_sp, after.ss_size, after.ss_flags, rc);
    return rc;
}
