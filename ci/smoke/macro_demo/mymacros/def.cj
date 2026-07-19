// 冒烟样本 06(宏)第一部分:宏定义包。
// 编译方式:cjc --compile-macro def.cj  →  产出 lib-macro_mymacros.so + mymacros.cjo
// 该步骤要求宏引擎在进程内加载运行时(<cjc>/../runtime 布局),是 macro-eval-needs-install-layout
// 记忆里的历史高危点:裸二进制缺 ../runtime 会静默跳过宏展开。
macro package mymacros

import std.ast.*

// @Twice(expr) 将其参数复制两份,顺序展开。
public macro Twice(input: Tokens): Tokens {
    return quote($input; $input)
}
