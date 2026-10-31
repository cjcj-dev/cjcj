#include <stdint.h>
#include <stddef.h>
typedef struct __attribute__((aligned(16))) { uint8_t x; } Aligned;
typedef struct __attribute__((packed, aligned(64))) { uint8_t tag; uint32_t value; } PackedAligned;
typedef struct { uint8_t prefix; Aligned inner; } Outer;
typedef struct { uint8_t prefix; PackedAligned inner; } PackedOuter;
typedef struct __attribute__((packed)) { uint8_t prefix; Aligned inner; } DenseOuter;
_Static_assert(sizeof(Outer) == 32 && offsetof(Outer, inner) == 16, "outer layout");
_Static_assert(sizeof(PackedOuter) == 128 && offsetof(PackedOuter, inner) == 64, "packed inner layout");
_Static_assert(sizeof(DenseOuter) == 17 && offsetof(DenseOuter, inner) == 1, "dense layout");
int32_t c_layout(Outer a, PackedOuter b, DenseOuter c)
{
    return a.prefix == 1 && a.inner.x == 7 && b.prefix == 2 && b.inner.tag == 3 &&
           b.inner.value == 1000 && c.prefix == 2 && c.inner.x == 7;
}
Outer c_outer(void) { return (Outer){5, {9}}; }
