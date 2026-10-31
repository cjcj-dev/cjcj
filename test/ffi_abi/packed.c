#include <stdint.h>
#include <stdalign.h>
typedef struct __attribute__((packed)) { uint8_t tag; uint32_t value; } Packed;
static _Alignas(16) Packed storage;
Packed *c_storage(void) {
    storage=(Packed){3,1000}; return &storage;
}
int32_t c_check(void) {
    return ((uintptr_t)((unsigned char *)&storage+1)%4)!=0 && storage.tag==5 && storage.value==1011;
}
extern uint32_t cj_packed_write(Packed *);
extern Packed cj_packed_return(Packed);
Packed c_packed_roundtrip(Packed p) { return cj_packed_return(p); }
typedef Packed (*PackedFn)(Packed);
PackedFn c_get_packed(void) { return c_packed_roundtrip; }
int32_t c_packed_callbacks(void) {
    Packed *p=c_storage();
    if(cj_packed_write(p)!=1000 || !c_check()) return 0;
    Packed q=cj_packed_return(*p); return q.tag==5 && q.value==1024;
}
