import aor_regression.*

main(args: Array<String>): Int64 {
    if (args.size != 1) { return 64 }
    let ok = match (args[0]) {
        case "none" => checkNone()
        case "some" => checkSome()
        case "controls" => checkControls()
        case _ => false
    }
    if (!ok) { return 1 }
    println("AOR_CASE_PASS ${args[0]}")
    return 0
}
