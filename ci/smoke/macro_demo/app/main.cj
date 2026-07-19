// 冒烟样本 06(宏)第二部分:宏消费方。
// 编译方式:cjc main.cj --import-path <mymacros 所在目录> -o app
// @Twice(println("tick")) 展开为两条 println,故运行输出两行 tick。
// 期望输出(两行):tick / tick
import mymacros.*

main(): Int64 {
    @Twice(println("tick"))
    return 0
}
