func f(b:Bool):Option<Int64>{ if(b){return Some(42)}; return None }
main(){ if(let Some(n)<-f(true)){ println(n) } else { println(0) } }
