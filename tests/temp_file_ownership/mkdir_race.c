/* Linux-only test interposer. Run only the owned fixture ELF with this library.
 * The managed Directory.exists check has already returned false when mkdir is
 * reached. A separate process wins creation here; no runtime/source is patched.
 * The fork child uses only raw system calls and never enters managed code.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static _Atomic int used;

int mkdir(const char *path, mode_t mode)
{
    const char *root = getenv("TEMP_OWNERSHIP_ROOT");
    const char *enabled = getenv("TEMP_OWNERSHIP_RACE");
    char prefix[PATH_MAX], sentinel[PATH_MAX], record[PATH_MAX];
    if (root && enabled && !strcmp(enabled, "1") &&
        snprintf(prefix, sizeof(prefix), "%s/tmp/cangjie-tmp-", root) < (int)sizeof(prefix) &&
        !strncmp(path, prefix, strlen(prefix)) && !strchr(path + strlen(prefix), '/') &&
        atomic_exchange(&used, 1) == 0) {
        struct stat st;
        errno = 0;
        int absent = lstat(path, &st) == -1 && errno == ENOENT;
        if (!absent || snprintf(sentinel, sizeof(sentinel), "%s/sentinel", path) >= (int)sizeof(sentinel) ||
            snprintf(record, sizeof(record), "%s/contended-path", root) >= (int)sizeof(record)) {
            dprintf(2, "RACE_SETUP_ERROR absent=%d\n", absent);
            _exit(92);
        }
        size_t path_len = strlen(path);
        pid_t child = (pid_t)syscall(SYS_fork);
        if (child < 0) {
            dprintf(2, "RACE_SETUP_ERROR fork errno=%d\n", errno);
            _exit(93);
        }
        if (child == 0) {
            int rc = 0;
            if (syscall(SYS_mkdir, path, mode) != 0) rc = 1;
            int fd = (int)syscall(SYS_openat, AT_FDCWD, sentinel, O_WRONLY|O_CREAT|O_EXCL, 0600);
            if (fd < 0 || syscall(SYS_write, fd, "other-process", 13) != 13) rc = 2;
            if (fd >= 0) syscall(SYS_close, fd);
            fd = (int)syscall(SYS_openat, AT_FDCWD, record, O_WRONLY|O_CREAT|O_EXCL, 0600);
            if (fd < 0 || syscall(SYS_write, fd, path, path_len) != (long)path_len) rc = 3;
            if (fd >= 0) syscall(SYS_close, fd);
            syscall(SYS_exit, rc);
            __builtin_unreachable();
        }
        int status = -1;
        pid_t waited;
        do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
        if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            dprintf(2, "RACE_SETUP_ERROR child=%d status=%d\n", child, status);
            _exit(93);
        }
        int result = (int)syscall(SYS_mkdir, path, mode);
        int saved_errno = errno;
        dprintf(2, "RACE_WINDOW parent=%d child=%d absent=%d mkdir=%d errno=%d path=%s\n",
                getpid(), child, absent, result, saved_errno, path);
        errno = saved_errno;
        return result;
    }
    return (int)syscall(SYS_mkdir, path, mode);
}
