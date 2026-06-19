class Box<T>{let v:T;init(x:T){v=x};func get():T{return v}}
main(){ println(Box<Int64>(9).get()) }
