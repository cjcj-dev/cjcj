package cangjie_compiler::ast

import std.collection.*

public class PrintNode {
    public init() {}

    public static func Print(node: Node, indent!: UInt64 = 0, addition!: String = ""): String {
        let state = PrintState(indent, addition)
        let walker = Walker(node, visitPre: { curNode: Node =>
            state.VisitPre(curNode)
        }, visitPost: { _: Node =>
            state.VisitPost()
        })
        walker.Walk()
        return state.Result()
    }

    public static func PrintTy(ty: Ty): String {
        return ty.String()
    }

    public static func PrintTy(ty: Option<Ty>): String {
        if (let Some(value) <- ty) {
            return value.String()
        }
        return "Invalid"
    }
}

private class PrintState {
    private let builder: StringBuilder = StringBuilder()
    private let rootIndent: UInt64
    private let rootAddition: String
    private var depth: UInt64
    private let depthStack: ArrayList<UInt64> = ArrayList<UInt64>()

    public init(indent: UInt64, addition: String) {
        rootIndent = indent
        rootAddition = addition
        depth = indent
    }

    public func VisitPre(curNode: Node): VisitAction {
        appendNodeLine(builder, depth, curNode, if (depth == rootIndent) { rootAddition } else { "" })
        depthStack.add(depth)
        depth++
        return VisitAction.WALK_CHILDREN
    }

    public func VisitPost(): VisitAction {
        if (!depthStack.isEmpty()) {
            depth = depthStack[depthStack.size - 1]
            depthStack.remove(at: depthStack.size - 1)
        }
        return VisitAction.WALK_CHILDREN
    }

    public func Result(): String {
        return builder.toString()
    }
}

public func PrintASTNode(node: Node): String {
    return PrintNode.Print(node)
}

public func PrintASTNode(node: Node, indent!: UInt64 = 0, addition!: String = ""): String {
    return PrintNode.Print(node, indent: indent, addition: addition)
}

private func appendNodeLine(builder: StringBuilder, depth: UInt64, node: Node, addition: String): Unit {
    appendIndent(builder, depth)
    if (!addition.isEmpty()) {
        builder.append(addition)
        builder.append(" ")
    }
    builder.append(displayName(node))
    let summary = displaySummary(node)
    if (!summary.isEmpty()) {
        builder.append(": ")
        builder.append(quoteText(summary))
    }
    builder.append(" {")
    appendBasicInfo(builder, node)
    builder.append("}\n")
}

private func appendIndent(builder: StringBuilder, depth: UInt64): Unit {
    for (_ in 0..depth) {
        builder.append("  ")
    }
}

private func displayName(node: Node): String {
    if (let Some(pkg) <- (node as Package)) {
        return "Package(" + pkg.fullPackageName + ")"
    }
    if (let Some(file) <- (node as File)) {
        if (!file.fileName.isEmpty()) {
            return "File(" + file.fileName + ")"
        }
    }
    if (let Some(decl) <- (node as Decl)) {
        let name = decl.identifier.GetRawText()
        if (!name.isEmpty()) {
            return ASTKindName(node.astKind) + "(" + name + ")"
        }
    }
    if (let Some(refExpr) <- (node as RefExpr)) {
        let name = refExpr.ref.identifier.GetRawText()
        if (!name.isEmpty()) {
            return "ref_expr(" + name + ")"
        }
    }
    if (let Some(member) <- (node as MemberAccess)) {
        let name = member.field.GetRawText()
        if (!name.isEmpty()) {
            return "member_access_expr(" + name + ")"
        }
    }
    if (let Some(refType) <- (node as RefType)) {
        let name = refType.ref.identifier.GetRawText()
        if (!name.isEmpty()) {
            return "ref_type(" + name + ")"
        }
    }
    if (let Some(qualified) <- (node as QualifiedType)) {
        let name = qualified.field.GetRawText()
        if (!name.isEmpty()) {
            return "qualified_type(" + name + ")"
        }
    }
    return ASTKindName(node.astKind)
}

private func displaySummary(node: Node): String {
    if (let Some(lit) <- (node as LitConstExpr)) {
        return lit.LitKindToString() + " " + lit.ToString()
    }
    if (let Some(importContent) <- (node as ImportContent)) {
        return importContent.GetImportedPackageName()
    }
    if (let Some(packageSpec) <- (node as PackageSpec)) {
        return packageSpec.GetPackageName()
    }
    if (let Some(featureId) <- (node as FeatureId)) {
        return featureId.ToString()
    }
    if (let Some(modifier) <- (node as Modifier)) {
        return modifier.ToString()
    }
    if (let Some(annotation) <- (node as Annotation)) {
        return annotation.identifier.Val()
    }
    if (let Some(macroExpr) <- (node as MacroExpandExpr)) {
        return macroExpr.invocation.macroCallDiagInfo.fullName
    }
    if (let Some(macroDecl) <- (node as MacroExpandDecl)) {
        return macroDecl.invocation.macroCallDiagInfo.fullName
    }
    if (let Some(macroParam) <- (node as MacroExpandParam)) {
        return macroParam.invocation.macroCallDiagInfo.fullName
    }
    let text = node.ToString()
    if (text == displayName(node)) {
        return ""
    }
    return text
}

