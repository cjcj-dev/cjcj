package rt.demangle

main() {
    let prefix = RtLit(42)
    let suffix = RtLit(43)
    let arena = RtArenaCreate()
    let text = prefix.WithArena(arena) + suffix
    let out = RtToCString(text)
    RtNativeFree(out)
    RtArenaDestroy(arena)
}
