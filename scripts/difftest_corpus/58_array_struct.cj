struct P{ let v:Int64; init(x:Int64){v=x} }
main(){ let a=Array<P>(3,{i=>P(i*2)}); println(a[2].v) }
