package cangjie_compiler::codegen

import std.collection.*

public class CGContextImpl {
    private let cgTypePool: ArrayList<CGType> = ArrayList<CGType>()
    private let chirType2CGTypeMap: HashMap<String, CGType> = HashMap<String, CGType>()
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

    public func FindCGType(key: String): Option<CGType> {
        if (chirType2CGTypeMap.contains(key)) {
            return chirType2CGTypeMap[key]
        }
        return None
    }

    public func SetCGType(key: String, cgType: CGType): Unit {
        chirType2CGTypeMap[key] = cgType
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
