import cjcj::driver.{StandardLibName, StandardLibMap}
import cjcj::utils.FileUtil
import cjcj::mangle.{GetOptPkgName, IsStdPackageMangleCode, Demangle, CJMangledCompression}

func check(name: String, actual: String, expected: String): Int64 {
    let ok = actual == expected
    println("${if (ok) { "PASS" } else { "FAIL" }} ${name} actual=${actual} expected=${expected}")
    return if (ok) { 0 } else { 1 }
}

main(): Int64 {
    var failures: Int64 = 0
    for ((pkg, code, lib) in [("std.concurrent", "cr", "concurrent"),
                             ("std.collection.concurrent", "bh", "collection.concurrent"),
                             ("std.binary", "ar", "binary")]) {
        failures += check("driver-name:${pkg}", StandardLibName(pkg) ?? "<none>", lib)
        failures += check("driver-map:${pkg}", StandardLibMap().get(pkg) ?? "<none>", lib)
        failures += check("library-name:${pkg}", FileUtil.ConvertPackageNameToLibCangjieBaseFormat(pkg),
                          "cangjie-std-${lib}")
        failures += check("mangle:${pkg}", GetOptPkgName(pkg), code)
        failures += check("recognize:${pkg}", IsStdPackageMangleCode(code).toString(), "true")
        let mangled = "_CN${code}5probeHCN${code}6MarkerECN${code}6MarkerE"
        let demangled = Demangle(mangled)
        failures += check("demangle:${pkg}", demangled.GetPkgName(), pkg)
        failures += check("demangle-valid:${pkg}", demangled.IsValid().toString(), "true")
        let compressed = CJMangledCompression(mangled)
        failures += check("compression:${pkg}", (compressed.size < mangled.size).toString(), "true")
        println("OBSERVE compressed:${pkg}=${compressed}")
    }
    failures += check("unknown-package", StandardLibName("example.concurrent") ?? "<none>", "<none>")
    failures += check("unknown-code", IsStdPackageMangleCode("cz").toString(), "false")
    return if (failures == 0) { 0 } else { 1 }
}
