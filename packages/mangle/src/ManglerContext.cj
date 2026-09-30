package cjcj::mangle

import std.collection.*
import cjcj::ast.*

private func GetDeclKey(node: Node): Option<Node> {
    if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { return body } }
    if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { return body } }
    if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { return body } }
    if (let Some(vda) <- (node as VarDeclAbstract)) { return vda }
    return None
}

// Original AST identity keys and vectors, BaseMangler.h:160-172.
public class ManglerContext {
    public let file2GlobalWildcardVar = HashMap<Node, ArrayList<VarWithPatternDecl>>()
    public let node2LocalWildcardVar = HashMap<Node, ArrayList<VarWithPatternDecl>>()
    public let node2Lambda = HashMap<Node, ArrayList<LambdaExpr>>()
    public let node2LocalVar = HashMap<Node, HashMap<String, ArrayList<VarDeclAbstract>>>()
    public let node2LocalFunc = HashMap<Node, HashMap<String, ArrayList<FuncDecl>>>()
    public let file2ExtendDecl = HashMap<Node, HashMap<String, ArrayList<ExtendDecl>>>()
    public let fileIndexes = ArrayList<UInt64>()

    public static func ReduceUnitTestPackageName(pkgName: String): String {
        let suffix = "$test"
        return if (EndsWith(pkgName, suffix)) { pkgName[0..pkgName.size - suffix.size] } else { pkgName }
    }

    public static func CheckAllElementsWildcard(root: Pattern): Bool {
        if (root is WildcardPattern) { return true }
        var all = true
        if (let Some(tp) <- (root as TuplePattern)) {
            for (pattern in tp.patterns) { all = all && CheckAllElementsWildcard(pattern) }
        } else if (let Some(ep) <- (root as EnumPattern)) {
            if (ep.patterns.isEmpty()) { all = false }
            for (pattern in ep.patterns) { all = all && CheckAllElementsWildcard(pattern) }
        } else { all = false }
        return all
    }

    public func SaveGlobalWildcardVar(file: File, vpd: VarWithPatternDecl): Unit {
        if (CheckAllElementsWildcard(vpd.irrefutablePattern.getOrThrow())) {
            if (!file2GlobalWildcardVar.contains(file)) { file2GlobalWildcardVar[file] = ArrayList<VarWithPatternDecl>() }
            file2GlobalWildcardVar[file].add(vpd)
        }
    }

    public func SaveFunc2CurDecl(node: Node): Unit {
        if (let Some(fd) <- (node as FuncDecl)) {
            if (fd.TestAttr(Attribute.GENERIC_INSTANTIATED) && !fd.TestAttr(Attribute.GLOBAL)) {
                if (let Some(outer) <- fd.outerDecl) {
                    if (!outer.IsNominalDecl()) {
                        if (let Some(key) <- GetDeclKey(outer)) {
                            if (!node2LocalFunc.contains(key)) { node2LocalFunc[key] = HashMap<String, ArrayList<FuncDecl>>() }
                            let names = node2LocalFunc[key]
                            let name = fd.identifier.Val()
                            if (!names.contains(name)) { names[name] = ArrayList<FuncDecl>() }
                            names[name].add(fd)
                        }
                    }
                }
            }
        }
        if (let Some(key) <- GetDeclKey(node)) {
            Walker(key, visitPre: { child: Node =>
                if (let Some(fd) <- (child as FuncDecl)) {
                    if (child != key) {
                        if (!node2LocalFunc.contains(key)) { node2LocalFunc[key] = HashMap<String, ArrayList<FuncDecl>>() }
                        let names = node2LocalFunc[key]
                        let name = fd.identifier.Val()
                        if (!names.contains(name)) { names[name] = ArrayList<FuncDecl>() }
                        names[name].add(fd)
                    }
                }
                VisitAction.WALK_CHILDREN
            }).Walk()
        }
    }

