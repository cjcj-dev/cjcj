// 冒烟样本 01:最小可执行程序。验证 driver + codegen + runtime 启动链路。
// 期望输出(见 run_smoke.sh 的 EXPECT 表):hello from cjcj
main(): Int64 {
    println("hello from cjcj")
    return 0
}
