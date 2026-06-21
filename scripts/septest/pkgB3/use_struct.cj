package pkgB3

import pkgA3.*

main() {
    let step = Step(8)
    let factor: Count = 5
    println(step.next() + step.scaled(factor))
}
