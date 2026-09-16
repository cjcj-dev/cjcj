#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <stdlib.h>
extern uintptr_t g_cjHeapRangeCount;
extern uintptr_t g_cjHeapRangeStart[];
extern uintptr_t g_cjHeapRangeEnd[];
static unsigned failures, checks;
static const unsigned char e0[] = "abc-世界", e1[] = "世界", e2[] = {'A',0,'B'}, e3[] = "import-世界", e4[] = "abc", e5[] = "世界abc";
static const unsigned char *expected[] = {e0,e1,e2,e3,e4,e5};
static const size_t sizes[] = {sizeof e0-1,sizeof e1-1,sizeof e2,sizeof e3-1,sizeof e4-1,sizeof e5-1};
static int in_heap(const void *p) {
    uintptr_t a=(uintptr_t)p;
    for (uintptr_t i=0;i<g_cjHeapRangeCount;i++)
        if (a>=g_cjHeapRangeStart[i] && a<g_cjHeapRangeEnd[i]) return 1;
    return 0;
}
int32_t checkLiteralBytes(const unsigned char *p, int64_t n, int32_t id) {
    int heap=in_heap(p);
    int bytes=id>=0 && id<6 && n==(int64_t)sizes[id] && p && memcmp(p,expected[id],sizes[id])==0;
    printf("ASSERT literal.%d.heap=%s bytes=%s size=%" PRId64 " address=%p\n",id,heap?"PASS":"FAIL",bytes?"PASS":"FAIL",n,(const void*)p);
    failures+=!heap+!bytes; checks+=2;
    return heap && bytes;
}
int32_t checkLiteralShare(uintptr_t a, uintptr_t b, int64_t delta) {
    int ok=b-a==(uintptr_t)delta;
    printf("ASSERT literal.share=%s delta=%" PRId64 "\n",ok?"PASS":"FAIL",delta);
    failures+=!ok; checks++;
    return ok;
}
int32_t checkOrdinaryAggregate(int64_t a, int64_t b) {
    int ok=a==7 && b==9;
    printf("ASSERT ordinary.aggregate=%s\n",ok?"PASS":"FAIL");
    failures+=!ok; checks++;
    return ok;
}
int32_t literalAssertionsDone(void) {
    const char *maps=getenv("LITERAL_MAPS");
    if (maps) {
        FILE *in=fopen("/proc/self/maps","r"), *out=fopen(maps,"w");
        if (in && out) { char line[4096]; while (fgets(line,sizeof line,in)) fputs(line,out); }
        if (in) fclose(in);
        if (out) fclose(out);
    }
    int native=!in_heap(e0);
    printf("ASSERT native.bytes=%s\n",native?"PASS":"FAIL");
    failures+=!native; checks++;
    printf("LITERAL_RESULT checks=%u failures=%u\n",checks,failures);
    return failures?1:0;
}
