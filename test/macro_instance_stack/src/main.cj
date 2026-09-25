package cjcj_test::macro_instance_stack

import cjcj::macro_pkg.{CallRuntime, OpenSymbolTable, RuntimeInit}
import std.collection.*
import std.env.getVariable
import std.fs.File

main(): Int64 {
    let lib = getVariable("CJCJ337_LIB") ?? ""
    let outp = getVariable("CJCJ337_OUT") ?? ""
    if (lib == "" || outp == "") {
        println("FAIL missing CJCJ337_LIB or CJCJ337_OUT")
        return 1
    }
    let opened = OpenSymbolTable(lib)
    if (!opened.opened) {
        println("FAIL probe not opened")
        return 1
    }
    let empty = ArrayList<(String, String)>()
    let callDefault = CallRuntime(opened, "InitCJRuntime", empty)
    if (callDefault != 0) {
        println("FAIL callrt default rc=${callDefault}")
        return 1
    }
    let withEnv = ArrayList<(String, String)>()
    withEnv.add(("cjStackSize", "128kb"))
    let callEnv = CallRuntime(opened, "InitCJRuntime", withEnv)
    if (callEnv != 0) {
        println("FAIL callrt env rc=${callEnv}")
        return 1
    }
    let started = RuntimeInit.GetInstance().InitRuntime(lib)
    if (!started) {
        println("FAIL InitRuntime returned false")
        return 1
    }
    let text = String.fromUtf8(File.readFrom(outp))
    println("OBSERVED")
    println(text)
    if (!text.contains("instance th=")) {
        println("FAIL instance path not entered")
        return 1
    }
    if (!text.contains("instance th=65536 co=4096 proc=1 n=1")) {
        println("FAIL TARGET instance th/co")
        return 2
    }
    println("PASS TARGET instance th=65536 co=4096 proc=1")
    if (!text.contains("callrt th=")) {
        println("FAIL callrt path not entered")
        return 1
    }
    if (!text.contains("callrt th=65536 co=4096 proc=0 n=1")) {
        println("FAIL TARGET callrt default")
        return 3
    }
    if (!text.contains("callrt th=65536 co=128 proc=0 n=2")) {
        println("FAIL TARGET callrt env")
        return 3
    }
    println("PASS TARGET callrt")
    return 0
}
