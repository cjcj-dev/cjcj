package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*

public class Collector {
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public func BuildSymbolTable(ctx: ASTContext, pkg: Package, buildTrie!: Bool = true): Unit {
        ctx.curPackage = pkg
        ctx.fullPackageName = pkg.fullPackageName
        let collector = this
        let walker = Walker(pkg, visitPre: { node: Node =>
            if (let Some(lce) <- (node as LitConstExpr)) {
                collector.CollectLitConstExpr(ctx, lce, buildTrie: buildTrie)
            } else {
                collector.AddSymbol(ctx, node, buildTrie: buildTrie)
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
        ctx.searcher.InvalidateCache()
    }

    public func Collect(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectDecl(decl)
            }
        }
    }

    private func collectDecl(decl: Decl): Unit {
        decls.add(decl)
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            for (constructor in enumDecl.constructors) {
                collectDecl(constructor)
            }
        }
        for (member in decl.GetMemberDecls()) {
            collectDecl(member)
        }
    }

    private func AddSymbol(ctx: ASTContext, node: Node, buildTrie!: Bool = true): Unit {
        let scopeName = if (node.scopeName.isEmpty()) { TOPLEVEL_SCOPE_NAME } else { node.scopeName }
        let fileHash = if (let Some(file) <- node.curFile) { file.fileHash } else { 0u64 }
        let symbol = Symbol(fileHash, SymbolName(node), node, node.scopeLevel, scopeName)
        node.symbol = Some(symbol)
        ctx.symbolTable.add(symbol)
        ctx.invertedIndex.Index(symbol, withTrie: buildTrie)
    }

    private func CollectLitConstExpr(ctx: ASTContext, lce: LitConstExpr, buildTrie!: Bool = true): Unit {
        if (let Some(refName) <- StringLiteralRefName(lce.kind)) {
            if (let None <- lce.ref) {
                let refType = RefType()
                refType.begin = lce.begin
                refType.ref.identifier = SrcIdentifier(refName)
                refType.EnableAttr(Attribute.COMPILER_ADD)
                refType.EnableAttr(Attribute.IN_CORE)
                lce.ref = Some(refType)
                AddSymbol(ctx, refType, buildTrie: buildTrie)
            }
        }
        AddSymbol(ctx, lce, buildTrie: buildTrie)
    }

    private func StringLiteralRefName(kind: LitConstKind): Option<String> {
        if (kind == LitConstKind.STRING) {
            return Some("String")
        }
        if (kind == LitConstKind.JSTRING) {
            return Some("JString")
        }
        return None
    }

    private func SymbolName(node: Node): String {
        if (let Some(pkg) <- (node as Package)) {
            return pkg.fullPackageName
        }
        if (let Some(file) <- (node as File)) {
            return if (!file.fileName.isEmpty()) { file.fileName } else { file.filePath }
        }
        if (let Some(decl) <- (node as Decl)) {
            return decl.identifier.Val()
        }
        if (let Some(refExpr) <- (node as RefExpr)) {
            return refExpr.ref.identifier.Val()
        }
        if (let Some(member) <- (node as MemberAccess)) {
            return member.field.Val()
        }
        if (let Some(refType) <- (node as RefType)) {
            return refType.ref.identifier.Val()
        }
        if (let Some(qualifiedType) <- (node as QualifiedType)) {
            return qualifiedType.field.Val()
        }
        if (let Some(primitiveType) <- (node as PrimitiveType)) {
            return primitiveType.str
        }
        if (let Some(varOrEnumPattern) <- (node as VarOrEnumPattern)) {
            return varOrEnumPattern.identifier.Val()
        }
        if (let Some(enumPattern) <- (node as EnumPattern)) {
            return enumPattern.GetIdentifier()
        }
        return ""
    }
}
