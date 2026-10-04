// Private observer calibration only; never linked into the product.
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

__attribute__((noinline)) void calibration_begin(void) { __asm__ volatile(""); }
static void receipt(const char *kind, const stack_t *in, const stack_t *old, int rc, int err) {
    printf("RECEIPT {\"kind\":\"%s\",\"rc\":%d,\"errno\":%d,\"in\":", kind, rc, err);
    if (in) printf("{\"ss_sp\":%llu,\"ss_size\":%llu,\"ss_flags\":%d}",
        (unsigned long long)(uintptr_t)in->ss_sp, (unsigned long long)in->ss_size, in->ss_flags);
    else printf("null");
    printf(",\"old\":");
    if (old) printf("{\"ss_sp\":%llu,\"ss_size\":%llu,\"ss_flags\":%d}",
        (unsigned long long)(uintptr_t)old->ss_sp, (unsigned long long)old->ss_size, old->ss_flags);
    else printf("null");
    printf("}\n"); fflush(stdout);
}
int main(int argc, char **argv) {
    {
        printf("LAYOUT {\"stack_size\":%zu,\"ss_sp\":[%zu,%zu],\"ss_size\":[%zu,%zu],\"ss_flags\":[%zu,%zu],\"SS_DISABLE\":%d,\"SS_ONSTACK\":%d,\"SIGSTKSZ\":%d,\"MINSIGSTKSZ\":%d,\"pointer_size\":%zu}\n",
            sizeof(stack_t), offsetof(stack_t, ss_sp), sizeof(((stack_t*)0)->ss_sp),
            offsetof(stack_t, ss_size), sizeof(((stack_t*)0)->ss_size),
            offsetof(stack_t, ss_flags), sizeof(((stack_t*)0)->ss_flags), SS_DISABLE, SS_ONSTACK,
            SIGSTKSZ, MINSIGSTKSZ, sizeof(void*));
        fflush(stdout);
    }
    calibration_begin();
    stack_t old = {0}; errno = 0;
    int rc = sigaltstack(NULL, &old), err = errno;
    receipt("query", NULL, &old, rc, err);
    if (rc || (old.ss_flags & SS_ONSTACK)) return 10;
    void *mem = malloc(SIGSTKSZ * 2);
    if (!mem) return 11;
    stack_t valid = {.ss_sp=mem, .ss_size=SIGSTKSZ * 2, .ss_flags=0}; errno=0;
    rc = sigaltstack(&valid, NULL); err=errno;
    receipt("valid", &valid, NULL, rc, err);
    if (rc) { free(mem); return 12; }
    stack_t invalid = {.ss_sp=mem, .ss_size=0, .ss_flags=0}; errno=0;
    int bad = sigaltstack(&invalid, NULL); err=errno;
    receipt("invalid", &invalid, NULL, bad, err);
    stack_t original_old = old;
    stack_t restore_request = original_old;
    if (original_old.ss_flags & SS_DISABLE) {
        restore_request = valid;
        restore_request.ss_flags = SS_DISABLE;
    }
    printf("RESTORE_STATE ");
    receipt("original_old", NULL, &original_old, 0, 0);
    errno=0;
    rc = sigaltstack(&restore_request, NULL); err=errno;
    receipt("restore", &restore_request, NULL, rc, err);
    if (rc) return 13;
    stack_t after_restore = {0}; errno=0;
    rc = sigaltstack(NULL, &after_restore); err=errno;
    receipt("postquery", NULL, &after_restore, rc, err);
    if (rc || (after_restore.ss_flags & SS_ONSTACK)) return 15;
    if (original_old.ss_flags & SS_DISABLE) {
        if (!(after_restore.ss_flags & SS_DISABLE)) return 16;
    } else if (after_restore.ss_sp != original_old.ss_sp ||
               after_restore.ss_size != original_old.ss_size ||
               after_restore.ss_flags != original_old.ss_flags ||
               after_restore.ss_sp == mem) return 17;
    free(mem);
    puts("SAFE_FREE");
    return bad != 0 ? 0 : 14;
}
