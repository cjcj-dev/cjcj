enum E{Lit(Int64)|Add(E,E)|Mul(E,E)}
func ev(e:E):Int64{match(e){case Lit(n)=>n;case Add(a,b)=>ev(a)+ev(b);case Mul(a,b)=>ev(a)*ev(b)}}
main(){ println(ev(Add(Lit(3),Mul(Lit(4),Lit(5))))) }
