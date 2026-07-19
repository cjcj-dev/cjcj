// 冒烟样本 02:泛型类 + 泛型自由函数 + 显式实例化。
// 验证泛型实例化(R-C 结构化键、mangler、单态化)这条历史高危链路。
// 期望输出:42 hi 7
class Box<T> {
    let v: T
    init(x: T) { v = x }
    func get(): T { v }
}

func firstOf<T>(xs: Array<T>): T { xs[0] }

main(): Int64 {
    let b = Box<Int64>(42)
    let s = Box<String>("hi")
    println("${b.get()} ${s.get()} ${firstOf<Int64>([7, 8, 9])}")
    return 0
}
