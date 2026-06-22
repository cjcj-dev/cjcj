main() {
    let s = "中文"
    println(s.size)
    println(s == "中文")
    println("中" == "\u{4e2d}")
    let r: Rune = r'中'
    match (r) { case r'\u{4e2d}' => println(true); case _ => println(false) }
}
