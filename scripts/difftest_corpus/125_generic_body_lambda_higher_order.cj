func higher<T>(fn:(Int64)->Int64,x:T):Int64{let g={=>fn(41)+1};return g()}
main(){println(higher<Int64>({v:Int64=>v},0))}
