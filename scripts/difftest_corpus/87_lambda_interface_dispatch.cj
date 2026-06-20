interface Runner{func run(x:Int64):Int64}
class AddRunner<:Runner{public func run(x:Int64):Int64{let base=2; let f={y:Int64=>y+base}; return f(x)}}
main(){let r:Runner=AddRunner(); println(r.run(5))}
