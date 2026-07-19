// 冒烟样本 04:接口(<:)+ 动态分派 + 代数枚举 + 递归 match 模式匹配。
// 验证 sema 类型检查、vtable/接口分派、enum 构造与解构。
// 期望输出:12.560000 3
interface Shape { func area(): Float64 }

class Circle <: Shape {
    let r: Float64
    init(r: Float64) { this.r = r }
    public func area(): Float64 { 3.14 * r * r }
}

enum Tree { Leaf | Node(Int64, Tree, Tree) }

func sum(t: Tree): Int64 {
    match (t) {
        case Leaf => 0
        case Node(v, l, r) => v + sum(l) + sum(r)
    }
}

main(): Int64 {
    let c: Shape = Circle(2.0)
    let t = Tree.Node(1, Tree.Node(2, Tree.Leaf, Tree.Leaf), Tree.Leaf)
    println("${c.area()} ${sum(t)}")
    return 0
}