private func appendBasicInfo(builder: StringBuilder, node: Node): Unit {
    appendField(builder, "pos", node.begin.ToString() + ".." + node.end.ToString())
    if (let Some(file) <- node.curFile) {
        if (!file.filePath.isEmpty()) {
            appendField(builder, "file", file.filePath)
        } else if (!file.fileName.isEmpty()) {
            appendField(builder, "file", file.fileName)
        }
    }
    if (!node.scopeName.isEmpty()) {
        appendField(builder, "scope", node.scopeName)
    }
    if (node.scopeLevel != 0u32) {
        appendField(builder, "scopeLevel", "${node.scopeLevel}")
    }
    if (node.TyKind() != TypeKind.TYPE_INITIAL) {
        appendField(builder, "ty", PrintNode.PrintTy(node.GetTy()))
    }
    let attrs = node.GetAttrs().ToString()
    if (attrs != "[]") {
        appendField(builder, "attrs", attrs)
    }
    if (!node.exportId.isEmpty()) {
        appendField(builder, "exportId", node.exportId)
    }
    let fullPackageName = node.GetFullPackageName()
    if (!fullPackageName.isEmpty() && fullPackageName != "default") {
        appendField(builder, "pkg", fullPackageName)
    }
    if (let Some(symbol) <- node.symbol) {
        appendField(builder, "symbol", symbol.name + "@" + symbol.scopeName)
    }
    if (let Some(decl) <- (node as Decl)) {
        appendDeclInfo(builder, decl)
    }
    if (let Some(target) <- node.GetTarget()) {
        appendField(builder, "target", targetName(target))
    }
    if (!node.comments.IsEmpty()) {
        appendField(builder, "comments", node.comments.ToString())
    }
}

private func appendDeclInfo(builder: StringBuilder, decl: Decl): Unit {
    if (decl.linkage != Linkage.EXTERNAL) {
        appendField(builder, "linkage", linkageName(decl.linkage))
    }
    if (decl.IsConst()) {
        appendField(builder, "isConst", "true")
    }
    if (!decl.mangledName.isEmpty()) {
        appendField(builder, "mangledName", decl.mangledName)
    }
    if (let Some(outer) <- decl.outerDecl) {
        appendField(builder, "outerDecl", targetName(outer))
    }
    if (decl.doNotExport) {
        appendField(builder, "doNotExport", "true")
    }
}

private func appendField(builder: StringBuilder, name: String, value: String): Unit {
    if (value.isEmpty()) {
        return
    }
    builder.append(" ")
    builder.append(name)
    builder.append("=")
    builder.append(quoteText(value))
}

private func targetName(decl: Decl): String {
    if (!decl.mangledName.isEmpty()) {
        return decl.mangledName
    }
    let name = decl.identifier.GetRawText()
    if (!name.isEmpty()) {
        return ASTKindName(decl.astKind) + "(" + name + ")"
    }
    return ASTKindName(decl.astKind) + "@" + decl.begin.ToString()
}

private func linkageName(linkage: Linkage): String {
    return match (linkage) {
        case Linkage.WEAK_ODR => "WEAK_ODR"
        case Linkage.EXTERNAL => "EXTERNAL"
        case Linkage.INTERNAL => "INTERNAL"
        case Linkage.LINKONCE_ODR => "LINKONCE_ODR"
        case Linkage.EXTERNAL_WEAK => "EXTERNAL_WEAK"
    }
}

private func quoteText(value: String): String {
    return "\"" + escape(value) + "\""
}

private func escape(value: String): String {
    let builder = StringBuilder()
    for (byte in value.toArray()) {
        if (byte == b'\n') {
            builder.append("\\n")
        } else if (byte == b'\r') {
            builder.append("\\r")
        } else if (byte == b'\t') {
            builder.append("\\t")
        } else if (byte == b'"') {
            builder.append("\\\"")
        } else if (byte == b'\\') {
            builder.append("\\\\")
        } else {
            builder.append(String.fromUtf8([byte]))
        }
    }
    return builder.toString()
}
