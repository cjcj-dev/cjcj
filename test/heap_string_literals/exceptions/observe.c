#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern uintptr_t g_cjHeapRangeCount, g_cjHeapRangeStart[], g_cjHeapRangeEnd[];
static unsigned checks, failures;
int64_t literalZeroInput(void) { return 0; }
int64_t literalHugeInput(void) { return INT64_MAX; }
static int heap(const void *p) {
    for (uintptr_t i=0;i<g_cjHeapRangeCount;i++)
        if ((uintptr_t)p>=g_cjHeapRangeStart[i] && (uintptr_t)p<g_cjHeapRangeEnd[i]) return 1;
    return 0;
}
void checkExceptionLiteral(const unsigned char *p,int64_t n) {
    static const char expected[]="Divided by zero!";
    int content=p && n==sizeof(expected)-1 && !memcmp(p,expected,sizeof(expected)-1);
    int managed=heap(p);
    printf("ASSERT exception.literal.heap=%s bytes=%s size=%ld\n",managed?"PASS":"FAIL",content?"PASS":"FAIL",n);
    checks+=2; failures+=!managed+!content;
}
int32_t exceptionAssertionsDone(void) {
    static const char native[]="metadata/native control";
    int ok=!heap(native); ++checks; failures+=!ok;
    printf("ASSERT exception.native.control=%s\n",ok?"PASS":"FAIL");
    printf("EXCEPTION_RESULT checks=%u failures=%u\n",checks,failures);
    return failures ? 1 : 0;
}
