package cjcj::modules

import std.collection.*
import cjcj::basic.SplitQualifiedName as BasicSplitQualifiedName
import cjcj::ast.AccessLevel as ASTAccessLevel
import cjcj::ast.Attribute as ASTAttribute

public type AccessLevel = ASTAccessLevel
public type Attribute = ASTAttribute
public let TEST_PKG_SUFFIX: String = "$test"

public enum PackageRelation {
    | NONE
    | CHILD
    | SAME_MODULE
    | SAME_PACKAGE
}

private func PackageRelationIndex(relation: PackageRelation): Int64 {
    return match (relation) {
        case PackageRelation.NONE => 0
        case PackageRelation.CHILD => 1
        case PackageRelation.SAME_MODULE => 2
        case PackageRelation.SAME_PACKAGE => 3
    }
}

extend PackageRelation <: Equatable<PackageRelation> {
    public operator func ==(right: PackageRelation): Bool {
        return PackageRelationIndex(this) == PackageRelationIndex(right)
    }

    public operator func !=(right: PackageRelation): Bool {
        return !(this == right)
    }
}

public func SplitQualifiedName(qualifiedName: String, splitDc!: Bool = false): ArrayList<String> {
    let names = ArrayList<String>()
    for (name in BasicSplitQualifiedName(qualifiedName, splitDc: splitDc)) {
        names.add(name)
    }
    return names
}

public func IsTestPackage(pkgName: String): Bool {
    return pkgName.size >= TEST_PKG_SUFFIX.size && pkgName.endsWith(TEST_PKG_SUFFIX)
}

public func GetMainPartPkgNameForTestPkg(testPkgName: String): String {
    if (!IsTestPackage(testPkgName)) {
        return testPkgName
    }
    return testPkgName[0..testPkgName.size - TEST_PKG_SUFFIX.size]
}

public func GetPackageRelation(srcFullPkgName: String, targetFullPkgName: String): PackageRelation {
    let pureSrcFullPackageName = if (IsTestPackage(srcFullPkgName)) {
        GetMainPartPkgNameForTestPkg(srcFullPkgName)
    } else {
        srcFullPkgName
    }
    let pureTargetFullPackageName = if (IsTestPackage(targetFullPkgName)) {
        GetMainPartPkgNameForTestPkg(targetFullPkgName)
    } else {
        targetFullPkgName
    }
    if (pureSrcFullPackageName == pureTargetFullPackageName) {
        return PackageRelation.SAME_PACKAGE
    }
    if (pureSrcFullPackageName.isEmpty() || pureTargetFullPackageName.isEmpty()) {
        return PackageRelation.NONE
    }
    let srcPath = SplitQualifiedName(pureSrcFullPackageName)
    let targetPath = SplitQualifiedName(pureTargetFullPackageName)
    if (targetPath.size < srcPath.size && startsWithPath(srcPath, targetPath)) {
        return PackageRelation.CHILD
    }
    if (!srcPath.isEmpty() && !targetPath.isEmpty() && srcPath[0] == targetPath[0]) {
        return PackageRelation.SAME_MODULE
    }
    return PackageRelation.NONE
}

public func IsSuperPackage(srcFullPackageName: String, targetFullPackageName: String): Bool {
    let pureSrcFullPackageName = if (IsTestPackage(srcFullPackageName)) {
        GetMainPartPkgNameForTestPkg(srcFullPackageName)
    } else {
        srcFullPackageName
    }
    let pureTargetFullPackageName = if (IsTestPackage(targetFullPackageName)) {
        GetMainPartPkgNameForTestPkg(targetFullPackageName)
    } else {
        targetFullPackageName
    }
    if (!pureTargetFullPackageName.startsWith(pureSrcFullPackageName)) {
        return false
    }
    let srcNames = SplitQualifiedName(pureSrcFullPackageName)
    let targetNames = SplitQualifiedName(pureTargetFullPackageName)
    return srcNames.size + 1 == targetNames.size
}

public func RelationToString(relation: PackageRelation): String {
    return match (relation) {
        case PackageRelation.NONE => "irrelevant"
        case PackageRelation.CHILD => "child"
        case PackageRelation.SAME_MODULE => "same module"
        case PackageRelation.SAME_PACKAGE => "same package"
    }
}

private func startsWithPath(longPath: ArrayList<String>, shortPath: ArrayList<String>): Bool {
    if (shortPath.size > longPath.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < shortPath.size) {
        if (longPath[idx] != shortPath[idx]) {
            return false
        }
        idx++
    }
    return true
}

