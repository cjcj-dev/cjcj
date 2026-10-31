var finalized: Int64 = 0

func explicitUnit(): Any {
    let value: Any = try { throw Exception("explicit") } catch (_: Exception) { () }
    return value
}
func emptyUnit(): Any {
    let value: Any = try { throw Exception("empty") } catch (_: Exception) {}
    return value
}
func normalValue(): Any {
    let value: Any = try { 42 } catch (_: Exception) { () }
    return value
}
func caughtValue(): Any {
    let value: Any = try { throw Exception("value") } catch (_: Exception) { 43 }
    return value
}
func catchReturn(): Any {
    let value: Any = try { throw Exception("return") } catch (_: Exception) { return 44 }
    return value
}
func catchThrow(): Any {
    let value: Any = try { throw Exception("first") } catch (_: Exception) { throw Exception("second") }
    return value
}
func unitFinally(): Any {
    let value: Any = try { throw Exception("finally") } catch (_: Exception) { () }
        finally { finalized++ }
    return value
}
main(args: Array<String>): Int64 {
    if (args.size != 1) { return 64 }
    if (args[0] == "unit") {
        if (!(explicitUnit() is Unit)) { return 1 }
        println("CATCH_ASSERT explicit_unit")
        if (!(emptyUnit() is Unit)) { return 2 }
        println("CATCH_ASSERT empty_unit")
        if (!(unitFinally() is Unit) || finalized != 1) { return 3 }
        println("CATCH_ASSERT unit_finally_once")
    } else if (args[0] == "control") {
        if ((normalValue() as Int64) != Some(42)) { return 4 }
        println("CATCH_ASSERT normal_value")
        if ((caughtValue() as Int64) != Some(43)) { return 5 }
        println("CATCH_ASSERT caught_value")
        if ((catchReturn() as Int64) != Some(44)) { return 6 }
        println("CATCH_ASSERT catch_return")
        var rejected = false
        try { catchThrow() } catch (e: Exception) { rejected = e.message == "second" }
        if (!rejected) { return 7 }
        println("CATCH_ASSERT catch_throw")
    } else { return 64 }
    println("CATCH_CASE_PASS ${args[0]}")
    return 0
}
