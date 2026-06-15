package cangjie_compiler::basic

import std.collection.*
import std.fs.*

public enum InteropCJStrategy {
    | FULL
    | NONE
    | UNKNOWN
}

private func InteropCJStrategyIndex(strategy: InteropCJStrategy): Int64 {
    return match (strategy) {
        case InteropCJStrategy.FULL => 0
        case InteropCJStrategy.NONE => 1
        case InteropCJStrategy.UNKNOWN => 2
    }
}

extend InteropCJStrategy <: Equatable<InteropCJStrategy> {
    public operator func ==(right: InteropCJStrategy): Bool {
        return InteropCJStrategyIndex(this) == InteropCJStrategyIndex(right)
    }

    public operator func !=(right: InteropCJStrategy): Bool {
        return !(this == right)
    }
}

public enum InteropCJGenericStrategyType {
    | NONE
    | PARTIAL
    | UNKNOWN
}

private func InteropCJGenericStrategyTypeIndex(strategy: InteropCJGenericStrategyType): Int64 {
    return match (strategy) {
        case InteropCJGenericStrategyType.NONE => 0
        case InteropCJGenericStrategyType.PARTIAL => 1
        case InteropCJGenericStrategyType.UNKNOWN => 2
    }
}

extend InteropCJGenericStrategyType <: Equatable<InteropCJGenericStrategyType> {
    public operator func ==(right: InteropCJGenericStrategyType): Bool {
        return InteropCJGenericStrategyTypeIndex(this) == InteropCJGenericStrategyTypeIndex(right)
    }

    public operator func !=(right: InteropCJGenericStrategyType): Bool {
        return !(this == right)
    }
}

public class GenericTypeArguments {
    public let symbols: HashSet<String> = HashSet<String>()

    public init() {}
}

public class ClassMapping {
    public var name: String
    public var pkgPath: String

    public init(name: String, pkgPath: String) {
        this.name = name
        this.pkgPath = pkgPath
    }
}

public class LambdaPattern {
    public var signature: String
    public let parameterTypes: ArrayList<String> = ArrayList<String>()
    public var returnType: String
    public let classMappings: ArrayList<ClassMapping> = ArrayList<ClassMapping>()
    public var fullPackageName: String = ""

    public init(signature: String, parameterTypes: Array<String>, returnType: String) {
        this.signature = signature
        this.returnType = returnType
        for (parameterType in parameterTypes) {
            this.parameterTypes.add(parameterType)
        }
    }
}

public class PackageConfig {
    public var name: String = ""
    public var apiStrategy: InteropCJStrategy = InteropCJStrategy.UNKNOWN
    public var genericTypeStrategy: InteropCJGenericStrategyType = InteropCJGenericStrategyType.UNKNOWN
    public let interopCJIncludedApis: ArrayList<String> = ArrayList<String>()
    public let interopCJExcludedApis: ArrayList<String> = ArrayList<String>()
    public let allowedInteropCJGenericInstantiations: HashMap<String, HashMap<String, GenericTypeArguments>> =
        HashMap<String, HashMap<String, GenericTypeArguments>>()
    public let interopTuples: ArrayList<String> = ArrayList<String>()
    public let lambdaPatterns: ArrayList<LambdaPattern> = ArrayList<LambdaPattern>()

    public init() {}
}

public class InteropCJPackageConfigReader {
    public var defaultApiStrategy: InteropCJStrategy = InteropCJStrategy.NONE
    public var defaultGenericTypeStrategy: InteropCJGenericStrategyType = InteropCJGenericStrategyType.NONE
    public let packages: HashMap<String, PackageConfig> = HashMap<String, PackageConfig>()

    public init() {}

    public func Parse(filePath: String): Bool {
        let content = String.fromUtf8(File.readFrom(filePath))
        var currentSection = ""
        var currentPackage: Option<PackageConfig> = None
        for (rawLine in SplitLines(content)) {
            let line = stripComment(rawLine).trimAscii()
            if (line.isEmpty()) {
                continue
            }
            if (line == "[default]") {
                storePackage(currentPackage)
                currentPackage = None
                currentSection = "default"
                continue
            }
            if (line == "[[package]]" || line == "[package]") {
                storePackage(currentPackage)
                currentPackage = PackageConfig()
                currentSection = "package"
                continue
            }
            if (!line.contains("=")) {
                continue
            }
            let parts = SplitString(line, "=")
            if (parts.size < 2) {
                continue
            }
            let eqPos = line.indexOf("=") ?? -1
            if (eqPos < 0) {
                continue
            }
            let key = parts[0].trimAscii()
            let value = line[eqPos + 1..].trimAscii()
            if (currentSection == "default") {
                parseDefaultEntry(key, value)
            } else if (currentSection == "package") {
                if (let Some(pkg) <- currentPackage) {
                    parsePackageEntry(pkg, key, value)
                }
            }
        }
        storePackage(currentPackage)
        return Validate()
    }

    public func GetPackage(name: String): Option<PackageConfig> {
        return packages.get(name)
    }

    public func GetApiStrategy(packageName: String): InteropCJStrategy {
        if (let Some(pkg) <- packages.get(packageName)) {
            return if (pkg.apiStrategy == InteropCJStrategy.UNKNOWN) { defaultApiStrategy } else { pkg.apiStrategy }
        }
        return defaultApiStrategy
    }

    public func GetGenericTypeStrategy(packageName: String): InteropCJGenericStrategyType {
        if (let Some(pkg) <- packages.get(packageName)) {
            return if (pkg.genericTypeStrategy == InteropCJGenericStrategyType.UNKNOWN) {
                defaultGenericTypeStrategy
            } else {
                pkg.genericTypeStrategy
            }
        }
        return defaultGenericTypeStrategy
    }

