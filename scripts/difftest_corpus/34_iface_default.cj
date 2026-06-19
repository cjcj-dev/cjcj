interface Greet { func name():String; func hello():String { return "hi "+name() } }
class P<:Greet { public func name():String{return "x"} }
main(){ let g:Greet=P(); println(g.hello()) }
