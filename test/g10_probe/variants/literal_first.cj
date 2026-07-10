package rt.demangle

main() {
    let prefix = RtLit(42)
    let arena = RtArenaCreate()
    let text = prefix.WithArena(arena) + RtLit(43)
    let out = RtToCString(text)
    RtNativeFree(out)
    RtArenaDestroy(arena)
}
