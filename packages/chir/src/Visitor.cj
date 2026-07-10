package cangjie_compiler::chir

import std.collection.ArrayList
import cangjie_compiler::utils.DynamicCast

public enum VisitResult {
    | CONTINUE
    | SKIP
    | STOP
}

public type VisitExprActionFunc = (Expression) -> VisitResult
public type VisitBlockActionFunc = (Block) -> VisitResult
public type VisitBlockGroupActionFunc = (BlockGroup) -> VisitResult

public interface Iterator {
    static func Iterate(expr: Expression): ArrayList<BlockGroup>
    static func Iterate(blockGroup: BlockGroup): ArrayList<Block>
    static func Iterate(block: Block): ArrayList<Expression>
}

public class SimpleIterator <: Iterator {
    public static func Iterate(expr: Expression): ArrayList<BlockGroup> {
        return expr.GetBlockGroups()
    }

    public static func Iterate(blockGroup: BlockGroup): ArrayList<Block> {
        return blockGroup.GetBlocks()
    }

    public static func Iterate(block: Block): ArrayList<Expression> {
        return block.GetExpressions()
    }
}

public func Walk(expr: Expression, pre: VisitBlockGroupActionFunc,
    post: VisitBlockGroupActionFunc): VisitResult {
    return Walk(SimpleIterator(), expr, pre, post)
}

public func Walk<I>(iterator: I, expr: Expression, pre: VisitBlockGroupActionFunc,
    post: VisitBlockGroupActionFunc): VisitResult where I <: Iterator {
    let _ = iterator
    for (blockGroup in I.Iterate(expr)) {
        match (pre(blockGroup)) {
            case VisitResult.SKIP => continue
            case VisitResult.STOP => return VisitResult.STOP
            case VisitResult.CONTINUE => ()
        }
        for (block in I.Iterate(blockGroup)) {
            for (innerExpr in I.Iterate(block)) {
                if (let VisitResult.STOP <- Walk(iterator, innerExpr, pre, post)) {
                    return VisitResult.STOP
                }
            }
        }
        if (let VisitResult.STOP <- post(blockGroup)) {
            return VisitResult.STOP
        }
    }
    return VisitResult.CONTINUE
}

public func Walk(expr: Expression, pre: VisitBlockActionFunc,
    post: VisitBlockActionFunc): VisitResult {
    return Walk(SimpleIterator(), expr, pre, post)
}

public func Walk<I>(iterator: I, expr: Expression, pre: VisitBlockActionFunc,
    post: VisitBlockActionFunc): VisitResult where I <: Iterator {
    let _ = iterator
    for (blockGroup in I.Iterate(expr)) {
        for (block in I.Iterate(blockGroup)) {
            match (pre(block)) {
                case VisitResult.SKIP => continue
                case VisitResult.STOP => return VisitResult.STOP
                case VisitResult.CONTINUE => ()
            }
            for (innerExpr in I.Iterate(block)) {
                if (let VisitResult.STOP <- Walk(iterator, innerExpr, pre, post)) {
                    return VisitResult.STOP
                }
            }
            if (let VisitResult.STOP <- post(block)) {
                return VisitResult.STOP
            }
        }
    }
    return VisitResult.CONTINUE
}

public func Walk(expr: Expression, pre: VisitExprActionFunc,
    post: VisitExprActionFunc): VisitResult {
    return Walk(SimpleIterator(), expr, pre, post)
}

public func Walk<I>(iterator: I, expr: Expression, pre: VisitExprActionFunc,
    post: VisitExprActionFunc): VisitResult where I <: Iterator {
    let _ = iterator
    match (pre(expr)) {
        case VisitResult.SKIP => return VisitResult.SKIP
        case VisitResult.STOP => return VisitResult.STOP
        case VisitResult.CONTINUE => ()
    }
    for (blockGroup in I.Iterate(expr)) {
        for (block in I.Iterate(blockGroup)) {
            for (innerExpr in I.Iterate(block)) {
                if (let VisitResult.STOP <- Walk(iterator, innerExpr, pre, post)) {
                    return VisitResult.STOP
                }
            }
        }
    }
    return post(expr)
}

