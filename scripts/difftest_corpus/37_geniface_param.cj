interface Sink<T> { func put(x:T):Int64 }
class ICell<:Sink<Int64> { public func put(x:Int64):Int64{return x+1} }
main(){ let s:Sink<Int64>=ICell(); println(s.put(41)) }
