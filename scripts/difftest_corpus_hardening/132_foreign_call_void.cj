foreign func strlen(s: CString): UIntNative

main() {
    unsafe {
        let cs = LibC.mallocCString("hello")
        let n = strlen(cs)
        println(n)
        LibC.free(cs)
    }
}
