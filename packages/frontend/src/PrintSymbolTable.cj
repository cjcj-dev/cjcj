package cangjie_compiler::frontend

import cangjie_compiler::basic.{PrintIndent, PrintIndentOnly, PrintNoSplit, Println}
import cangjie_compiler::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}
import std.collection.*

private let ONE_INDENT: UInt64 = 1u64
private let TWO_INDENT: UInt64 = 2u64
private let THREE_INDENT: UInt64 = 3u64
private let FOUR_INDENT: UInt64 = 4u64
private let FIVE_INDENT: UInt64 = 5u64

private func PrintIndentNoSplitNoEndl(indent: UInt64, value: String): Unit {
    PrintIndentOnly(indent)
    PrintNoSplit(value)
}

private func PrintIndentNoSplit(indent: UInt64, value: String): Unit {
    PrintIndentNoSplitNoEndl(indent, value)
    Println()
}

private func PrintPackage(symbol: Symbol): Unit {
    PrintIndent(TWO_INDENT, "{")
    PrintIndentNoSplit(THREE_INDENT, "\"name\": \"" + symbol.name + "\",")
    PrintIndent(THREE_INDENT, "\"files\": [")
    CJC_NULLPTR_CHECK(symbol.node)
    let node = symbol.node.getOrThrow()
    CJC_ASSERT(node.astKind == ASTKind.PACKAGE)
    let pkg = (node as Package).getOrThrow()
    var idx: Int64 = 0
    PrintIndentNoSplitNoEndl(FOUR_INDENT, "\"" + pkg.files[idx].filePath + "\"")
    idx++
    while (idx < pkg.files.size) {
        Println(value: ",")
        PrintIndentNoSplitNoEndl(FOUR_INDENT, "\"" + pkg.files[idx].filePath + "\"")
        idx++
    }
    Println()
    PrintIndent(THREE_INDENT, "]")
    PrintIndentNoSplitNoEndl(TWO_INDENT, "}")
}

private func PrintPackages(packages: ArrayList<Symbol>): Unit {
    if (packages.isEmpty()) {
        return
    }
    let packageNames = HashSet<String>()
    var idx: Int64 = 0
    packageNames.add(packages[idx].name)
    PrintPackage(packages[idx])
    idx++
    while (idx < packages.size) {
        let symbol = packages[idx]
        if (!packageNames.contains(symbol.name)) {
            packageNames.add(symbol.name)
            Println(value: ",")
            PrintPackage(symbol)
        }
        idx++
    }
    Println()
}

private func PrintPosition(indent: UInt64, pos: Position, name: String, hasComma: Bool): Unit {
    PrintIndentNoSplit(indent, "\"" + name + "\": {")
    PrintIndentNoSplit(indent + ONE_INDENT, "\"line\": " + pos.line.toString() + ",")
    PrintIndent(indent + ONE_INDENT, "\"column\":" + pos.column.toString())
    PrintIndentNoSplit(indent, "}" + if (hasComma) { "," } else { "" })
}

private func PrintPackageSpecPart(packageSpec: PackageSpec): Unit {
    PrintIndentNoSplit(FIVE_INDENT, "\"packageName\": \"" + packageSpec.packageName.Val() + "\",")
    PrintPosition(FIVE_INDENT, packageSpec.macroPos, "macroPos", true)
    PrintPosition(FIVE_INDENT, packageSpec.packagePos, "packagePos", true)
    PrintPosition(FIVE_INDENT, packageSpec.packageName.Begin(), "packageNamePos", true)
}

private func PrintImportSpecPart(importSpec: ImportSpec): Unit {
    PrintPosition(FIVE_INDENT, importSpec.importPos, "importPos", true)
    PrintIndentNoSplit(FIVE_INDENT, "\"packageName\": \"" + GetImportedItemFullName(importSpec.content) + "\",")
    PrintPosition(FIVE_INDENT, importSpec.content.begin, "packageNamePos", true)
    if (importSpec.IsImportAlias()) {
        PrintPosition(FIVE_INDENT, importSpec.content.asPos, "asPos", true)
        PrintIndentNoSplit(FIVE_INDENT, "\"asIdentifier\": \"" + importSpec.content.aliasName.Val() + "\",")
        PrintPosition(FIVE_INDENT, importSpec.content.aliasName.Begin(), "asIdentifierPos", true)
    }
}

private func PrintDeclPart(decl: Decl): Unit {
    PrintIndentNoSplit(FIVE_INDENT, "\"identifier\": \"" + decl.identifier.Val() + "\",")
    PrintPosition(FIVE_INDENT, decl.identifier.Begin(), "identifierPos", true)
}

