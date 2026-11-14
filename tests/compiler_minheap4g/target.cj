foreign func CJCJ_CheckActualHeap(): Int32
main(): Int64 {
    return unsafe { Int64(CJCJ_CheckActualHeap()) }
}
