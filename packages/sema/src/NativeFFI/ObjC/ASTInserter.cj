package cjcj::sema.NativeFFI.ObjC

import cjcj::ast.*
import cjcj::basic.Position
import cjcj::utils.{CJC_NULLPTR_CHECK, GetRootPackageName}

public enum InsertMode {
    | SHALLOW
    | RECURSIVE
}

// Upstream a51ced71, ObjC/Utils/ASTInserter.cpp:26-70.
private class InsertLocation {
    public let curFile: Option<File>
    public let fullPackageName: String
    public let range: Position

    public init(curFile: Option<File>, fullPackageName: String, range: Position) {
        this.curFile = curFile
        this.fullPackageName = fullPackageName
        this.range = range
    }
}

private func SetSynthesizedRange(node: Node, pos: Position): Unit {
    node.begin = pos
    node.end = pos
}

private func SetPackageInfo(decl: Decl, fullPackageName: String): Unit {
    decl.fullPackageName = fullPackageName
    decl.moduleName = GetRootPackageName(fullPackageName)
}

private func BindNode(node: Node, loc: InsertLocation): Unit {
    node.curFile = loc.curFile
    SetSynthesizedRange(node, loc.range)
    if (let Some(decl) <- (node as Decl)) {
        SetPackageInfo(decl, loc.fullPackageName)
        if (decl.identifier.ZeroPos()) {
            decl.identifier.SetPos(loc.range, loc.range)
        }
    }
}

private func Bind(node: Node, loc: InsertLocation, mode: InsertMode): Unit {
    match (mode) {
        case InsertMode.SHALLOW => BindNode(node, loc)
        case InsertMode.RECURSIVE =>
            let walker = Walker(node, visitPre: {subNode: Node =>
                BindNode(subNode, loc)
                return VisitAction.WALK_CHILDREN
            })
            let _ = walker.Walk()
    }
}

// Upstream a51ced71, ObjC/Utils/ASTInserter.cpp:73-115.
public class ASTInserter {
    public func InsertInto(target: File, decl: Decl, mode!: InsertMode = InsertMode.RECURSIVE): Unit {
        Bind(decl, InsertLocation(Some(target), target.GetFullPackageName(), target.end), mode)
        target.decls.add(decl)
    }

    public func BindTo(target: ClassLikeDecl, decl: Decl, mode!: InsertMode = InsertMode.RECURSIVE): Unit {
        CJC_NULLPTR_CHECK(target.curFile)
        decl.outerDecl = Some(target)
        decl.EnableAttr(Attribute.IN_CLASSLIKE)
        if (let Some(fd) <- (decl as FuncDecl)) {
            if (let Some(body) <- fd.funcBody) {
                body.parentClassLike = Some(target)
            }
        }
        Bind(decl, InsertLocation(target.curFile, target.GetFullPackageName(), target.end), mode)
    }

    public func InsertInto(target: ClassLikeDecl, decl: Decl, mode!: InsertMode = InsertMode.RECURSIVE): Unit {
        BindTo(target, decl, mode: mode)
        target.GetMemberDecls().add(decl)
    }

    public func InsertGetterInto(target: PropDecl, getterDecl: FuncDecl,
        mode!: InsertMode = InsertMode.RECURSIVE): Unit {
        CJC_NULLPTR_CHECK(target.curFile)
        getterDecl.outerDecl = target.outerDecl
        getterDecl.propDecl = Some(target)
        getterDecl.isGetter = true
        Bind(getterDecl, InsertLocation(target.curFile, target.GetFullPackageName(), target.end), mode)
        target.getters.add(getterDecl)
    }

    public func InsertSetterInto(target: PropDecl, setterDecl: FuncDecl,
        mode!: InsertMode = InsertMode.RECURSIVE): Unit {
        CJC_NULLPTR_CHECK(target.curFile)
        setterDecl.outerDecl = target.outerDecl
        setterDecl.propDecl = Some(target)
        setterDecl.isSetter = true
        Bind(setterDecl, InsertLocation(target.curFile, target.GetFullPackageName(), target.end), mode)
        target.setters.add(setterDecl)
    }
}
