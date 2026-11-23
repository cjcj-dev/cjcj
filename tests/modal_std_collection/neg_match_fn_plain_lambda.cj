package modalcollmatchneg

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

// A non-exclave lambda cannot build its @local! result from an external local parameter:
// `Some(s)` takes an external argument and the result is an internal value of the lambda's region.
exclave func collect<R>(src: Array<R> @local!, transform: ((R @local!) -> Option<R> @local!) @local?): Int64 {
    var out: Array<R> @local! = Array<R>(src.size, repeat: src[0])
    var j = 0
    for (i in 0..src.size) {
        match (transform(src[i])) {
            case Some(v) =>
                out[j] = v
                j++
            case None => continue
        }
    }
    j
}

main(): Int64 {
    let src: Array<Item> @local! = [Item() @local!, Item() @local!, Item() @local!]
    let n = collect<Item>(src, { s: Item @local! => Some(s) })
    if (n == 3) { 0 } else { 1 }
}
