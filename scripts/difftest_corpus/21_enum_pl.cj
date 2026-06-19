enum C{Red|Green|Blue}
func idx(c:C):Int64{match(c){case Red=>0;case Green=>1;case Blue=>2}}
main():Int64{ return idx(Green) }
