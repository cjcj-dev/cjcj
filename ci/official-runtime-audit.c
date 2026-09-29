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

unsigned int la_version(unsigned int version) { return version < LAV_CURRENT ? version : LAV_CURRENT; }

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
    int official = !strncmp(exe, sdk, strlen(sdk)) && exe[strlen(sdk)] == '/';
    if (!official && strcmp(name, "libcangjie-runtime.so")) return 0;
    int fd = open(so, O_RDONLY);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) || st.st_size <= 0) _exit(87);
    void *bytes = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (bytes == MAP_FAILED) _exit(87);
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(bytes, st.st_size, hash);
    munmap(bytes, st.st_size); close(fd);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) sprintf(digest + i * 2, "%02x", hash[i]);
    int coloured = !strcmp(so, colour) || !strcmp(digest, expected);
    if (!coloured && strcmp(name, "libcangjie-runtime.so")) return 0;
    int blocked = official && coloured;
    fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
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
