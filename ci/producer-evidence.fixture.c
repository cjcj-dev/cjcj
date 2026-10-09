// Controlled ELF for apparatus qualification. Never a cjcj compiler substitute in production.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>

static void cancelled_zero(int signal_number) { (void)signal_number; _exit(0); }

static void copy(const char *from, const char *to) {
    FILE *in = fopen(from, "rb"), *out = fopen(to, "wb");
    if (!in || !out) exit(91);
    int ch; while ((ch = fgetc(in)) != EOF) fputc(ch, out);
    fclose(in); fclose(out);
    chmod(to, 0755);
}

int main(int argc, char **argv) {
    const char *mode = getenv("EVIDENCE_TEST_MODE");
    // Install before publishing readiness to the parent.
    if (mode && !strcmp(mode, "cancel-zero")) signal(SIGTERM, cancelled_zero);
    if (mode && !strcmp(mode, "cancel-ignore")) signal(SIGTERM, SIG_IGN);
    const char *trace = getenv("EVIDENCE_TEST_TRACE");
    if (trace) {
        FILE *f = fopen(trace, "a");
        if (!f) return 92;
        char cwd[4096]; getcwd(cwd, sizeof(cwd));
        fprintf(f, "cwd=%s argv0=%s argc=%d\n", cwd, argv[0], argc);
        for (int i = 1; i < argc; i++) fprintf(f, "arg=%s\n", argv[i]);
        fclose(f);
    }
    if (mode && (!strcmp(mode, "cancel-zero") || !strcmp(mode, "cancel-ignore"))) {
        for (;;) pause();
    }
    if (mode && !strcmp(mode, "unlink")) { unlink(argv[0]); if (argc > 1) unlink(argv[1]); return 0; }
    if (mode && !strcmp(mode, "fail")) { fputs("CONTROLLED_CHILD_FAILURE\n", stderr); return 7; }
    if (mode && !strcmp(mode, "signal")) { raise(SIGSEGV); return 93; }
    if (mode && !strcmp(mode, "wait")) { sleep(30); return 0; }
    if (mode && !strcmp(mode, "handled")) { signal(SIGSEGV, SIG_IGN); raise(SIGSEGV); puts("AFTER_SIGNAL"); return 0; }
    const char *directory = NULL, *output = NULL, *source = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--output-dir") && i + 1 < argc) directory = argv[++i];
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) output = argv[++i];
        else if (strstr(argv[i], ".cj")) source = argv[i];
    }
    if (directory && output) {
        char file[4096]; snprintf(file, sizeof(file), "%s/%s", directory, output);
        FILE *f = fopen(file, "w"); if (!f) return 94; fputs("archive", f); fclose(f);
        snprintf(file, sizeof(file), "%s/objc.%s.cjo", directory, strstr(output, "internal") ? "internal" : "lang");
        f = fopen(file, "w"); if (!f) return 95; fputs("declaration", f); fclose(f); return 0;
    }
    if (source) {
        const char *link = getenv("EVIDENCE_TEST_LINK_TEXT");
        if (link) fprintf(stderr, "%s\n", link);
        if (output) copy(argv[0], output); return 0;
    }
    if (strstr(argv[0], "01_hello")) puts("hello from cjcj");
    else if (strstr(argv[0], "02_generics")) puts("42 hi 7");
    else if (strstr(argv[0], "03_closures")) puts("30");
    else if (strstr(argv[0], "04_iface_enum")) puts("12.560000 3");
    else if (strstr(argv[0], "05_ffi")) puts("7");
    else if (strstr(argv[0], "/app")) puts("tick\ntick");
    else puts("CONTROLLED_ELF");
    return 0;
}
