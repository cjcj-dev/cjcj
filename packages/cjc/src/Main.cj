package cangjie_compiler::cjc

import std.env.*
import cangjie_compiler::driver.RunDriverMain

main(): Int64 {
    return RunDriverMain(getCommandLine())
}
