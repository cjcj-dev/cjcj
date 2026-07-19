// 冒烟样本 05:C FFI(foreign func + unsafe 调用)。
// 验证 @C 外部函数声明、unsafe 块、与 libc 的链接(abs 来自 libc)。
// 期望输出:7
foreign func abs(i: Int32): Int32

main(): Int64 {
    unsafe { println(abs(-7)) }
    return 0
}
