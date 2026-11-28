import std.collection.ArrayList

private func getHalf(items: ArrayList<String> @local?): Int64 {
    match (items.get(0)) {
        case Some(s) => s.size
        case None => -1
    }
}

main(): Int64 {
    let items: ArrayList<String> @local! = ArrayList<String>() @local!
    let value: String @local! = "modal"
    items.add(value)
    let full = match (items.get(0)) {
        case Some(s) => s.size
        case None => -1
    }
    if (full == 5 && getHalf(items) == 5) { 0 } else { 1 }
}
