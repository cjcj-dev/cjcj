package varray_location

func arithmetic(index: Int64): Unit {
    var values: VArray<Int64, $4> = [1, 2, 3, 4]
    values[index] += 1
    values[index] -= 1
    values[index] *= 2
    values[index] /= 2
    values[index] %= 2
    values[index] **= 2
    values[index] &= 1
    values[index] |= 1
    values[index] ^= 1
    values[index] <<= 1
    values[index] >>= 1
}

func logical(index: Int64): Unit {
    var values: VArray<Bool, $4> = [true, false, true, false]
    values[index] &&= true
    values[index] ||= false
}

func ordinary(index: Int64): Unit {
    var values: VArray<Int64, $4> = [1, 2, 3, 4]
    values[index] = 3
}
