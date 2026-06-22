func wrap2<T>(x:Int64):Int64{ let g={=>x+1}; return g() }
main(){ println(wrap2<Int64>(41)) }
