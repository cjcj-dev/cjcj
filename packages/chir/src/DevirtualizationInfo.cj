package cjcj::chir

import std.collection.*

// Upstream 6e125215 DevirtualizationInfo.h:31-56, DevirtualizationInfo.cpp:19-24.
public class DevirtualizationInfo {
    private let chirPackage: Package
    public let returnTypeMap: HashMap<Int64, Type> = HashMap<Int64, Type>()
    public let subtypeMap: HashMap<CustomTypeDef, ArrayList<InheritanceInfo>> =
        HashMap<CustomTypeDef, ArrayList<InheritanceInfo>>()
    public let constMemberTypeMap: HashMap<Int64, HashMap<Int64, Type>> = HashMap<Int64, HashMap<Int64, Type>>()
    public let defsMap: HashMap<Type, ArrayList<CustomTypeDef>> = HashMap<Type, ArrayList<CustomTypeDef>>()
    public init(chirPackage: Package) { this.chirPackage = chirPackage }
    public func Collect(): Unit {
        ReturnTypeMapCollector(chirPackage).Collect(returnTypeMap)
        InheritanceInfoCollector(chirPackage).Collect(subtypeMap, defsMap)
        for ((key, value) in ConstMemberVarCollector(chirPackage).CollectConstMemberVarType()) {
            constMemberTypeMap[key] = value
        }
    }
}