    public func Validate(): Bool {
        if (defaultApiStrategy == InteropCJStrategy.UNKNOWN ||
            defaultGenericTypeStrategy == InteropCJGenericStrategyType.UNKNOWN) {
            return false
        }
        for ((_, pkg) in packages) {
            if (pkg.name.isEmpty()) {
                return false
            }
        }
        return true
    }

    private func parseDefaultEntry(key: String, value: String): Unit {
        if (key == "APIStrategy") {
            defaultApiStrategy = stringToStrategy(parseString(value))
        } else if (key == "GenericTypeStrategy") {
            defaultGenericTypeStrategy = stringToGenericStrategy(parseString(value))
        }
    }

    private func parsePackageEntry(pkg: PackageConfig, key: String, value: String): Unit {
        if (key == "name") {
            pkg.name = parseString(value)
        } else if (key == "APIStrategy") {
            pkg.apiStrategy = stringToStrategy(parseString(value))
        } else if (key == "GenericTypeStrategy") {
            pkg.genericTypeStrategy = stringToGenericStrategy(parseString(value))
        } else if (key == "included_apis") {
            appendStrings(pkg.interopCJIncludedApis, parseStringArray(value))
        } else if (key == "excluded_apis") {
            appendStrings(pkg.interopCJExcludedApis, parseStringArray(value))
        } else if (key == "tuple_configuration") {
            appendStrings(pkg.interopTuples, parseStringArray(value))
        } else if (key == "signature") {
            let signature = parseString(value)
            let params = parseParameterList(signature)
            let retType = parseReturnType(signature)
            pkg.lambdaPatterns.add(LambdaPattern(signature, params, retType))
        }
        // TODO(selfhost:Basic): complete tinytoml-compatible parsing for generic_object_configuration and class_mappings tables.
    }

    private func storePackage(pkgOpt: Option<PackageConfig>): Unit {
        if (let Some(pkg) <- pkgOpt) {
            if (!pkg.name.isEmpty()) {
                if (packages.contains(pkg.name)) {
                    packages.remove(pkg.name)
                }
                packages.add(pkg.name, pkg)
            }
        }
    }
}

private func stringToStrategy(value: String): InteropCJStrategy {
    if (value == "Full") {
        return InteropCJStrategy.FULL
    }
    if (value == "None") {
        return InteropCJStrategy.NONE
    }
    return InteropCJStrategy.UNKNOWN
}

private func stringToGenericStrategy(value: String): InteropCJGenericStrategyType {
    if (value == "None") {
        return InteropCJGenericStrategyType.NONE
    }
    if (value == "Partial") {
        return InteropCJGenericStrategyType.PARTIAL
    }
    return InteropCJGenericStrategyType.UNKNOWN
}

private func stripComment(line: String): String {
    var inString = false
    var idx: Int64 = 0
    while (idx < line.size) {
        let ch = line[idx]
        if (ch == b'"') {
            inString = !inString
        } else if (ch == b'#' && !inString) {
            return line[0..idx]
        }
        idx++
    }
    return line
}

private func parseString(value: String): String {
    let trimmed = value.trimAscii()
    if (trimmed.size >= 2 && trimmed[0] == b'"' && trimmed[trimmed.size - 1] == b'"') {
        return StringConvertor.Normalize(trimmed[1..trimmed.size - 1])
    }
    return trimmed
}

private func parseStringArray(value: String): Array<String> {
    let result = ArrayList<String>()
    let trimmed = value.trimAscii()
    if (trimmed.size < 2 || trimmed[0] != b'[' || trimmed[trimmed.size - 1] != b']') {
        return result.toArray()
    }
    var idx: Int64 = 1
    var builder = StringBuilder()
    var inString = false
    while (idx < trimmed.size - 1) {
        let ch = trimmed[idx]
        if (ch == b'"') {
            if (inString) {
                result.add(StringConvertor.Normalize(builder.toString()))
                builder = StringBuilder()
                inString = false
            } else {
                inString = true
            }
        } else if (inString) {
            builder.append(String.fromUtf8([ch]))
        }
        idx++
    }
    return result.toArray()
}

private func appendStrings(target: ArrayList<String>, values: Array<String>): Unit {
    for (value in values) {
        target.add(value)
    }
}

private func parseParameterList(signature: String): Array<String> {
    if (!signature.startsWith("(")) {
        return Array<String>()
    }
    let end = signature.indexOf(")") ?? -1
    if (end <= 1) {
        return Array<String>()
    }
    let paramsStr = signature[1..end]
    let parameters = ArrayList<String>()
    var currentParam = StringBuilder()
    var genericDepth: Int64 = 0
    for (byte in paramsStr.toArray()) {
        if (byte == b'<') {
            genericDepth++
            currentParam.append("<")
        } else if (byte == b'>') {
            genericDepth--
            currentParam.append(">")
        } else if (byte == b',' && genericDepth == 0) {
            let param = currentParam.toString().trimAscii()
            if (!param.isEmpty()) {
                parameters.add(param)
            }
            currentParam = StringBuilder()
        } else {
            currentParam.append(String.fromUtf8([byte]))
        }
    }
    let finalParam = currentParam.toString().trimAscii()
    if (!finalParam.isEmpty()) {
        parameters.add(finalParam)
    }
    return parameters.toArray()
}

private func parseReturnType(signature: String): String {
    if (let Some(pos) <- signature.indexOf("->")) {
        return signature[pos + 2..].trimAscii()
    }
    return ""
}
