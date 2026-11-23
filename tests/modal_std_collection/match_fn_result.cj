package modalcollmatch

public class Item {
    public init() {}
    public exclave init(this @local!) {}
}

// Same shape as ArrayList.filterMap: the value bound from a call through a function-typed
// parameter has that function's @local! result mode, so `out[j] = v` uses the local setter.
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
    // The parameter is an external local and `Some(s)` builds the @local! result, so the lambda
    // returns it through an exclave (upstream TypeCheckModal.cpp IsExternalLocal rule 1/2,
    // CheckCallExpr, CheckReturnModalType); neg_match_fn_plain_lambda keeps the plain body.
    let n = collect<Item>(src, { s: Item @local! => exclave { Some(s) } })
    if (n == 3) { 0 } else { 1 }
}
