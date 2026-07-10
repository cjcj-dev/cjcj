package cjcj::incremental_compilation

// PORT-DEFERRED: the C++ InvidPath case expects writable ".log" to leave logging disabled,
// but the current selfhost IncrementalCompilationLogger enables any writable path ending in ".log".
