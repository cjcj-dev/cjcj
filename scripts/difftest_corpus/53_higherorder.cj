func ap(f:(Int64)->Int64,x:Int64):Int64{ return f(x) }
main(){ println(ap({y:Int64=>y*2},21)) }
