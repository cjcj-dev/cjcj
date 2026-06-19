struct P{let x:Int64;let y:Int64;init(a:Int64,b:Int64){x=a;y=b};func d():Int64{return x*x+y*y}}
main(){ println(P(3,4).d()) }
