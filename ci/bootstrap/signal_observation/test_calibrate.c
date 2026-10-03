/* Offline API simulation executes the actual private helper; not native evidence. */
#include <signal.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
static int scenario, calls, freed, request_ok;
static void *allocated;
static stack_t original, current;
static int fake_stack(const stack_t *in, stack_t *out) {
    calls++;
    if (!in) {
        if (calls == 5 && scenario == 3) { errno=12; return -1; }
        *out = current;
        if (calls == 5 && scenario == 4) out->ss_flags=0;
        if (calls == 5 && scenario == 5) out->ss_flags |= SS_ONSTACK;
        return 0;
    }
    if (calls == 3) { errno=12; return -1; }
    if (calls == 4) {
        request_ok = scenario == 1 ?
            in->ss_sp == original.ss_sp && in->ss_size == original.ss_size && in->ss_flags == original.ss_flags :
            in->ss_sp == allocated && in->ss_size == SIGSTKSZ*2 && in->ss_flags == SS_DISABLE;
        if (scenario == 2) { errno=12; return -1; }
        if (scenario == 0 && !in->ss_size) { errno=12; return -1; }
    }
    current=*in; return 0;
}
static void *fake_malloc(size_t n) { allocated=malloc(n); return allocated; }
static void fake_free(void *p) { if (p==allocated) freed++; free(p); }
#define sigaltstack fake_stack
#define malloc fake_malloc
#define free fake_free
#define main helper_main
#include "calibrate.c"
#undef main
#undef free
int main(int argc, char **argv) {
    scenario=atoi(argv[1]);
    original=(stack_t){.ss_sp=(void*)0x1000,.ss_size=SIGSTKSZ,.ss_flags=0};
    current=scenario==1 ? original : (stack_t){.ss_flags=SS_DISABLE};
    int rc=helper_main(0,NULL);
    int pass = scenario<=1 ? rc==0 && request_ok && freed==1 && calls==5 :
        rc!=0 && freed==0 && calls==(scenario==2 ? 4 : 5);
    printf("TARGET scenario=%d rc=%d calls=%d request_ok=%d freed=%d pass=%d\n",scenario,rc,calls,request_ok,freed,pass);
    return !pass;
}
