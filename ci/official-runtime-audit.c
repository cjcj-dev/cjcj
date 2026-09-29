// glibc loader audit: check actual mapped runtime before its initializers run.
#define _GNU_SOURCE
#include <link.h>
#include <openssl/sha.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void file_sha256(const char *file, char *digest) {
    int fd = open(file, O_RDONLY);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) || st.st_size <= 0) _exit(87);
    void *bytes = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (bytes == MAP_FAILED) _exit(87);
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(bytes, st.st_size, hash);
    munmap(bytes, st.st_size); close(fd);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) sprintf(digest + i * 2, "%02x", hash[i]);
}

static int matches_identity(const char *exe, const char *identities) {
    if (!identities) _exit(87);
    FILE *list = fopen(identities, "r");
    if (!list) _exit(87);
    char digest[SHA256_DIGEST_LENGTH * 2 + 1], line[128];
    file_sha256(exe, digest);
    int match = 0;
    while (fgets(line, sizeof(line), list)) {
        line[strcspn(line, "\n")] = 0;
        if (!strcmp(line, digest)) { match = 1; break; }
    }
    fclose(list);
    return match;
}

static int official_executable(const char *exe, const char *sdk) {
    static int known = -1;
    if (known < 0) known = (!strncmp(exe, sdk, strlen(sdk)) && exe[strlen(sdk)] == '/') ||
                          matches_identity(exe, getenv("CJCJ_AUDIT_IDENTITIES"));
    return known;
}

// cjc invokes opt through a shell; follow the process ancestry, not just PPID.
static void check_optimizer(void) {
    const char *opt = getenv("CJCJ_AUDIT_OPT");
    if (!opt || !opt[0]) return;
    const char *expected = getenv("CJCJ_AUDIT_OPT_SHA256");
    const char *log = getenv("CJCJ_AUDIT_LOG");
    char exe[PATH_MAX], digest[SHA256_DIGEST_LENGTH * 2 + 1];
    if (!expected || !log || !realpath("/proc/self/exe", exe)) _exit(87);
    file_sha256(exe, digest);
    if (strcmp(exe, opt) && strcmp(digest, expected)) return;
    long pid = getppid();
    int official_parent = 0;
    char ancestor[PATH_MAX] = "none";
    while (pid > 1) {
        char proc[64], parent[PATH_MAX], line[256];
        snprintf(proc, sizeof(proc), "/proc/%ld/exe", pid);
        if (!realpath(proc, parent)) _exit(87);
        if (matches_identity(parent, getenv("CJCJ_AUDIT_COMPILERS"))) {
            official_parent = 1;
            snprintf(ancestor, sizeof(ancestor), "%s", parent);
            break;
        }
        snprintf(proc, sizeof(proc), "/proc/%ld/status", pid);
        FILE *status = fopen(proc, "r");
        if (!status) _exit(87);
        long next = 0;
        while (fgets(line, sizeof(line), status)) {
            if (!strncmp(line, "PPid:", 5)) { next = strtol(line + 5, NULL, 10); break; }
        }
        fclose(status);
        if (next == pid) _exit(87);
        pid = next;
    }
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) _exit(87);
    dprintf(fd, "%s pid=%ld exe=%s sha256=%s official_parent=%d ancestor=%s\n",
            official_parent ? "OFFICIAL_TOOLCHAIN_MISMATCH" : "OPT_LOAD", (long)getpid(), exe, digest, official_parent, ancestor);
    close(fd);
    if (official_parent) {
        dprintf(STDERR_FILENO, "OFFICIAL_TOOLCHAIN_MISMATCH exe=%s official_compiler=%s\n", exe, ancestor);
        _exit(86);
    }
}

unsigned int la_version(unsigned int version) {
    check_optimizer();
    return version < LAV_CURRENT ? version : LAV_CURRENT;
}

unsigned int la_objopen(struct link_map *map, Lmid_t ns, uintptr_t *cookie) {
    (void)ns; (void)cookie;
    const char *name = strrchr(map->l_name, '/');
    name = name ? name + 1 : map->l_name;
    if (!map->l_name[0] || !strcmp(map->l_name, "linux-vdso.so.1")) return 0;
    char exe[PATH_MAX], so[PATH_MAX], digest[SHA256_DIGEST_LENGTH * 2 + 1];
    const char *sdk = getenv("CJCJ_AUDIT_SDK");
    const char *colour = getenv("CJCJ_AUDIT_RUNTIME");
    const char *expected = getenv("CJCJ_AUDIT_SHA256");
    const char *log = getenv("CJCJ_AUDIT_LOG");
    if (!sdk || !colour || !expected || !log || !realpath("/proc/self/exe", exe) ||
        !realpath(map->l_name, so)) _exit(87);
    int official = official_executable(exe, sdk);
    if (!official && strcmp(name, "libcangjie-runtime.so")) return 0;
    file_sha256(so, digest);
    int coloured = !strcmp(so, colour) || !strcmp(digest, expected);
    if (!coloured && strcmp(name, "libcangjie-runtime.so")) return 0;
    int blocked = official && coloured;
    int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) _exit(87);
    dprintf(fd, "%s pid=%ld exe=%s so=%s sha256=%s official=%d coloured=%d\n",
            blocked ? "OFFICIAL_RUNTIME_MISMATCH" : "RUNTIME_LOAD", (long)getpid(), exe, so, digest, official, coloured);
    close(fd);
    if (blocked) {
        dprintf(STDERR_FILENO, "OFFICIAL_RUNTIME_MISMATCH exe=%s so=%s sha256=%s\n", exe, so, digest);
        _exit(86);
    }
    return 0;
}
