foreign { func literalHugeInput(): Int64 }
main(): Int64 {
    let memory = Array<UInt8>(unsafe { literalHugeInput() }, repeat: 0)
    return memory.size
}
