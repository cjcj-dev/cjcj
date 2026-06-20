interface Speaker{func word():String;func phrase():String{return word()+"!"}}
class Bot<:Speaker{public func word():String{return "ok"}}
main(){ let speaker:Speaker=Bot(); let f=speaker.phrase; println(f()) }
