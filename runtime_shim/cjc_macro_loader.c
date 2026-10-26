/* The compiler loads this private bridge into its admitted runtime namespace.
 * Its DT_RPATH is $ORIGIN: the target SDK runtime directory, not the host
 * compiler's execution-library directory.  glibc dlopen uses the calling DSO
 * to select both the namespace and the inherited dependency search path.
 */
#include <dlfcn.h>

__attribute__((visibility("default")))
void *CjcjMacroOpen(const char *path)
{
    /* Keep a real call frame here. A tail call would make the managed caller
     * the dlopen caller and lose both this namespace and this RPATH anchor. */
    void *volatile result = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    return result;
}

__attribute__((visibility("default")))
const char *CjcjMacroError(void)
{
    return dlerror();
}
