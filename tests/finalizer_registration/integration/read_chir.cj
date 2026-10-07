package finalizer_chir_reader

import cjcj::chir.*
import std.core.Box as CoreBox

main(args: Array<String>): Int64 {
    if (args.size != 2) {
        return 2
    }
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let phase = CoreBox<ToCHIRPhase>(ToCHIRPhase.RAW)
    if (!CHIRDeserializer.Deserialize(args[0], builder, phase)) {
        return 2
    }
    let pkg = context.GetCurPackage().getOrThrow()
    if (args[1] == "scalar") {
        var folded = false
        for (line in pkg.ToString().split("\n")) {
            folded = folded || (line.contains("= 41i //") && line.contains("srcCodeIdentifier: answer,"))
        }
        println("TARGET deserialized_scalar_fold=${folded}")
        return if (folded) { 0 } else { 1 }
    }
    var roots: Int64 = 0
    var exits: Int64 = 0
    var registeredExits: Int64 = 0
    for (function in pkg.GetGlobalFunctions()) {
        if (!function.IsConstructor()) {
            continue
        }
        let owner = function.GetParentCustomTypeDef().getOrThrow()
        if (owner.GetPackageName() != "std.core" || owner.GetSrcCodeIdentifier() != "Object") {
            continue
        }
        roots++
        for (block in function.GetBody().getOrThrow().GetBlocks()) {
            var previousRegistration = false
            for (expression in block.GetExpressions()) {
                if (expression.GetExprKind() == ExprKind.EXIT) {
                    exits++
                    if (previousRegistration) {
                        registeredExits++
                    }
                }
                if (let Some(intrinsic) <- (expression as Intrinsic)) {
                    previousRegistration = intrinsic.GetIntrinsicKind() == IntrinsicKind.REGISTER_FINALIZER
                } else {
                    previousRegistration = false
                }
            }
        }
    }
    let passed = roots == 1 && exits > 0 && registeredExits == exits
    println("TARGET deserialized_root_return=${passed} roots=${roots} exits=${exits} registered=${registeredExits}")
    return if (passed) { 0 } else { 1 }
}
