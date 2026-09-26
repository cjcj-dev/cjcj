#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void note(const char *tag, uint64_t th, uint64_t co, uint32_t proc, uint64_t n) {
    const char *path = getenv("CJCJ337_OUT");
    FILE *f;
    if (path == NULL || path[0] == '\0') {
        return;
    }
    f = fopen(path, "a");
    if (f == NULL) {
        return;
    }
    fprintf(f, "%s th=%llu co=%llu proc=%u n=%llu\n", tag,
        (unsigned long long)th, (unsigned long long)co, proc, (unsigned long long)n);
    fclose(f);
}

static uint64_t g_inst_n;
static uint64_t g_call_n;

void *CJCJ_MRT_InstanceNew(void *param) {
    uint64_t th = 0;
    uint64_t co = 0;
    uint32_t proc = 0;
    if (param != NULL) {
        memcpy(&th, param, 8);
        memcpy(&co, (char *)param + 8, 8);
        memcpy(&proc, (char *)param + 16, 4);
    }
    g_inst_n++;
    note("instance", th, co, proc, g_inst_n);
    return &g_inst_n;
}

int CJCJ_MRT_InstanceRunTask(void *handle) {
    (void)handle;
    return 0;
}

int CJCJ_MRT_InstanceStop(void *handle) {
    (void)handle;
    return 0;
}

int ReleaseHandle(void *handle) {
    (void)handle;
    return 0;
}

int InitCJRuntime(void *param) {
    uint64_t th = 0;
    uint64_t co = 0;
    uint32_t proc = 0;
    if (param != NULL) {
        memcpy(&th, (char *)param + 136, 8);
        memcpy(&co, (char *)param + 144, 8);
        memcpy(&proc, (char *)param + 152, 4);
    }
    g_call_n++;
    note("callrt", th, co, proc, g_call_n);
    return 0;
}
