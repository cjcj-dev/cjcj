// G10 valid-program negative control: conversion.

main(): Int64 {
    let x: Int32 = 21
    if (Int64(x) * 2 != 42) { return 1 }
    return 0
}
