interface Shape{ func area():Int64 }
class Sq<:Shape{let s:Int64;init(x:Int64){s=x};func area():Int64{return s*s}}
main(){ let sh:Shape=Sq(5); println(sh.area()) }
