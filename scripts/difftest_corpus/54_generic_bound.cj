interface Sized { func sz():Int64 }
class Box<:Sized { let n:Int64; init(x:Int64){n=x}; public func sz():Int64{return n} }
func total<T>(a:T,b:T):Int64 where T<:Sized { return a.sz()+b.sz() }
main(){ println(total(Box(3),Box(4))) }
