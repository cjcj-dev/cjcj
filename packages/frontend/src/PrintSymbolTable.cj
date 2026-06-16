package cangjie_compiler::frontend

import std.collection.*
import std.sort.*

public func PrintSymbolTable(ci: CompilerInstance): Unit {
    let packages = ArrayList<Symbol>()
    let file2nodesMap = HashMap<String, (File, ArrayList<Node>)>()
    for (srcPkg in ci.GetSourcePackages()) {
        if (let Some(ctx) <- ci.GetASTContextByPackage(srcPkg)) {
            var fileOpt: Option<File> = None
            for (sym in ctx.symbolTable) {
                AddSymbolToInfo(packages, file2nodesMap, fileOpt, sym)
                if (let Some(node) <- sym.node) {
                    if (let Some(fileNode) <- (node as File)) {
                        fileOpt = Some(fileNode)
                    }
                }
            }
        }
    }
    let builder = StringBuilder()
    builder.append("{\n")
    builder.append("  \"packages\": [\n")
    appendPackages(builder, packages)
    builder.append("  ],\n")
    builder.append("  \"files\": [\n")
    appendFiles(builder, file2nodesMap)
    builder.append("  ]\n")
    builder.append("}")
    println(builder.toString())
}

private func AddSymbolToInfo(packages: ArrayList<Symbol>, file2nodesMap: HashMap<String, (File, ArrayList<Node>)>,
    fileOpt: Option<File>, symbol: Symbol): Unit {
    if (let None <- symbol.node) {
        return
    }
    let node = symbol.node.getOrThrow()
    if (node.TestAttr("COMPILER_ADD")) {
        return
    }
    if (node.astKind == ASTKind.PACKAGE) {
        packages.add(symbol)
        return
    }
    var currentFileOpt = fileOpt
    if (let Some(fileNode) <- (node as File)) {
        currentFileOpt = Some(fileNode)
    }
    if (let Some(fileNode) <- currentFileOpt) {
        addNodeForFile(file2nodesMap, fileNode, node)
        HandleFileNode(file2nodesMap, symbol, node)
    }
}

private func HandleFileNode(file2nodesMap: HashMap<String, (File, ArrayList<Node>)>, symbol: Symbol, node: Node): Unit {
    if (node.astKind != ASTKind.FILE) {
        return
    }
    if (let Some(file) <- (node as File)) {
        if (let Some(packageSpec) <- file.packageSpec) {
            addNodeForFile(file2nodesMap, file, packageSpec)
        }
        for (importSpec in file.imports) {
            if (!importSpec.importPos.IsZero()) {
                addNodeForFile(file2nodesMap, file, importSpec)
            }
        }
    }
}

private func addNodeForFile(file2nodesMap: HashMap<String, (File, ArrayList<Node>)>, file: File, node: Node): Unit {
    if (let Some(pair) <- file2nodesMap.get(file.filePath)) {
        pair[1].add(node)
    } else {
        let nodes = ArrayList<Node>()
        nodes.add(node)
        file2nodesMap.add(file.filePath, (file, nodes))
    }
}

private func appendPackages(builder: StringBuilder, packages: ArrayList<Symbol>): Unit {
    let seen = HashSet<String>()
    var emitted: Int64 = 0
    for (symbol in packages) {
        if (seen.contains(symbol.name)) {
            continue
        }
        seen.add(symbol.name)
        if (emitted > 0) {
            builder.append(",\n")
        }
        appendPackage(builder, symbol)
        emitted++
    }
    if (emitted > 0) {
        builder.append("\n")
    }
}

private func appendPackage(builder: StringBuilder, symbol: Symbol): Unit {
    builder.append("    {\n")
    builder.append("      \"name\": \"" + EscapeJson(symbol.name) + "\",\n")
    builder.append("      \"files\": [")
    if (let Some(node) <- symbol.node) {
        if (let Some(pkg) <- (node as Package)) {
            var idx: Int64 = 0
            while (idx < pkg.files.size) {
                if (idx > 0) {
                    builder.append(", ")
                }
                builder.append("\"" + EscapeJson(pkg.files[idx].filePath) + "\"")
                idx++
            }
        }
    }
    builder.append("]\n")
    builder.append("    }")
}

