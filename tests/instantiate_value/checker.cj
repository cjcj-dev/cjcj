package instantiate_value_checker

import std.collection.*
import cjcj::chir.*
import cjcj::option.GlobalOptions

// Only constructs checker inputs; all validation is the linked product CheckPackage.
main(args: Array<String>): Int64 {
    let mode = args[0]
    let context = CHIRContext()
    let builder = CHIRBuilder(context)
    let pkg = builder.CreatePackage("instantiate_value_checker")
    let fnTy = context.GetFuncTy(ArrayList<Type>(), context.GetNothingType())
    let interfaceA = builder.CreateClassDef(pkg.GetName(), "A", isClass: false)
    let typeA = context.GetClassTy(interfaceA, ArrayList<Type>())
    interfaceA.SetType(typeA)
    let interfaceB = builder.CreateClassDef(pkg.GetName(), "B", isClass: false)
    let typeB = context.GetClassTy(interfaceB, ArrayList<Type>())
    interfaceB.SetType(typeB)
    let generic = context.GetGenericTy("T")
    generic.SetUpperBounds(ArrayList<Type>([typeA]))
    let callee = builder.CreateFunction(fnTy, "callee", packageName: pkg.GetName())
    let isMixed = mode.startsWith("mixed")
    let isParent = mode.startsWith("parent") || isMixed
    if (isParent) {
        let def = builder.CreateClassDef(pkg.GetName(), "Owner", "Owner")
        def.AddGenericTypeParam(generic)
        def.SetType(context.GetClassTy(def, ArrayList<Type>([generic])))
        callee.EnableAttr(Attribute.STATIC)
        def.AddMethod(callee)
        callee.SetOuterDeclaredOrExtendedDef(def)
    } else {
        callee.AddGenericTypeParam(generic)
    }
    if (isMixed) {
        let functionGeneric = context.GetGenericTy("U")
        functionGeneric.SetUpperBounds(ArrayList<Type>([typeB]))
        callee.AddGenericTypeParam(functionGeneric)
    }
    let caller = builder.CreateFunction(fnTy, "caller", packageName: pkg.GetName())
    let body = builder.CreateBlockGroup(caller)
    caller.InitBody(body)
    let block = builder.CreateBlock(body)
    body.SetEntryBlock(block)
    let actuals = ArrayList<Type>()
    if (mode != "empty") {
        let badParent = mode.endsWith("bad") && mode != "mixed-function-bad"
        if (mode.endsWith("intersection")) {
            let actual = context.GetGenericTy("S")
            actual.SetUpperBounds(ArrayList<Type>([typeA, typeB]))
            actuals.add(actual)
        } else {
            actuals.add(if (badParent) { typeB } else { typeA })
        }
        if (isMixed) {
            actuals.add(if (mode == "mixed-function-bad") { typeA } else { typeB })
        }
    }
    if (mode == "arity") { actuals.add(typeA) }
    let inst = builder.CreateGetInstantiateValue(fnTy, callee, actuals, block)
    if (mode != "control") { block.AppendExpression(inst) }
    block.AppendExpression(builder.CreateExit(None, block))
    println("INPUT bodies=${pkg.GetGlobalFuncsWithBody().size} " +
        "expressions=${block.GetExpressionsNum()} exprIsValue=${(inst as Value).isSome()}")
    let observed = CHIRChecker(pkg, GlobalOptions(), builder).CheckPackage(
        ArrayList<CHIRCheckerRule>([CHIRCheckerRule.CHECK_FUNC_BODY]))
    let expected = !(mode.endsWith("bad") || mode == "empty" || mode == "arity")
    println("TARGET mode=${mode} observed=${observed} expected=${expected}")
    return if (observed == expected) { 0 } else { 1 }
}