private func PrintNode(node: Node): Unit {
    if (node.TestAttr(Attribute.COMPILER_ADD)) {
        return
    }
    PrintIndent(FOUR_INDENT, "{")
    PrintIndentNoSplit(FIVE_INDENT, "\"astKind\": \"" + ASTKindName(node.astKind) + "\",")
    let symbolName = if (let Some(symbol) <- node.symbol) { symbol.name } else { "" }
    PrintIndentNoSplit(FIVE_INDENT, "\"name\": \"" + symbolName + "\",")
    if (let Some(packageSpec) <- (node as PackageSpec)) {
        PrintPackageSpecPart(packageSpec)
    } else if (let Some(importSpec) <- (node as ImportSpec)) {
        PrintImportSpecPart(importSpec)
    } else if (let Some(decl) <- (node as Decl)) {
        PrintDeclPart(decl)
    }
    PrintPosition(FIVE_INDENT, node.begin, "begin", true)
    PrintPosition(FIVE_INDENT, node.end, "end", false)
    PrintIndentNoSplitNoEndl(FOUR_INDENT, "}")
}

private func PrintFile(file: File, nodes: ArrayList<Node>): Unit {
    PrintIndent(TWO_INDENT, "{")
    PrintIndentNoSplit(THREE_INDENT, "\"path\": \"" + file.filePath + "\",")
    PrintIndentNoSplit(THREE_INDENT, "\"symbols\": [")
    if (!nodes.isEmpty()) {
        var idx: Int64 = 0
        PrintNode(nodes[idx])
        idx++
        while (idx < nodes.size) {
            Println(value: ",")
            PrintNode(nodes[idx])
            idx++
        }
        Println()
    }
    PrintIndentNoSplit(THREE_INDENT, "]")
    PrintIndentNoSplitNoEndl(TWO_INDENT, "}")
}

private func PrintFiles(file2nodesMap: HashMap<Node, ArrayList<Node>>): Unit {
    if (file2nodesMap.isEmpty()) {
        return
    }
    var emitted: Int64 = 0
    for ((fileKey, nodes) in file2nodesMap) {
        if (emitted > 0) {
            Println(value: ",")
        }
        PrintFile((fileKey as File).getOrThrow(), nodes)
        emitted++
    }
    Println()
}

private func HandleFileNode(file2nodesMap: HashMap<Node, ArrayList<Node>>, symbol: Symbol, node: Node): Unit {
    if (node.astKind != ASTKind.FILE) {
        return
    }
    if (let Some(nodeSymbol) <- node.symbol) {
        if (refEq(symbol, nodeSymbol)) {
            return
        }
    }
    let file = (node as File).getOrThrow()
    let fileKey: Node = file
    if (file2nodesMap.get(fileKey).isNone()) {
        file2nodesMap.add(fileKey, ArrayList<Node>())
    }
    let nodes = file2nodesMap.get(fileKey).getOrThrow()
    if (let Some(packageSpec) <- file.packageSpec) {
        nodes.add(packageSpec)
    }
    for (importSpec in file.imports) {
        if (importSpec.importPos.line != 0) {
            nodes.add(importSpec)
        }
    }
}

private func AddSymbolToInfo(packages: ArrayList<Symbol>, file2nodesMap: HashMap<Node, ArrayList<Node>>,
    fileOpt: Box<Option<File>>, symbol: Symbol): Unit {
    CJC_NULLPTR_CHECK(symbol.node)
    let node = symbol.node.getOrThrow()
    if (node.TestAttr(Attribute.COMPILER_ADD)) {
        return
    }
    if (node.astKind == ASTKind.PACKAGE) {
        packages.add(symbol)
        return
    }
    if (node.astKind == ASTKind.FILE) {
        fileOpt.value = (node as File).getOrThrow()
    }
    CJC_ASSERT(fileOpt.value.isSome())
    let file = fileOpt.value.getOrThrow()
    let fileKey: Node = file
    if (let Some(nodes) <- file2nodesMap.get(fileKey)) {
        nodes.add(node)
    } else {
        let nodes = ArrayList<Node>()
        nodes.add(node)
        file2nodesMap.add(fileKey, nodes)
    }
    HandleFileNode(file2nodesMap, symbol, node)
}

public func PrintSymbolTable(ci: CompilerInstance): Unit {
    let packages = ArrayList<Symbol>()
    let file2nodesMap = HashMap<Node, ArrayList<Node>>()
    for (srcPkg in ci.GetSourcePackages()) {
        let ctxOpt = ci.GetASTContextByPackage(srcPkg)
        CJC_NULLPTR_CHECK(ctxOpt)
        let ctx = ctxOpt.getOrThrow()
        let fileOpt = Box<Option<File>>(None)
        for (sym in ctx.symbolTable) {
            AddSymbolToInfo(packages, file2nodesMap, fileOpt, sym)
        }
    }
    Println(value: "{")
    PrintIndent(ONE_INDENT, "\"packages\": [")
    PrintPackages(packages)
    PrintIndent(ONE_INDENT, "],")
    PrintIndent(ONE_INDENT, "\"files\": [")
    PrintFiles(file2nodesMap)
    PrintIndent(ONE_INDENT, "]")
    Println(value: "}")
}
