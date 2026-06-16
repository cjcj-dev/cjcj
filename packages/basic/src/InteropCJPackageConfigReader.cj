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
    public var apiStrategy: InteropCJStrategy = InteropCJStrategy.NONE
    public var genericTypeStrategy: InteropCJGenericStrategyType = InteropCJGenericStrategyType.NONE
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
        if (content.contains("/*")) {
            WriteError("Failed to open configuration file. Error: Unsupported block comment '/*' detected. Please use line comment '#' instead.\n")
            return false
        }
        var currentSection = ""
        var currentPackage: Option<PackageConfig> = None
        for (rawLine in collectTomlStatements(content)) {
            let line = rawLine.trimAscii()
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
                    if (!parsePackageEntry(pkg, key, value)) {
                        return false
                    }
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
            return pkg.apiStrategy
        }
        return defaultApiStrategy
    }

    public func GetGenericTypeStrategy(packageName: String): InteropCJGenericStrategyType {
        if (let Some(pkg) <- packages.get(packageName)) {
            return pkg.genericTypeStrategy
        }
        return defaultGenericTypeStrategy
    }

    public func Validate(): Bool {
        if (defaultApiStrategy == InteropCJStrategy.UNKNOWN) {
            WriteError("Validation failed: Default API strategy is unknown\n")
            return false
        }
        if (defaultGenericTypeStrategy == InteropCJGenericStrategyType.UNKNOWN) {
            WriteError("Validation failed: Default generic type  strategy is unknown\n")
            return false
        }
        for ((name, pkg) in packages) {
            if (pkg.name.isEmpty()) {
                return false
            }
            if (pkg.apiStrategy == InteropCJStrategy.UNKNOWN) {
                WriteError("Validation failed: '" + name + "' API strategy is unknown\n")
                return false
            }
            if (pkg.genericTypeStrategy == InteropCJGenericStrategyType.UNKNOWN) {
                WriteError("Validation failed: '" + name + "' generic type strategy is unknown\n")
                return false
            }
            if (pkg.apiStrategy == InteropCJStrategy.FULL && !pkg.interopCJIncludedApis.isEmpty()) {
                WriteError("Validation failed for package '" + name +
                    "': API strategy is Full but IncludedApis is Configured \n")
                return false
            }
            if (pkg.apiStrategy == InteropCJStrategy.NONE && !pkg.interopCJExcludedApis.isEmpty()) {
                WriteError("Validation failed for package '" + name +
                    "': API strategy is None but ExcludedApis is Configured \n")
                return false
            }
            if (!pkg.interopCJIncludedApis.isEmpty() && !pkg.interopCJExcludedApis.isEmpty()) {
                WriteError("Validation failed for package '" + name + "': Cannot hava both included and excluded APIs\n")
                return false
            }
            if (pkg.genericTypeStrategy == InteropCJGenericStrategyType.NONE &&
                !pkg.allowedInteropCJGenericInstantiations.isEmpty()) {
                WriteError("Validation failed for package '" + name +
                    "': None generic strategy cannot hava generic instantiations\n")
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

    private func parsePackageEntry(pkg: PackageConfig, key: String, value: String): Bool {
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
            let params = parseSignatureParameterList(signature)
            let retType = parseReturnType(signature)
            pkg.lambdaPatterns.add(LambdaPattern(signature, params, retType))
        } else if (key == "generic_object_configuration") {
            return parseGenericObjectConfiguration(pkg, value)
        } else if (key == "lambda_patterns") {
            parseLambdaPatternsConfiguration(pkg, value)
        }
        return true
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

private func collectTomlStatements(content: String): Array<String> {
    let result = ArrayList<String>()
    var builder = StringBuilder()
    var squareDepth: Int64 = 0
    var braceDepth: Int64 = 0
    var inString = false
    var escaped = false
    for (rawLine in SplitLines(content)) {
        let line = stripComment(rawLine).trimAscii()
        if (line.isEmpty()) {
            continue
        }
        if (builder.toString().isEmpty()) {
            builder.append(line)
        } else {
            builder.append(" " + line)
        }
        for (byte in line.toArray()) {
            if (inString) {
                if (escaped) {
                    escaped = false
                } else if (byte == b'\\') {
                    escaped = true
                } else if (byte == b'"') {
                    inString = false
                }
            } else if (byte == b'"') {
                inString = true
            } else if (byte == b'[') {
                squareDepth++
            } else if (byte == b']') {
                squareDepth--
            } else if (byte == b'{') {
                braceDepth++
            } else if (byte == b'}') {
                braceDepth--
            }
        }
        if (squareDepth <= 0 && braceDepth <= 0 && !inString) {
            result.add(builder.toString())
            builder = StringBuilder()
            squareDepth = 0
            braceDepth = 0
        }
    }
    let rest = builder.toString().trimAscii()
    if (!rest.isEmpty()) {
        result.add(rest)
    }
    return result.toArray()
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

private func splitTopLevel(value: String, delimiter: UInt8): Array<String> {
    let result = ArrayList<String>()
    var builder = StringBuilder()
    var squareDepth: Int64 = 0
    var braceDepth: Int64 = 0
    var angleDepth: Int64 = 0
    var inString = false
    var escaped = false
    for (byte in value.toArray()) {
        if (inString) {
            builder.append(String.fromUtf8([byte]))
            if (escaped) {
                escaped = false
            } else if (byte == b'\\') {
                escaped = true
            } else if (byte == b'"') {
                inString = false
            }
            continue
        }
        if (byte == b'"') {
            inString = true
            builder.append("\"")
        } else if (byte == b'[') {
            squareDepth++
            builder.append("[")
        } else if (byte == b']') {
            squareDepth--
            builder.append("]")
        } else if (byte == b'{') {
            braceDepth++
            builder.append("{")
        } else if (byte == b'}') {
            braceDepth--
            builder.append("}")
        } else if (byte == b'<') {
            angleDepth++
            builder.append("<")
        } else if (byte == b'>') {
            angleDepth--
            builder.append(">")
        } else if (byte == delimiter && squareDepth == 0 && braceDepth == 0 && angleDepth == 0) {
            result.add(builder.toString().trimAscii())
            builder = StringBuilder()
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    let finalPart = builder.toString().trimAscii()
    if (!finalPart.isEmpty()) {
        result.add(finalPart)
    }
    return result.toArray()
}

private func topLevelEquals(value: String): Int64 {
    var squareDepth: Int64 = 0
    var braceDepth: Int64 = 0
    var inString = false
    var escaped = false
    var idx: Int64 = 0
    while (idx < value.size) {
        let byte = value[idx]
        if (inString) {
            if (escaped) {
                escaped = false
            } else if (byte == b'\\') {
                escaped = true
            } else if (byte == b'"') {
                inString = false
            }
        } else if (byte == b'"') {
            inString = true
        } else if (byte == b'[') {
            squareDepth++
        } else if (byte == b']') {
            squareDepth--
        } else if (byte == b'{') {
            braceDepth++
        } else if (byte == b'}') {
            braceDepth--
        } else if (byte == b'=' && squareDepth == 0 && braceDepth == 0) {
            return idx
        }
        idx++
    }
    return -1
}

private func putRawValue(map: HashMap<String, String>, key: String, value: String): Unit {
    if (map.contains(key)) {
        map.remove(key)
    }
    map.add(key, value)
}

private func parseInlineTable(table: String): HashMap<String, String> {
    let result = HashMap<String, String>()
    let trimmed = table.trimAscii()
    if (trimmed.size < 2 || trimmed[0] != b'{' || trimmed[trimmed.size - 1] != b'}') {
        return result
    }
    let body = trimmed[1..trimmed.size - 1]
    for (entry in splitTopLevel(body, b',')) {
        let eqPos = topLevelEquals(entry)
        if (eqPos < 0) {
            continue
        }
        let key = entry[0..eqPos].trimAscii()
        let value = entry[eqPos + 1..].trimAscii()
        if (!key.isEmpty()) {
            putRawValue(result, key, value)
        }
    }
    return result
}

private func parseArrayOfTables(value: String): Array<HashMap<String, String>> {
    let result = ArrayList<HashMap<String, String>>()
    let trimmed = value.trimAscii()
    if (trimmed.size < 2 || trimmed[0] != b'[' || trimmed[trimmed.size - 1] != b']') {
        return result.toArray()
    }
    let body = trimmed[1..trimmed.size - 1]
    var builder = StringBuilder()
    var braceDepth: Int64 = 0
    var inString = false
    var escaped = false
    for (byte in body.toArray()) {
        if (inString) {
            if (braceDepth > 0) {
                builder.append(String.fromUtf8([byte]))
            }
            if (escaped) {
                escaped = false
            } else if (byte == b'\\') {
                escaped = true
            } else if (byte == b'"') {
                inString = false
            }
            continue
        }
        if (byte == b'"') {
            inString = true
            if (braceDepth > 0) {
                builder.append("\"")
            }
        } else if (byte == b'{') {
            braceDepth++
            builder.append("{")
        } else if (byte == b'}') {
            if (braceDepth > 0) {
                builder.append("}")
                braceDepth--
                if (braceDepth == 0) {
                    result.add(parseInlineTable(builder.toString()))
                    builder = StringBuilder()
                }
            }
        } else if (braceDepth > 0) {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return result.toArray()
}

private func appendStrings(target: ArrayList<String>, values: Array<String>): Unit {
    for (value in values) {
        target.add(value)
    }
}

private func isValidInteropType(value: String): Bool {
    let validTypes = [
        "Int", "Int8", "Int16", "Int32", "Int64", "IntNative",
        "UInt8", "UInt16", "UInt32", "UInt64", "UIntNative",
        "Float16", "Float32", "Float64", "Bool", "Boolean", "Unit"
    ]
    for (validType in validTypes) {
        if (value == validType) {
            return true
        }
    }
    return false
}

private func parseTypeString(typeString: String): Array<String> {
    let result = ArrayList<String>()
    for (segment in splitTopLevel(typeString, b',')) {
        let trimmed = segment.trimAscii()
        if (!trimmed.isEmpty() && isValidInteropType(trimmed)) {
            result.add(trimmed)
        }
    }
    return result.toArray()
}

private func combineTypes(types: Array<String>): String {
    return String.join(types, delimiter: ", ")
}

private func putGenericArgs(pkg: PackageConfig, outerType: String, innerType: String, args: GenericTypeArguments): Unit {
    if (let Some(innerMap) <- pkg.allowedInteropCJGenericInstantiations.get(outerType)) {
        if (innerMap.contains(innerType)) {
            innerMap.remove(innerType)
        }
        innerMap.add(innerType, args)
        return
    }
    let created = HashMap<String, GenericTypeArguments>()
    created.add(innerType, args)
    pkg.allowedInteropCJGenericInstantiations.add(outerType, created)
}

private func appendTypeArgument(
    typeArgumentsMap: HashMap<String, ArrayList<String>>,
    packageName: String,
    typeValue: String
): Unit {
    if (let Some(values) <- typeArgumentsMap.get(packageName)) {
        values.add(typeValue)
        return
    }
    let values = ArrayList<String>()
    values.add(typeValue)
    typeArgumentsMap.add(packageName, values)
}

private func containsString(values: ArrayList<String>, value: String): Bool {
    for (candidate in values) {
        if (candidate == value) {
            return true
        }
    }
    return false
}

private func makeSymbols(rawSymbols: String): GenericTypeArguments {
    let args = GenericTypeArguments()
    for (symbol in parseStringArray(rawSymbols)) {
        args.symbols.add(symbol)
    }
    return args
}

private func collectTypeArguments(
    tables: Array<HashMap<String, String>>,
    typeArgumentsMap: HashMap<String, ArrayList<String>>,
    pkg: PackageConfig
): Bool {
    for (table in tables) {
        let packageName = if (let Some(rawName) <- table.get("name")) { parseString(rawName) } else { "" }
        if (packageName.isEmpty()) {
            continue
        }
        if (let Some(rawTypeArguments) <- table.get("type_arguments")) {
            for (typeString in parseStringArray(rawTypeArguments)) {
                let validatedTypes = parseTypeString(typeString)
                if (validatedTypes.isEmpty()) {
                    WriteError("Error: Empty or invalid type definition in package '${pkg.name}'\n")
                    return false
                }
                let combined = combineTypes(validatedTypes)
                putGenericArgs(pkg, packageName, combined, GenericTypeArguments())
                appendTypeArgument(typeArgumentsMap, packageName, combined)
            }
        }
    }
    return true
}

private func processSymbolConfigurations(
    tables: Array<HashMap<String, String>>,
    typeArgumentsMap: HashMap<String, ArrayList<String>>,
    pkg: PackageConfig
): Unit {
    for (table in tables) {
        let name = if (let Some(rawName) <- table.get("name")) { parseString(rawName) } else { "" }
        if (name.isEmpty()) {
            continue
        }
        if (let Some(rawSymbols) <- table.get("symbols")) {
            let anglePos = name.indexOf("<") ?? -1
            if (anglePos >= 0 && name.endsWith(">")) {
                let outerType = name[0..anglePos]
                let innerType = name[anglePos + 1..name.size - 1]
                if (let Some(allowedTypes) <- typeArgumentsMap.get(outerType)) {
                    if (containsString(allowedTypes, innerType)) {
                        putGenericArgs(pkg, outerType, innerType, makeSymbols(rawSymbols))
                    }
                }
            } else {
                putGenericArgs(pkg, name, "", makeSymbols(rawSymbols))
            }
        }
    }
}

private func parseGenericObjectConfiguration(pkg: PackageConfig, value: String): Bool {
    let tables = parseArrayOfTables(value)
    let typeArgumentsMap = HashMap<String, ArrayList<String>>()
    if (!collectTypeArguments(tables, typeArgumentsMap, pkg)) {
        return false
    }
    processSymbolConfigurations(tables, typeArgumentsMap, pkg)
    return true
}

private func parseClassMappings(value: String): Array<ClassMapping> {
    let result = ArrayList<ClassMapping>()
    let table = parseInlineTable(value)
    for ((name, pkgPath) in table) {
        result.add(ClassMapping(name, parseString(pkgPath)))
    }
    return result.toArray()
}

private func parseLambdaPatternsConfiguration(pkg: PackageConfig, value: String): Unit {
    for (table in parseArrayOfTables(value)) {
        if (let Some(rawSignature) <- table.get("signature")) {
            let signature = parseString(rawSignature)
            let lambdaPattern = LambdaPattern(signature, parseSignatureParameterList(signature), parseReturnType(signature))
            if (let Some(rawClassMappings) <- table.get("class_mappings")) {
                for (classMapping in parseClassMappings(rawClassMappings)) {
                    lambdaPattern.classMappings.add(classMapping)
                }
            }
            pkg.lambdaPatterns.add(lambdaPattern)
        }
    }
}

private func parseSignatureParameterList(signature: String): Array<String> {
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
