import cjcj::option.*
import std.env.getVariable
import std.fs.{File, exists}

main(): Int64 {
    let root = (getVariable("TEMP_OWNERSHIP_ROOT") ?? "")
    if (root.isEmpty()) { return 90 }
    let race = (getVariable("TEMP_OWNERSHIP_RACE") ?? "") == "1"
    let opts = GlobalOptions()
    opts.output = root + "/output/result"
    opts.environment.allVariables.add("TMPDIR", root + "/tmp")
    let manager = TempFileManager.Instance()
    if (!manager.Init(opts, false)) { return 91 }
    let own = manager.GetTempFolder()
    File.writeTo(own + "/own-sentinel", "owned".toArray())
    var other = ""
    if (race) {
        other = String.fromUtf8(File.readFrom(root + "/contended-path"))
    }
    let distinct = !race || own != other
    manager.DeleteTempFiles()
    let ownGone = !exists(own)
    var protected = true
    if (race) {
        protected = exists(other)
        if (protected) {
            protected = String.fromUtf8(File.readFrom(other + "/sentinel")) == "other-process"
        }
    }
    println("TEMP_OWNERSHIP race=${race} distinct=${distinct} ownGone=${ownGone} protected=${protected}")
    return if (distinct && ownGone && protected) { 0 } else { 2 }
}