public class Visitor {
    public static func Visit(root: Expression, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Expression, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit where I <: Iterator {
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit(root: Expression, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Expression, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit where I <: Iterator {
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit(root: Expression, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Expression, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit(root: Expression, pre: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Expression,
        pre: VisitExprActionFunc): Unit where I <: Iterator {
        let post = { _: Expression => VisitResult.CONTINUE }
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit(root: Expression, pre: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Expression,
        pre: VisitBlockActionFunc): Unit where I <: Iterator {
        let post = { _: Block => VisitResult.CONTINUE }
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit(root: Expression, pre: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Expression,
        pre: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        let post = { _: BlockGroup => VisitResult.CONTINUE }
        let _ = Walk(iterator, root, pre, post)
    }

    public static func Visit<T>(root: Expression, pre: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I, T>(iterator: I, root: Expression,
        pre: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        let wrapperPre = { child: Expression =>
            if (let Some(argTy) <- DynamicCast<T>(child)) {
                return pre(argTy)
            }
            return VisitResult.CONTINUE
        }
        let post = { _: Expression => VisitResult.CONTINUE }
        let _ = Walk(iterator, root, wrapperPre, post)
    }

    public static func Visit<T>(root: Expression, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I, T>(iterator: I, root: Expression, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        let wrapperPre = { child: Expression =>
            if (let Some(argTy) <- DynamicCast<T>(child)) {
                return pre(argTy)
            }
            return VisitResult.CONTINUE
        }
        let wrapperPost = { child: Expression =>
            if (let Some(argTy) <- DynamicCast<T>(child)) {
                return post(argTy)
            }
            return VisitResult.CONTINUE
        }
        let _ = Walk(iterator, root, wrapperPre, wrapperPost)
    }

    public static func Visit(root: Block, pre: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Block,
        pre: VisitExprActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: Block, pre: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Block,
        pre: VisitBlockActionFunc): Unit where I <: Iterator {
        match (pre(root)) {
            case VisitResult.SKIP => return
            case VisitResult.STOP => return
            case VisitResult.CONTINUE => ()
        }
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: Block, pre: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Block,
        pre: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit<T>(root: Block, pre: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I, T>(iterator: I, root: Block,
        pre: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: Block, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Block, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit(root: Block, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Block, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit where I <: Iterator {
        match (pre(root)) {
            case VisitResult.SKIP => return
            case VisitResult.STOP => return
            case VisitResult.CONTINUE => ()
        }
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
        let _ = post(root)
    }

    public static func Visit(root: Block, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Block, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit<T>(root: Block, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I, T>(iterator: I, root: Block, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup,
        pre: VisitExprActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup,
        pre: VisitBlockActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup,
        pre: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        match (pre(root)) {
            case VisitResult.SKIP => return
            case VisitResult.STOP => return
            case VisitResult.CONTINUE => ()
        }
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit<T>(root: BlockGroup, pre: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I, T>(iterator: I, root: BlockGroup,
        pre: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit where I <: Iterator {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit(root: BlockGroup, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: BlockGroup, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        match (pre(root)) {
            case VisitResult.SKIP => return
            case VisitResult.STOP => return
            case VisitResult.CONTINUE => ()
        }
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
        let _ = post(root)
    }

    public static func Visit<T>(root: BlockGroup, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I, T>(iterator: I, root: BlockGroup, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        for (child in I.Iterate(root)) {
            Visit(iterator, child, pre, post)
        }
    }

    public static func Visit(root: Function, pre: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Function,
        pre: VisitExprActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre)
        }
    }

    public static func Visit(root: Function, pre: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Function,
        pre: VisitBlockActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre)
        }
    }

    public static func Visit(root: Function, pre: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I>(iterator: I, root: Function,
        pre: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre)
        }
    }

    public static func Visit<T>(root: Function, pre: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre)
    }

    public static func Visit<I, T>(iterator: I, root: Function,
        pre: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre)
        }
    }

    public static func Visit(root: Function, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Function, pre: VisitExprActionFunc,
        post: VisitExprActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre, post)
        }
    }

    public static func Visit(root: Function, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Function, pre: VisitBlockActionFunc,
        post: VisitBlockActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre, post)
        }
    }

    public static func Visit(root: Function, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I>(iterator: I, root: Function, pre: VisitBlockGroupActionFunc,
        post: VisitBlockGroupActionFunc): Unit where I <: Iterator {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre, post)
        }
    }

    public static func Visit<T>(root: Function, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where T <: Expression {
        Visit(SimpleIterator(), root, pre, post)
    }

    public static func Visit<I, T>(iterator: I, root: Function, pre: (T) -> VisitResult,
        post: (T) -> VisitResult): Unit where I <: Iterator, T <: Expression {
        if (let Some(body) <- root.GetBody()) {
            Visit(iterator, body, pre, post)
        }
    }
}
