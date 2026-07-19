package cjcj::codegen

import std.collection.*
import cjcj::chir.Type

@OverflowWrapping
private func CGTypeCacheHash(extraInfo: TypeExtraInfo): Int64 {
    var result = extraInfo.addrspace.hashCode()
    result = result * 131 + if (extraInfo.isMethod) { 1 } else { 0 }
    result = result * 131 + if (extraInfo.isStaticMethod) { 1 } else { 0 }
    result = result * 131 + if (extraInfo.allowBasePtr) { 1 } else { 0 }
    result = result * 131 + if (extraInfo.forWrapper) { 1 } else { 0 }
    for (ty in extraInfo.instantiatedParamTypes) {
        result = result * 131 + ty.hashCode()
    }
    return result
}

// Mirrors CGType::TypeExtraInfo and TypeExtraInfoHasher in CodeGen/Base/CGTypes/CGType.h:285-335.
public struct CGTypeCacheKey <: Hashable & Equatable<CGTypeCacheKey> {
    private let addrspace: UInt32
    private let isMethod: Bool
    private let isStaticMethod: Bool
    private let allowBasePtr: Bool
    private let forWrapper: Bool
    private let instantiatedParamTypes: Array<Type>
    private let hashValue: Int64

    public init(extraInfo: TypeExtraInfo) {
        addrspace = extraInfo.addrspace
        isMethod = extraInfo.isMethod
        isStaticMethod = extraInfo.isStaticMethod
        allowBasePtr = extraInfo.allowBasePtr
        forWrapper = extraInfo.forWrapper
        instantiatedParamTypes = extraInfo.instantiatedParamTypes.toArray()
        hashValue = CGTypeCacheHash(extraInfo)
    }

    public operator func ==(right: CGTypeCacheKey): Bool {
        if (instantiatedParamTypes.size != right.instantiatedParamTypes.size || addrspace != right.addrspace ||
            isMethod != right.isMethod || isStaticMethod != right.isStaticMethod ||
            allowBasePtr != right.allowBasePtr || forWrapper != right.forWrapper) {
            return false
        }
        var idx: Int64 = 0
        while (idx < instantiatedParamTypes.size) {
            if (instantiatedParamTypes[idx] != right.instantiatedParamTypes[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    public operator func !=(right: CGTypeCacheKey): Bool {
        return !(this == right)
    }

    public func hashCode(): Int64 {
        return hashValue
    }

    public operator func ==(extraInfo: TypeExtraInfo): Bool {
        if (instantiatedParamTypes.size != extraInfo.instantiatedParamTypes.size ||
            addrspace != extraInfo.addrspace || isMethod != extraInfo.isMethod ||
            isStaticMethod != extraInfo.isStaticMethod || allowBasePtr != extraInfo.allowBasePtr ||
            forWrapper != extraInfo.forWrapper) {
            return false
        }
        var idx: Int64 = 0
        while (idx < instantiatedParamTypes.size) {
            if (instantiatedParamTypes[idx] != extraInfo.instantiatedParamTypes[idx]) {
                return false
            }
            idx++
        }
        return true
    }
}

public class CGContextImpl {
    private let cgTypePool: ArrayList<CGType> = ArrayList<CGType>()
    private let chirType2CGTypeMap:
        HashMap<Int64, ArrayList<(CGTypeCacheKey, HashMap<Type, CGType>)>> =
        HashMap<Int64, ArrayList<(CGTypeCacheKey, HashMap<Type, CGType>)>>()
    private let valueAndBasePtrMap: HashMap<UIntNative, LLVMValueRef> = HashMap<UIntNative, LLVMValueRef>()
    private let nullableReferences: HashSet<UIntNative> = HashSet<UIntNative>()

    public init() {}

    public func Clear(): Unit {
        cgTypePool.clear()
        chirType2CGTypeMap.clear()
        valueAndBasePtrMap.clear()
        nullableReferences.clear()
    }

    public func AddCGType(cgType: CGType): Unit {
        cgTypePool.add(cgType)
    }

    public func FindCGType(extraInfo: TypeExtraInfo, chirTy: Type): Option<CGType> {
        let hashValue = CGTypeCacheHash(extraInfo)
        if (let Some(bucket) <- chirType2CGTypeMap.get(hashValue)) {
            for ((key, cache) in bucket) {
                if (key == extraInfo) {
                    return cache.get(chirTy)
                }
            }
        }
        return None
    }

    public func SetCGType(extraInfo: TypeExtraInfo, chirTy: Type, cgType: CGType): Unit {
        let hashValue = CGTypeCacheHash(extraInfo)
        if (let Some(bucket) <- chirType2CGTypeMap.get(hashValue)) {
            for ((key, cache) in bucket) {
                if (key == extraInfo) {
                    cache[chirTy] = cgType
                    return
                }
            }
            let cache = HashMap<Type, CGType>()
            cache[chirTy] = cgType
            bucket.add((CGTypeCacheKey(extraInfo), cache))
            return
        }
        let cache = HashMap<Type, CGType>()
        cache[chirTy] = cgType
        let bucket = ArrayList<(CGTypeCacheKey, HashMap<Type, CGType>)>()
        bucket.add((CGTypeCacheKey(extraInfo), cache))
        chirType2CGTypeMap[hashValue] = bucket
    }

    public func SetBasePtr(value: LLVMValueRef, basePtr: LLVMValueRef): Unit {
        valueAndBasePtrMap[value.toUIntNative()] = basePtr
    }

    public func GetBasePtr(value: LLVMValueRef): Option<LLVMValueRef> {
        let key = value.toUIntNative()
        if (valueAndBasePtrMap.contains(key)) {
            return valueAndBasePtrMap[key]
        }
        return None
    }

    public func AddNullableReference(value: LLVMValueRef): Unit {
        nullableReferences.add(value.toUIntNative())
    }
}
