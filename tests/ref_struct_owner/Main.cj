import ref_struct_owner.*
main(): Int64 {
    let holder = Holder()
    if (heapSite(holder, Anchor(40)) != 40) { return 1 }
    println("OWNER_ASSERT heap")
    if (globalSite(Anchor(41)) != 41) { return 2 }
    println("OWNER_ASSERT global")
    if (localSite(Anchor(42)) != 42) { return 3 }
    println("OWNER_ASSERT local")
    if (forwardSite(holder, Anchor(43)) != 43) { return 4 }
    println("OWNER_ASSERT forwarded")
    if (trySite(holder, Anchor(-1)) != -1 || holder.slot.value.value != 43) { return 5 }
    if (trySite(holder, Anchor(44)) != 44) { return 6 }
    println("OWNER_ASSERT try_apply")
    if (tupleControl(Anchor(40)) != 49 || primitiveControl(40) != 41) { return 7 }
    println("OWNER_ASSERT tuple_primitive")
    return 0
}
