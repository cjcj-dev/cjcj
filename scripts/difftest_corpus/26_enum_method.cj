enum Color { Red | Green | Blue ; func code():Int64 { match(this){ case Red=>1; case Green=>2; case Blue=>3 } } }
main(){ println(Green.code()) }
