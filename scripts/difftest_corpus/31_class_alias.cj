class Ctr{var n:Int64;init(){n=0};func inc(){n=n+1};func get():Int64{return n}}
main(){ let a=Ctr(); let b=a; b.inc(); println(a.get()) }
