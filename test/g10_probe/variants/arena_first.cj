package rt.demangle

main() {
    let arena = RtArenaCreate()
    let text = RtLit(42).WithArena(arena) + RtLit(43)
    let out = RtToCString(text)
    RtNativeFree(out)
    RtArenaDestroy(arena)
}
