#include <stdint.h>
typedef struct __attribute__((aligned(16))) { uint8_t x; } ArrayElement;
typedef struct { uint8_t prefix; ArrayElement values[2]; uint8_t tail; } ArrayBox;
extern ArrayBox cj_array(ArrayBox);
ArrayBox c_array(ArrayBox p) { p.values[0].x++; p.values[1].x+=2; return p; }
int32_t c_array_callbacks(void) {
    ArrayBox p={3,{{7},{7}},9};
    ArrayBox q=cj_array(p);
    return q.prefix==3 && q.values[0].x==8 && q.values[1].x==9 && q.tail==9;
}
