#include <stdint.h>
#include <stdarg.h>

typedef struct { uint64_t x, y; } Pair;
typedef struct { uint64_t x, y, z; } Ret;
typedef struct __attribute__((packed)) { uint8_t tag; uint32_t value; } Packed;
typedef struct { uint8_t a, b, c, d, e, f, g, h, i; } Nine;
typedef struct { float x, y; } FloatPair;
typedef struct { float x, y, z, w; } FloatFour;
typedef struct {} Empty;

Ret c_sret(uint64_t a, uint64_t b, uint64_t c, uint64_t d, Pair p)
{
    return (Ret){p.x, p.y, a + b + c + d};
}
uint64_t c_pair(Pair p) { return p.x + p.y; }
uint64_t c_packed(Packed p) { return p.tag + p.value; }
Packed c_packed_ret(void) { return (Packed){3, 1000}; }
uint64_t c_nine(Nine p) { return p.a + p.i; }
int32_t c_sse(double a, double b, double c, double d, double e, double f, double g,
              FloatPair p, FloatFour q)
{
    return a == 1 && b == 2 && c == 3 && d == 4 && e == 5 && f == 6 && g == 7 &&
           p.x == 8 && p.y == 9 && q.x == 10 && q.y == 11 && q.z == 12 && q.w == 13;
}
int32_t c_vararg(Empty e, int32_t tag, ...)
{
    (void)e;
    va_list ap;
    va_start(ap, tag);
    double x = va_arg(ap, double);
    int y = va_arg(ap, int);
    int u8 = va_arg(ap, int), u16 = va_arg(ap, int);
    int boolean = va_arg(ap, int), i16 = va_arg(ap, int);
    va_end(ap);
    return tag == 42 && x == 1.5 && y == -3 && u8 == 250 && u16 == 60000 && boolean == 1 && i16 == -30000;
}
extern Ret cj_sret(uint64_t, uint64_t, uint64_t, uint64_t, Pair);
extern uint64_t cj_packed(Packed);
extern uint64_t cj_nine(Nine);
extern int32_t cj_sse(double, double, double, double, double, double, double, FloatPair, FloatFour);
int32_t c_callbacks(void)
{
    Ret r = cj_sret(1, 2, 3, 4, (Pair){17, 23});
    if (r.x != 17 || r.y != 23 || r.z != 10) return 1;
    if (cj_packed((Packed){3, 1000}) != 1003) return 2;
    if (cj_nine((Nine){1, 0, 0, 0, 0, 0, 0, 0, 9}) != 10) return 3;
    if (!cj_sse(1, 2, 3, 4, 5, 6, 7, (FloatPair){8, 9}, (FloatFour){10, 11, 12, 13})) return 4;
    return 0;
}
