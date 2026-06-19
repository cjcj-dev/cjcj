func g(b:Bool):Option<Int64>{ if(b){return Some(5)}; return None }
main(){ match(g(true)){ case Some(n)=>println(n); case None=>println(0) } }
