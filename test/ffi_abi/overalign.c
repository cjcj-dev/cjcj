#include <stdint.h>
#include <stdarg.h>
typedef struct __attribute__((aligned(16))) { uint8_t x; } A;
typedef struct { A a; } Box;
typedef struct __attribute__((aligned(16))) { float x; } AF;
typedef struct { AF a; } FBox;
uint64_t c_take(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,Box p,uint64_t tail) { return a+b+c+d+e+p.a.x+tail; }
uint64_t c_stack(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,Box p,uint64_t tail) { return a+b+c+d+e+f+p.a.x+tail; }
Box c_box(Box p) { p.a.x++; return p; }
FBox c_fbox(FBox p) { p.a.x+=2; return p; }
typedef uint64_t (*Take)(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,Box,uint64_t);
typedef uint64_t (*Stack)(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,Box,uint64_t);
typedef Box (*BoxFn)(Box);
typedef FBox (*FBoxFn)(FBox);
Take c_get_take(void) { return c_take; }
Stack c_get_stack(void) { return c_stack; }
BoxFn c_get_box(void) { return c_box; }
FBoxFn c_get_fbox(void) { return c_fbox; }
int32_t c_variadic(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,...) {
    va_list ap; va_start(ap,e); Box p=va_arg(ap,Box); uint64_t tail=va_arg(ap,uint64_t); va_end(ap);
    return a+b+c+d+e==15 && p.a.x==7 && tail==99;
}
int32_t c_varstack(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,...) {
    va_list ap; va_start(ap,f); Box p=va_arg(ap,Box); uint64_t tail=va_arg(ap,uint64_t); va_end(ap);
    return a+b+c+d+e+f==21 && p.a.x==7 && tail==99;
}
extern uint64_t cj_take(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,Box,uint64_t);
extern uint64_t cj_stack(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,Box,uint64_t);
extern Box cj_box(Box);
extern FBox cj_fbox(FBox);
int32_t c_over_callbacks(void) {
    Box p={{7}}; FBox f={{1.5f}};
    if(cj_take(1,2,3,4,5,p,99)!=121) return 1;
    if(cj_stack(1,2,3,4,5,6,p,99)!=127) return 2;
    if(cj_box(p).a.x!=8) return 3;
    if(cj_fbox(f).a.x!=3.5f) return 4;
    return 0;
}
