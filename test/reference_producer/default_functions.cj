package reference_default_functions

import cjcj::chir.*
import std.collection.*

main(args: Array<String>): Int64 {
    let bchir = BCHIR()
    let pointers = HashMap<String, Int64>()
    bchir.SetMainMangledName("test_main")
    pointers["test_main"] = 900
    if (args.size == 1 && args[0] == "control") {
        bchir.LinkDefaultFunctions(pointers)
        if (bchir.GetDefaultFunctionPointer(BCHIRDefaultFunctionKind.MAIN) != 900 ||
            bchir.GetDefaultFunctionPointer(BCHIRDefaultFunctionKind.THROW_ERROR) != 0) {
            return 1
        }
        println("CONTROL missing_helpers_and_main")
        return 0
    }
    let expected = [
        (BCHIRDefaultFunctionKind.THROW_ARITHMETIC_EXCEPTION, "rt$ThrowArithmeticException"),
        (BCHIRDefaultFunctionKind.THROW_OVERFLOW_EXCEPTION, "rt$ThrowOverflowException"),
        (BCHIRDefaultFunctionKind.THROW_INDEX_OUT_OF_BOUNDS_EXCEPTION, "rt$ThrowIndexOutOfBoundsException"),
        (BCHIRDefaultFunctionKind.THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION, "rt$ThrowNegativeArraySizeException"),
        (BCHIRDefaultFunctionKind.CALL_TO_STRING, "rt$CallToString"),
        (BCHIRDefaultFunctionKind.THROW_ARITHMETIC_EXCEPTION_MSG, "rt$ThrowArithmeticException_msg"),
        (BCHIRDefaultFunctionKind.THROW_OUT_OF_MEMORY_ERROR, "rt$ThrowOutOfMemoryError"),
        (BCHIRDefaultFunctionKind.CHECK_IS_ERROR, "rt$CheckIsError"),
        (BCHIRDefaultFunctionKind.THROW_ERROR, "rt$ThrowError"),
        (BCHIRDefaultFunctionKind.CALL_PRINT_STACK_TRACE, "rt$CallPrintStackTrace"),
        (BCHIRDefaultFunctionKind.CALL_PRINT_STACK_TRACE_ERROR, "rt$CallPrintStackTraceError")
    ]
    for (index in 0..expected.size) {
        pointers[expected[index][1]] = 100 + index
    }
    pointers["rt$RegisterReferenceFinalizer"] = 700
    pointers["rt$RunReferenceHandler"] = 701
    pointers["rt$RunReferenceFinalizers"] = 702
    println("TARGET link_real_default_functions")
    bchir.LinkDefaultFunctions(pointers)
    let cloned = bchir.Clone()
    for (index in 0..expected.size) {
        if (bchir.GetDefaultFunctionPointer(expected[index][0]) != 100 + index ||
            cloned.GetDefaultFunctionPointer(expected[index][0]) != 100 + index) {
            return 1
        }
    }
    if (bchir.GetDefaultFuncPtrs().size != 12 ||
        cloned.GetDefaultFunctionPointer(BCHIRDefaultFunctionKind.MAIN) != 900) {
        return 1
    }
    println("PASS default_function_slots_and_clone")
    return 0
}
