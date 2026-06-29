package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Type

public class CGContextImpl {
    private let cgTypePool: ArrayList<CGType> = ArrayList<CGType>()
    private let chirType2CGTypeMap: ArrayList<(TypeExtraInfo, ArrayList<(Type, CGType)>)> =
        ArrayList<(TypeExtraInfo, ArrayList<(Type, CGType)>)>()
    private let valueAndBasePtrMap: HashMap<String, LLVMValueRef> = HashMap<String, LLVMValueRef>()
    private let nullableReferences: HashSet<String> = HashSet<String>()

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
        for ((cachedExtraInfo, cache) in chirType2CGTypeMap) {
            if (extraInfo == cachedExtraInfo) {
                for ((cachedChirTy, cachedCGType) in cache) {
                    if (refEq(cachedChirTy, chirTy)) {
                        return cachedCGType
                    }
                }
            }
        }
        return None
    }

    public func SetCGType(extraInfo: TypeExtraInfo, chirTy: Type, cgType: CGType): Unit {
        for ((cachedExtraInfo, cache) in chirType2CGTypeMap) {
            if (extraInfo == cachedExtraInfo) {
                var idx: Int64 = 0
                while (idx < cache.size) {
                    if (refEq(cache[idx][0], chirTy)) {
                        cache[idx] = (chirTy, cgType)
                        return
                    }
                    idx++
                }
                cache.add((chirTy, cgType))
                return
            }
        }
        let keyExtraInfo = TypeExtraInfo(extraInfo.addrspace, extraInfo.isMethod, extraInfo.isStaticMethod,
            extraInfo.allowBasePtr, extraInfo.instantiatedParamTypes)
        keyExtraInfo.forWrapper = extraInfo.forWrapper
        let cache = ArrayList<(Type, CGType)>()
        cache.add((chirTy, cgType))
        chirType2CGTypeMap.add((keyExtraInfo, cache))
    }

    public func SetBasePtr(key: String, value: LLVMValueRef): Unit {
        valueAndBasePtrMap[key] = value
    }

    public func GetBasePtr(key: String): Option<LLVMValueRef> {
        if (valueAndBasePtrMap.contains(key)) {
            return valueAndBasePtrMap[key]
        }
        return None
    }

    public func AddNullableReference(key: String): Unit {
        nullableReferences.add(key)
    }
}
