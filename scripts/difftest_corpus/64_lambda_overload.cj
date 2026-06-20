func choose(f:(Int64)->Int64):Int64{ return f(41) }
func choose(s:String):Int64{ return s.size }
main(){ println(choose({x=>x+1})) }
