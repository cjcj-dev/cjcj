func wrap<T>(x:T):Int64{ let f={=>42}; return f() }
main(){ println(wrap<Int64>(7)) }
