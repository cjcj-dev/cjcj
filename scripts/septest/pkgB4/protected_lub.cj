package pkgA4.child

import pkgA4.*

func pick(flag: Bool) {
    let x = if (flag) { makeA() } else { makeB() }
    println(x.value())
}

main() {
    pick(false)
}