    public func SaveLocalWildcardVar2Decl(node: Node): Unit {
        var key: Option<Node> = None
        if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { key = body } }
        else if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { key = body } }
        else if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { key = body } }
        else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL)) { key = vda }
        }
        if (let Some(root) <- key) {
            Walker(root, visitPre: { child: Node =>
                if (let Some(vda) <- (child as VarWithPatternDecl)) {
                    if (child != root) {
                        if (!node2LocalWildcardVar.contains(root)) { node2LocalWildcardVar[root] = ArrayList<VarWithPatternDecl>() }
                        node2LocalWildcardVar[root].add(vda)
                    }
                } else if (child is FuncBody && child != root) { return VisitAction.SKIP_CHILDREN }
                VisitAction.WALK_CHILDREN
            }).Walk()
        }
    }

    public func SaveVar2CurDecl(node: Node): Unit {
        var key: Option<Node> = None
        if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { key = body } }
        else if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { key = body } }
        else if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { key = body } }
        else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL)) { key = vda }
        }
        if (let Some(root) <- key) {
            Walker(root, visitPre: { child: Node =>
                if (let Some(vda) <- (child as VarDeclAbstract)) {
                    if (child != root) {
                        if (!node2LocalVar.contains(root)) { node2LocalVar[root] = HashMap<String, ArrayList<VarDeclAbstract>>() }
                        let names = node2LocalVar[root]
                        let name = vda.identifier.Val()
                        if (!names.contains(name)) { names[name] = ArrayList<VarDeclAbstract>() }
                        names[name].add(vda)
                    }
                } else if (child is FuncBody && child != root) { return VisitAction.SKIP_CHILDREN }
                VisitAction.WALK_CHILDREN
            }).Walk()
        }
    }

    public func SaveLambda2CurDecl(node: Node): Unit {
        let keys = ArrayList<Node>()
        if (let Some(lambda) <- (node as LambdaExpr)) { keys.add(lambda.funcBody.getOrThrow()) }
        else if (let Some(fd) <- (node as FuncDecl)) {
            keys.add(fd.funcBody.getOrThrow())
            if (let Some(array) <- fd.annotationsArray) { keys.add(array) }
        } else if (let Some(ctor) <- (node as PrimaryCtorDecl)) {
            keys.add(ctor.funcBody.getOrThrow())
            if (let Some(array) <- ctor.annotationsArray) { keys.add(array) }
        } else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL) || (if (let Some(outer) <- vda.outerDecl) {
                outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
            } else { false })) {
                keys.add(vda)
                if (let Some(array) <- vda.annotationsArray) { keys.add(array) }
            }
        }
        for (key in keys) {
            Walker(key, visitPre: { child: Node =>
                if (let Some(lambda) <- (child as LambdaExpr)) {
                    if (child != key) {
                        if (!node2Lambda.contains(key)) { node2Lambda[key] = ArrayList<LambdaExpr>() }
                        node2Lambda[key].add(lambda)
                    }
                } else if (child is FuncBody && child != key) { return VisitAction.SKIP_CHILDREN }
                VisitAction.WALK_CHILDREN
            }).Walk()
        }
    }

    public func SaveExtend2CurFile(file: File, node: ExtendDecl): Unit {
        if (!file2ExtendDecl.contains(file)) { file2ExtendDecl[file] = HashMap<String, ArrayList<ExtendDecl>>() }
        let names = file2ExtendDecl[file]
        let name = node.extendedType.getOrThrow().GetTy().getOrThrow().String()
        if (!names.contains(name)) { names[name] = ArrayList<ExtendDecl>() }
        names[name].add(node)
    }

    public func GetIndexOfGlobalWildcardVar(file: File, target: VarWithPatternDecl): Option<Int64> {
        if (file.fileHash == 0) { return None }
        if (let Some(values) <- file2GlobalWildcardVar.get(file)) {
            for (i in 0..values.size) { if (values[i] == target) { return i } }
        }
        return None
    }

    public func GetIndexOfExtend(file: File, target: ExtendDecl): Option<Int64> {
        let values = file2ExtendDecl[file][target.extendedType.getOrThrow().GetTy().getOrThrow().String()]
        for (i in 0..values.size) { if (values[i] == target) { return i } }
        return None
    }

    public func GetIndexOfLocalWildcardVar(node: Node, target: VarWithPatternDecl): Option<Int64> {
        var key: Option<Node> = None
        if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { key = body } }
        else if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { key = body } }
        else if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { key = body } }
        else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL)) { key = vda }
        }
        if (let Some(root) <- key) {
            if (let Some(values) <- node2LocalWildcardVar.get(root)) {
                for (i in 0..values.size) { if (values[i] == target) { return i } }
            }
        }
        return None
    }

    public func GetIndexOfVar(node: Node, target: VarDeclAbstract): Option<Int64> {
        var key: Option<Node> = None
        if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { key = body } }
        else if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { key = body } }
        else if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { key = body } }
        else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL)) { key = vda }
        }
        if (let Some(root) <- key) {
            if (let Some(names) <- node2LocalVar.get(root)) {
                if (let Some(values) <- names.get(target.identifier.Val())) {
                    for (i in 0..values.size) { if (values[i] == target) { return i } }
                }
            }
        }
        return None
    }

    public func GetIndexOfFunc(node: Node, target: FuncDecl): Option<Int64> {
        if (let Some(key) <- GetDeclKey(node)) {
            if (let Some(names) <- node2LocalFunc.get(key)) {
                if (let Some(values) <- names.get(target.identifier.Val())) {
                    for (i in 0..values.size) { if (values[i] == target) { return i } }
                }
            }
        }
        return None
    }

    public func GetIndexOfLambda(node: Node, target: LambdaExpr): Option<Int64> {
        var key: Option<Node> = None
        var annotation: Option<ArrayLit> = None
        if (let Some(lambda) <- (node as LambdaExpr)) { if (let Some(body) <- lambda.funcBody) { key = body } }
        else if (let Some(fd) <- (node as FuncDecl)) { if (let Some(body) <- fd.funcBody) { key = body }; annotation = fd.annotationsArray }
        else if (let Some(ctor) <- (node as PrimaryCtorDecl)) { if (let Some(body) <- ctor.funcBody) { key = body }; annotation = ctor.annotationsArray }
        else if (let Some(vda) <- (node as VarDeclAbstract)) {
            if (vda.TestAttr(Attribute.GLOBAL) || (if (let Some(outer) <- vda.outerDecl) {
                outer.astKind == ASTKind.CLASS_DECL || outer.astKind == ASTKind.INTERFACE_DECL ||
                outer.astKind == ASTKind.STRUCT_DECL || outer.astKind == ASTKind.ENUM_DECL
            } else { false })) { key = vda; annotation = vda.annotationsArray }
        }
        var offset: Int64 = 0
        if (let Some(root) <- key) {
            if (let Some(values) <- node2Lambda.get(root)) {
                for (i in 0..values.size) { if (values[i] == target) { return i } }
                offset = values.size
            }
        }
        if (let Some(root) <- annotation) {
            if (let Some(values) <- node2Lambda.get(root)) {
                for (i in 0..values.size) { if (values[i] == target) { return offset + i } }
            }
        }
        throw IllegalArgumentException("index of lambda has no value")
    }
}
