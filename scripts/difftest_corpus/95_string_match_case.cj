main(): Int64 {
    var out: Int64 = 0
    let text = "."
    match (text) {
        case "." => out = 1
        case "," => out = 2
        case "=>" => out = 3
        case "Int64" => out = 4
        case "while" => out = 5
        case _ => out = 9
    }
    println(out)
    return 0
}
