func outer(x:Int64):Int64{ func inner(y:Int64):Int64{ return y*y }; return inner(x)+1 }
main(){ println(outer(5)) }
