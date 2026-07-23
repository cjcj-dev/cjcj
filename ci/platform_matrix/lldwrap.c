#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#define REAL_LLD "ld.lld-real.exe"
#else
#include <limits.h>
#include <unistd.h>
#define REAL_LLD "ld.lld-real"
#endif

static const char bad_name[] = "cjcj::cjc.exe";
static const char good_name[] = "cjcj.exe";

static int rewrite(char *text)
{
    int changed = 0;
    char *match;
    while ((match = strstr(text, bad_name)) != NULL) {
        size_t tail = strlen(match + sizeof(bad_name) - 1) + 1;
        memcpy(match, good_name, sizeof(good_name) - 1);
        memmove(match + sizeof(good_name) - 1, match + sizeof(bad_name) - 1, tail);
        changed = 1;
    }
    return changed;
}

static int rewrite_rsp(const char *path)
{
    FILE *file = fopen(path, "rb");
    long size;
    char *content;
    if (!file || fseek(file, 0, SEEK_END) || (size = ftell(file)) < 0 || fseek(file, 0, SEEK_SET)) return -1;
    content = malloc((size_t)size + 1);
    if (!content || fread(content, 1, (size_t)size, file) != (size_t)size) { fclose(file); free(content); return -1; }
    fclose(file);
    content[size] = '\0';
    if (!rewrite(content)) { free(content); return 0; }
    file = fopen(path, "wb");
    if (!file || fwrite(content, 1, strlen(content), file) != strlen(content) || fclose(file)) { free(content); return -1; }
    free(content);
    return 1;
}

int main(int argc, char **argv)
{
    char self[4096], real[4096];
    char *slash;
    int i;
#ifdef _WIN32
    DWORD length = GetModuleFileNameA(NULL, self, sizeof(self));
    if (!length || length >= sizeof(self)) { fputs("lldwrap: cannot locate executable\n", stderr); return 127; }
#else
    ssize_t length = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (length < 0 || (size_t)length >= sizeof(self) - 1) { perror("lldwrap: readlink"); return 127; }
    self[length] = '\0';
#endif
    slash = strrchr(self, '/');
#ifdef _WIN32
    { char *backslash = strrchr(self, '\\'); if (!slash || (backslash && backslash > slash)) slash = backslash; }
#endif
    if (!slash) { fputs("lldwrap: invalid executable path\n", stderr); return 127; }
    *slash = '\0';
    if (snprintf(real, sizeof(real), "%s/%s", self, REAL_LLD) >= (int)sizeof(real)) return 127;
    for (i = 1; i < argc; ++i) {
        if (argv[i][0] == '@') {
            if (rewrite_rsp(argv[i] + 1) < 0) { fprintf(stderr, "lldwrap: cannot rewrite %s: %s\n", argv[i] + 1, strerror(errno)); return 127; }
        } else {
            rewrite(argv[i]);
        }
    }
    argv[0] = real;
#ifdef _WIN32
    /* _exec* detaches on Windows (the caller would see the wrapper exit before
     * the real linker finishes), so run the child with _spawnv(_P_WAIT) and
     * hand its exit code back. The CRT joins argv with spaces without quoting,
     * so re-quote arguments that would otherwise be split. */
    for (i = 1; i < argc; ++i) {
        if (argv[i][0] == '\0' || strpbrk(argv[i], " \t") != NULL) {
            size_t len = strlen(argv[i]);
            char *quoted = malloc(len + 3);
            if (!quoted) { fputs("lldwrap: out of memory\n", stderr); return 127; }
            quoted[0] = '"';
            memcpy(quoted + 1, argv[i], len);
            quoted[len + 1] = '"';
            quoted[len + 2] = '\0';
            argv[i] = quoted;
        }
    }
    {
        intptr_t status = _spawnv(_P_WAIT, real, (const char *const *)argv);
        if (status < 0) { fprintf(stderr, "lldwrap: cannot execute %s: %s\n", real, strerror(errno)); return 127; }
        return (int)status;
    }
#else
    execv(real, argv);
    fprintf(stderr, "lldwrap: cannot execute %s: %s\n", real, strerror(errno));
    return 127;
#endif
}