private func appendFiles(builder: StringBuilder, file2nodesMap: HashMap<String, (File, ArrayList<Node>)>): Unit {
    let keys = ArrayList<String>()
    for ((key, _) in file2nodesMap) {
        keys.add(key)
    }
    sort(keys, by: { left: String, right: String =>
        if (left < right) {
            Ordering.LT
        } else if (left > right) {
            Ordering.GT
        } else {
            Ordering.EQ
        }
    })
    var emitted: Int64 = 0
    for (key in keys) {
        if (let Some(pair) <- file2nodesMap.get(key)) {
            if (emitted > 0) {
                builder.append(",\n")
            }
            appendFile(builder, pair[0], pair[1])
            emitted++
        }
    }
    if (emitted > 0) {
        builder.append("\n")
    }
}

private func appendFile(builder: StringBuilder, file: File, nodes: ArrayList<Node>): Unit {
    builder.append("    {\n")
    builder.append("      \"path\": \"" + EscapeJson(file.filePath) + "\",\n")
    builder.append("      \"symbols\": [")
    if (!nodes.isEmpty()) {
        builder.append("\n")
        var idx: Int64 = 0
        while (idx < nodes.size) {
            if (idx > 0) {
                builder.append(",\n")
            }
            appendNode(builder, nodes[idx])
            idx++
        }
        builder.append("\n      ")
    }
    builder.append("]\n")
    builder.append("    }")
}

private func appendNode(builder: StringBuilder, node: Node): Unit {
    if (node.TestAttr("COMPILER_ADD")) {
        return
    }
    builder.append("        {\n")
    builder.append("          \"astKind\": \"" + ASTKindName(node.astKind) + "\",\n")
    builder.append("          \"name\": \"" + EscapeJson(SymbolName(node.symbol)) + "\",\n")
    if (let Some(packageSpec) <- (node as PackageSpec)) {
        appendPackageSpecPart(builder, packageSpec)
    } else if (let Some(importSpec) <- (node as ImportSpec)) {
        appendImportSpecPart(builder, importSpec)
    } else if (let Some(decl) <- (node as Decl)) {
        appendDeclPart(builder, decl)
    }
    appendPosition(builder, node.begin, "begin", true)
    appendPosition(builder, node.end, "end", false)
    builder.append("        }")
}

private func appendPackageSpecPart(builder: StringBuilder, packageSpec: PackageSpec): Unit {
    builder.append("          \"packageName\": \"" + EscapeJson(packageSpec.packageName.Val()) + "\",\n")
    appendPosition(builder, packageSpec.macroPos, "macroPos", true)
    appendPosition(builder, packageSpec.packagePos, "packagePos", true)
    appendPosition(builder, packageSpec.packageName.Begin(), "packageNamePos", true)
}

private func appendImportSpecPart(builder: StringBuilder, importSpec: ImportSpec): Unit {
    appendPosition(builder, importSpec.importPos, "importPos", true)
    builder.append("          \"packageName\": \"" + EscapeJson(GetImportedItemFullName(importSpec.content)) + "\",\n")
    appendPosition(builder, importSpec.content.begin, "packageNamePos", true)
    if (importSpec.IsImportAlias()) {
        appendPosition(builder, importSpec.content.asPos, "asPos", true)
        builder.append("          \"asIdentifier\": \"" + EscapeJson(importSpec.content.aliasName.Val()) + "\",\n")
        appendPosition(builder, importSpec.content.aliasName.Begin(), "asIdentifierPos", true)
    }
}

private func appendDeclPart(builder: StringBuilder, decl: Decl): Unit {
    builder.append("          \"identifier\": \"" + EscapeJson(decl.identifier.Val()) + "\",\n")
    appendPosition(builder, decl.identifier.Begin(), "identifierPos", true)
}

private func appendPosition(builder: StringBuilder, pos: Position, name: String, hasComma: Bool): Unit {
    builder.append("          \"" + name + "\": {\n")
    builder.append("            \"line\": " + pos.line.toString() + ",\n")
    builder.append("            \"column\": " + pos.column.toString() + "\n")
    builder.append("          }")
    if (hasComma) {
        builder.append(",")
    }
    builder.append("\n")
}

private func SymbolName(symbol: Option<Symbol>): String {
    if (let Some(value) <- symbol) {
        return value.name
    }
    return ""
}
