#include <cstddef>

// Link with -Wl,--wrap=CJOFPackageViewOpen to prove that the official arm can
// be disabled while the byte-level manual arm remains live.
extern "C" void *__wrap_CJOFPackageViewOpen(const unsigned char *, size_t)
{
    return nullptr;
}
