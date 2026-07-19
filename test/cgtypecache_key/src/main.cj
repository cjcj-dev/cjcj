import std.collection.*
import cjcj::chir.{Type, TypeKind}
import cjcj::codegen.{CGTypeCacheKey, TypeExtraInfo}

func Check(condition: Bool, message: String): Unit {
    if (!condition) {
        throw IllegalStateException(message)
    }
}

func MakeInfo(addrspace: UInt32, isMethod: Bool, isStaticMethod: Bool, allowBasePtr: Bool,
    forWrapper: Bool, params: ArrayList<Type>): TypeExtraInfo {
    let info = TypeExtraInfo(addrspace, isMethod, isStaticMethod, allowBasePtr, params)
    info.forWrapper = forWrapper
    return info
}

main(): Int64 {
    let typeA = Type(TypeKind.TYPE_INT64)
    let typeB = Type(TypeKind.TYPE_INT64)
    let typeC = Type(TypeKind.TYPE_BOOLEAN)
    let params = ArrayList<Type>()
    params.add(typeA)
    params.add(typeC)
    let original = MakeInfo(1u32, true, false, false, true, params)
    let key = CGTypeCacheKey(original)
    Check(key == CGTypeCacheKey(MakeInfo(1u32, true, false, false, true, params)), "equal key mismatch")
    Check(key != CGTypeCacheKey(MakeInfo(0u32, true, false, false, true, params)), "addrspace omitted")
    Check(key != CGTypeCacheKey(MakeInfo(1u32, false, false, false, true, params)), "isMethod omitted")
    Check(key != CGTypeCacheKey(MakeInfo(1u32, true, true, false, true, params)), "isStaticMethod omitted")
    Check(key != CGTypeCacheKey(MakeInfo(1u32, true, false, true, true, params)), "allowBasePtr omitted")
    Check(key != CGTypeCacheKey(MakeInfo(1u32, true, false, false, false, params)), "forWrapper omitted")

    let reversedParams = ArrayList<Type>()
    reversedParams.add(typeC)
    reversedParams.add(typeA)
    Check(key != CGTypeCacheKey(MakeInfo(1u32, true, false, false, true, reversedParams)),
        "generic argument order omitted")
    let distinctIdentityParams = ArrayList<Type>()
    distinctIdentityParams.add(typeB)
    distinctIdentityParams.add(typeC)
    Check(key != CGTypeCacheKey(MakeInfo(1u32, true, false, false, true, distinctIdentityParams)),
        "generic argument identity omitted")

    original.forWrapper = false
    original.instantiatedParamTypes.add(typeB)
    Check(!(key == original), "mutated source unexpectedly matched immutable key")
    Check(key == CGTypeCacheKey(MakeInfo(1u32, true, false, false, true, params)),
        "key changed after source mutation")

    let outer = HashMap<CGTypeCacheKey, Int64>()
    outer[key] = 7
    Check(outer.get(CGTypeCacheKey(MakeInfo(1u32, true, false, false, true, params))) == Some(7),
        "HashMap key lookup failed")
    let inner = HashMap<Type, Int64>()
    inner[typeA] = 11
    inner[typeB] = 13
    Check(inner.size == 2 && inner[typeA] == 11 && inner[typeB] == 13, "Type identity HashMap mismatch")
    println("CGTYPECACHE-KEY-PASS")
    return 0
}
