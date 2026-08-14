#include <cstddef>

// Link-only compatibility for the negative arm: the pre-slice shim still
// supplies CJOFVerifyPackageBuffer, while these weak definitions model the
// removed read implementation and let the identical Cangjie probe run.
extern "C" __attribute__((weak)) void *CJOFPackageViewOpen(const unsigned char *, size_t)
{
    return nullptr;
}

extern "C" __attribute__((weak)) void CJOFPackageViewClose(void *)
{
}

extern "C" __attribute__((weak)) const unsigned char *CJOFPackageViewGetFullPkgName(const void *, size_t *)
{
    return nullptr;
}

extern "C" __attribute__((weak)) size_t CJOFPackageViewGetDependencyCount(const void *)
{
    return 0;
}

extern "C" __attribute__((weak)) const unsigned char *CJOFPackageViewGetDependencyName(
    const void *, size_t, size_t *)
{
    return nullptr;
}
