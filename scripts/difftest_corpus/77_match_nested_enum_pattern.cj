enum E{Lit(Int64)|Add(E,E)|Other}
func score(v:Option<E>):Int64{match(v){case Some(Add(Lit(x),Lit(y)))=>x*10+y;case Some(_)=>1;case None=>0}}
main(){ println(score(Some(Add(Lit(4),Lit(6))))) }
