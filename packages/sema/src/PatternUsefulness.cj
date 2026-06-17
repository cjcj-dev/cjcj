package cangjie_compiler::sema

import std.collection.*
import std.sort.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Position as BasicPosition
import cangjie_compiler::basic.Range as BasicRange

private func ToBasicPosition(pos: Position): BasicPosition {
    return BasicPosition(pos.fileID, pos.line, pos.column)
}

private func MakeBasicRange(begin: Position, end: Position): BasicRange {
    return BasicRange(ToBasicPosition(begin), ToBasicPosition(end))
}

private func MatchCasePatternRange(mc: MatchCase): BasicRange {
    if (mc.patterns.isEmpty()) {
        return MakeBasicRange(mc.begin, mc.end)
    }
    return MakeBasicRange(mc.patterns[0].begin, mc.patterns[mc.patterns.size - 1].end)
}

private enum PatternCtorKind {
    | UNIT
    | BOOLEAN
    | NON_EXHAUSTIVE_LITERAL
    | ENUM
    | NON_EXHAUSTIVE_ENUM
    | TUPLE
    | TYPE
    | WILDCARD
    | MISSING
    | OR
    | INVALID
}

private func PatternCtorKindIndex(kind: PatternCtorKind): Int64 {
    return match (kind) {
        case PatternCtorKind.UNIT => 0
        case PatternCtorKind.BOOLEAN => 1
        case PatternCtorKind.NON_EXHAUSTIVE_LITERAL => 2
        case PatternCtorKind.ENUM => 3
        case PatternCtorKind.NON_EXHAUSTIVE_ENUM => 4
        case PatternCtorKind.TUPLE => 5
        case PatternCtorKind.TYPE => 6
        case PatternCtorKind.WILDCARD => 7
        case PatternCtorKind.MISSING => 8
        case PatternCtorKind.OR => 9
        case PatternCtorKind.INVALID => 10
    }
}

extend PatternCtorKind <: Equatable<PatternCtorKind> {
    public operator func ==(right: PatternCtorKind): Bool {
        return PatternCtorKindIndex(this) == PatternCtorKindIndex(right)
    }

    public operator func !=(right: PatternCtorKind): Bool {
        return !(this == right)
    }
}

private class PatternCtor {
    public var kind: PatternCtorKind
    public var arity: Int64
    public var boolValue: Bool = false
    public var literal: Option<LitConstExpr> = None
    public var enumIdentifier: String = ""
    public var enumTy: Option<Ty> = None
    public var typeTy: Option<Ty> = None

    public init(kind: PatternCtorKind, arity: Int64) {
        this.kind = kind
        this.arity = arity
    }

    public static func UnitCtor(): PatternCtor {
        return PatternCtor(PatternCtorKind.UNIT, 0)
    }

    public static func Boolean(value: Bool): PatternCtor {
        let ctor = PatternCtor(PatternCtorKind.BOOLEAN, 0)
        ctor.boolValue = value
        return ctor
    }

    public static func NonExhaustiveLiteral(value: LitConstExpr): PatternCtor {
        let ctor = PatternCtor(PatternCtorKind.NON_EXHAUSTIVE_LITERAL, 0)
        ctor.literal = value
        return ctor
    }

    public static func NonExhaustiveEnum(): PatternCtor {
        return PatternCtor(PatternCtorKind.NON_EXHAUSTIVE_ENUM, 0)
    }

    public static func Tuple(size: Int64): PatternCtor {
        return PatternCtor(PatternCtorKind.TUPLE, size)
    }

    public static func Enum(decl: Decl, ty: Ty): PatternCtor {
        if (!Ty.IsTyCorrect(ty)) {
            return PatternCtor.Invalid()
        }
        var numArgs: Int64 = 0
        if (let Some(fd) <- (decl as FuncDecl)) {
            if (let Some(body) <- fd.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    numArgs = body.paramLists[0].params.size
                }
            }
        }
        let ctor = PatternCtor(PatternCtorKind.ENUM, numArgs)
        ctor.enumIdentifier = decl.identifier.Val()
        ctor.enumTy = ty
        return ctor
    }

    public static func Type(ty: Ty): PatternCtor {
        let ctor = PatternCtor(PatternCtorKind.TYPE, 0)
        ctor.typeTy = ty
        return ctor
    }

    public static func Wildcard(): PatternCtor {
        return PatternCtor(PatternCtorKind.WILDCARD, 0)
    }

    public static func Missing(): PatternCtor {
        return PatternCtor(PatternCtorKind.MISSING, 0)
    }

    public static func Or(size: Int64): PatternCtor {
        return PatternCtor(PatternCtorKind.OR, size)
    }

    public static func Invalid(): PatternCtor {
        return PatternCtor(PatternCtorKind.INVALID, 0)
    }

    public static func FromLiteral(expr: Expr): PatternCtor {
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return PatternCtor.FromLitConstExpr(lit)
        }
        return PatternCtor.Invalid()
    }

    public static func FromLitConstExpr(lit: LitConstExpr): PatternCtor {
        if (lit.kind == LitConstKind.UNIT) {
            return PatternCtor.UnitCtor()
        }
        if (lit.kind == LitConstKind.BOOL) {
            return PatternCtor.Boolean(lit.stringValue == "true")
        }
        return PatternCtor.NonExhaustiveLiteral(lit)
    }

    public func ToString(): String {
        return match (kind) {
            case PatternCtorKind.UNIT => "()"
            case PatternCtorKind.BOOLEAN => if (boolValue) { "true" } else { "false" }
            case PatternCtorKind.ENUM => enumIdentifier
            case PatternCtorKind.WILDCARD => "_"
            case PatternCtorKind.MISSING => "_"
            case PatternCtorKind.NON_EXHAUSTIVE_LITERAL => if (let Some(lit) <- literal) { lit.stringValue } else { "_" }
            case PatternCtorKind.NON_EXHAUSTIVE_ENUM => "_"
            case PatternCtorKind.TYPE => if (let Some(ty) <- typeTy) { ty.String() } else { "invalid" }
            case _ => "invalid"
        }
    }

    public func IsCoveredBy(typeManager: TypeManager, other: PatternCtor): Bool {
        if (other.kind == PatternCtorKind.WILDCARD || other.kind == PatternCtorKind.MISSING) {
            return true
        }
        if (kind == PatternCtorKind.WILDCARD || kind == PatternCtorKind.MISSING) {
            return false
        }
        if (kind == PatternCtorKind.UNIT) {
            return other.kind == PatternCtorKind.UNIT
        }
        if (kind == PatternCtorKind.BOOLEAN) {
            return other.kind == PatternCtorKind.BOOLEAN && boolValue == other.boolValue
        }
        if (kind == PatternCtorKind.NON_EXHAUSTIVE_LITERAL) {
            if (other.kind != PatternCtorKind.NON_EXHAUSTIVE_LITERAL) {
                return false
            }
            if (let Some(left) <- literal) {
                if (let Some(right) <- other.literal) {
                    return LitConstExprEq(left, right)
                }
            }
            return false
        }
        if (kind == PatternCtorKind.NON_EXHAUSTIVE_ENUM) {
            return other.kind == PatternCtorKind.NON_EXHAUSTIVE_ENUM || other.kind == PatternCtorKind.WILDCARD
        }
        if (kind == PatternCtorKind.ENUM) {
            if (other.kind != PatternCtorKind.ENUM || enumIdentifier != other.enumIdentifier) {
                return false
            }
            if (let Some(leftTy) <- enumTy) {
                if (let Some(rightTy) <- other.enumTy) {
                    return leftTy.IsEnum() == rightTy.IsEnum() && leftTy.typeArgs.size == rightTy.typeArgs.size
                }
            }
            return false
        }
        if (kind == PatternCtorKind.TUPLE) {
            return other.kind == PatternCtorKind.TUPLE
        }
        if (kind == PatternCtorKind.TYPE) {
            if (other.kind != PatternCtorKind.TYPE) {
                return false
            }
            if (let Some(leftTy) <- typeTy) {
                if (let Some(rightTy) <- other.typeTy) {
                    return typeManager.IsSubtype(leftTy, rightTy, implicitBoxed: true, allowOptionBox: false)
                }
            }
        }
        return false
    }
}

private class DestructedPattern {
    public var ctor: PatternCtor
    public let subPatterns: ArrayList<DestructedPattern> = ArrayList<DestructedPattern>()
    public var goalTy: Ty
    public var node: Option<Pattern>

    public init(ctor: PatternCtor, subPatterns: ArrayList<DestructedPattern>, goalTy: Ty, node: Option<Pattern>) {
        this.ctor = ctor
        for (subPattern in subPatterns) {
            this.subPatterns.add(subPattern)
        }
        this.goalTy = goalTy
        this.node = node
    }

    public static func FromPattern(typeManager: TypeManager, goalTy: Ty, pattern: Pattern): DestructedPattern {
        if (!Ty.IsTyCorrect(pattern.GetTy()) || !IsValidUsefulnessTy(pattern.GetTy())) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), pattern)
        }
        let goal = typeManager.ReplaceThisTy(goalTy)
        if (let Some(constPattern) <- (pattern as ConstPattern)) {
            return FromConstPattern(constPattern)
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            return FromTuplePattern(typeManager, tuplePattern)
        }
        if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            return FromEnumPattern(typeManager, enumPattern)
        }
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            return FromTypePattern(typeManager, goal, typePattern)
        }
        if (pattern.astKind == ASTKind.WILDCARD_PATTERN || pattern.astKind == ASTKind.VAR_PATTERN) {
            return DestructedPattern(PatternCtor.Wildcard(), ArrayList<DestructedPattern>(),
                pattern.GetTy() ?? TypeManager.GetInvalidTy(), pattern)
        }
        if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
            if (let Some(inner) <- varOrEnum.pattern) {
                return FromPattern(typeManager, goal, inner)
            }
        }
        return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
            TypeManager.GetInvalidTy(), pattern)
    }

    public static func FromPatterns(typeManager: TypeManager, goalTy: Ty,
        patterns: ArrayList<Pattern>): DestructedPattern {
        if (patterns.isEmpty()) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), None)
        }
        var hasInvalid = false
        for (pattern in patterns) {
            if (!Ty.IsTyCorrect(pattern.GetTy()) || !IsValidUsefulnessTy(pattern.GetTy())) {
                hasInvalid = true
                break
            }
        }
        if (hasInvalid) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), patterns[0])
        }
        if (patterns.size == 1) {
            return FromPattern(typeManager, goalTy, patterns[0])
        }
        let sub = ArrayList<DestructedPattern>()
        for (pattern in patterns) {
            sub.add(FromPattern(typeManager, goalTy, pattern))
        }
        return DestructedPattern(PatternCtor.Or(sub.size), sub, goalTy, patterns[0])
    }

    public func ToString(): String {
        if (ctor.kind == PatternCtorKind.TUPLE) {
            return SubPatternsToString(subPatterns)
        }
        if (ctor.kind == PatternCtorKind.ENUM) {
            if (ctor.arity > 0) {
                return ctor.ToString() + SubPatternsToString(subPatterns)
            }
            return ctor.ToString()
        }
        return ctor.ToString()
    }

    public func IsUnreachableTypePattern(typeManager: TypeManager): Bool {
        if (ctor.kind != PatternCtorKind.TYPE) {
            return false
        }
        if (let Some(patternTy) <- ctor.typeTy) {
            if (patternTy.IsNothing()) {
                return true
            }
            if (goalTy.HasGeneric() || patternTy.HasGeneric() || !IsSealedLike(goalTy) || !IsSealedLike(patternTy)) {
                return false
            }
            let goalIsSubtype = typeManager.IsSubtype(goalTy, patternTy, implicitBoxed: true, allowOptionBox: false)
            let patternIsSubtype = typeManager.IsSubtype(patternTy, goalTy, implicitBoxed: true, allowOptionBox: false)
            return !goalIsSubtype && !patternIsSubtype
        }
        return true
    }

    public func AllWildcard(): Bool {
        if (ctor.kind == PatternCtorKind.WILDCARD) {
            return true
        }
        if (ctor.kind == PatternCtorKind.TUPLE) {
            for (subPattern in subPatterns) {
                if (!subPattern.AllWildcard()) {
                    return false
                }
            }
            return true
        }
        return false
    }

    public func Specialize(otherCtor: PatternCtor): ArrayList<DestructedPattern> {
        if (ctor.kind == PatternCtorKind.WILDCARD) {
            return SpecializeWildcard(goalTy, otherCtor)
        }
        let out = ArrayList<DestructedPattern>()
        for (subPattern in subPatterns) {
            out.add(subPattern)
        }
        return out
    }

    private static func FromConstPattern(pattern: ConstPattern): DestructedPattern {
        if (let Some(lit) <- pattern.literal) {
            return DestructedPattern(PatternCtor.FromLiteral(lit), ArrayList<DestructedPattern>(),
                pattern.GetTy() ?? TypeManager.GetInvalidTy(), pattern)
        }
        return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
            TypeManager.GetInvalidTy(), pattern)
    }

    private static func FromTuplePattern(typeManager: TypeManager, pattern: TuplePattern): DestructedPattern {
        let sub = ArrayList<DestructedPattern>()
        if (let Some(tupleTy) <- ((pattern.GetTy() ?? TypeManager.GetInvalidTy()) as TupleTy)) {
            var idx: Int64 = 0
            while (idx < tupleTy.typeArgs.size && idx < pattern.patterns.size) {
                sub.add(FromPattern(typeManager, tupleTy.typeArgs[idx], pattern.patterns[idx]))
                idx++
            }
        }
        return DestructedPattern(PatternCtor.Tuple(sub.size), sub,
            pattern.GetTy() ?? TypeManager.GetInvalidTy(), pattern)
    }

    private static func FromEnumPattern(typeManager: TypeManager, pattern: EnumPattern): DestructedPattern {
        if (let None <- pattern.constructor) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), pattern)
        }
        let constructor = pattern.constructor.getOrThrow()
        if (let None <- constructor.GetTarget()) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), pattern)
        }
        let target = constructor.GetTarget().getOrThrow()
        if (!Ty.IsTyCorrect(pattern.GetTy())) {
            return DestructedPattern(PatternCtor.Invalid(), ArrayList<DestructedPattern>(),
                TypeManager.GetInvalidTy(), pattern)
        }
        let patternTy = pattern.GetTy().getOrThrow()
        let typeMapping = MultiTypeSubst()
        typeManager.GenerateGenericMapping(typeMapping, patternTy)
        var instTy: Ty = TypeManager.GetInvalidTy()
        if (let Some(targetTy) <- target.GetTy()) {
            instTy = typeManager.GetBestInstantiatedTy(targetTy, typeMapping)
        }
        let ctor = PatternCtor.Enum(target, instTy)
        if (let Some(funcTy) <- (instTy as FuncTy)) {
            let sub = ArrayList<DestructedPattern>()
            var idx: Int64 = 0
            while (idx < funcTy.paramTys.size && idx < pattern.patterns.size) {
                sub.add(FromPattern(typeManager, funcTy.paramTys[idx], pattern.patterns[idx]))
                idx++
            }
            return DestructedPattern(ctor, sub, patternTy, pattern)
        }
        return DestructedPattern(ctor, ArrayList<DestructedPattern>(), patternTy, pattern)
    }

    private static func FromTypePattern(typeManager: TypeManager, goalTy: Ty, pattern: TypePattern): DestructedPattern {
        let patternTy = pattern.GetTy() ?? TypeManager.GetInvalidTy()
        if (!patternTy.IsNothing() &&
            typeManager.IsSubtype(goalTy, patternTy, implicitBoxed: true, allowOptionBox: false)) {
            return DestructedPattern(PatternCtor.Wildcard(), ArrayList<DestructedPattern>(), goalTy, pattern)
        }
        return DestructedPattern(PatternCtor.Type(patternTy), ArrayList<DestructedPattern>(), goalTy, pattern)
    }

    private static func SubPatternsToString(patterns: ArrayList<DestructedPattern>): String {
        if (patterns.isEmpty()) {
            return "()"
        }
        let parts = ArrayList<String>()
        for (pattern in patterns) {
            parts.add(pattern.ToString())
        }
        return "(" + JoinStrings(parts, ", ") + ")"
    }

    private static func SpecializeWildcard(ty: Ty, ctor: PatternCtor): ArrayList<DestructedPattern> {
        let sub = ArrayList<DestructedPattern>()
        if (ctor.kind == PatternCtorKind.TUPLE) {
            var idx: Int64 = 0
            while (idx < ctor.arity && idx < ty.typeArgs.size) {
                sub.add(DestructedPattern(PatternCtor.Wildcard(), ArrayList<DestructedPattern>(), ty.typeArgs[idx], None))
                idx++
            }
            return sub
        }
        if (ctor.kind == PatternCtorKind.ENUM) {
            if (let Some(ctorTy) <- ctor.enumTy) {
                if (ctorTy.IsEnum()) {
                    return sub
                }
                if (let Some(funcTy) <- (ctorTy as FuncTy)) {
                    for (paramTy in funcTy.paramTys) {
                        sub.add(DestructedPattern(PatternCtor.Wildcard(), ArrayList<DestructedPattern>(), paramTy, None))
                    }
                }
            }
            return sub
        }
        return sub
    }
}

private class PatternStack {
    public let stack: ArrayList<DestructedPattern> = ArrayList<DestructedPattern>()

    public init() {}

    public init(pattern: DestructedPattern) {
        stack.add(pattern)
    }

    public init(values: ArrayList<DestructedPattern>) {
        for (value in values) {
            stack.add(value)
        }
    }

    public func IsEmpty(): Bool {
        return stack.isEmpty()
    }

    public func AllWildcard(): Bool {
        for (pattern in stack) {
            if (!pattern.AllWildcard()) {
                return false
            }
        }
        return true
    }

    public func Size(): Int64 {
        return stack.size
    }

    public func Head(): DestructedPattern {
        return stack[stack.size - 1]
    }

    public func Specialize(ctor: PatternCtor): PatternStack {
        let newStack = ArrayList<DestructedPattern>()
        if (!stack.isEmpty()) {
            var idx: Int64 = 0
            while (idx < stack.size - 1) {
                newStack.add(stack[idx])
                idx++
            }
            let headSub = Head().Specialize(ctor)
            var subIdx = headSub.size - 1
            while (subIdx >= 0) {
                newStack.add(headSub[subIdx])
                subIdx--
            }
        }
        return PatternStack(newStack)
    }

    public func Apply(ctor: PatternCtor, ty: Ty): PatternStack {
        let subPatterns = ArrayList<DestructedPattern>()
        var taken: Int64 = 0
        var readIdx = stack.size - 1
        while (taken < ctor.arity && readIdx >= 0) {
            subPatterns.add(stack[readIdx])
            readIdx--
            taken++
        }
        let newStack = ArrayList<DestructedPattern>()
        var keepCount = stack.size - ctor.arity
        if (keepCount < 0) {
            keepCount = 0
        }
        var idx: Int64 = 0
        while (idx < keepCount) {
            newStack.add(stack[idx])
            idx++
        }
        newStack.add(DestructedPattern(ctor, subPatterns, ty, None))
        return PatternStack(newStack)
    }

    public func ExpandOr(): ArrayList<PatternStack> {
        let results = ArrayList<PatternStack>()
        if (IsEmpty() || Head().ctor.kind != PatternCtorKind.OR) {
            return results
        }
        for (newHead in Head().subPatterns) {
            let newStack = ArrayList<DestructedPattern>()
            var idx: Int64 = 0
            while (idx < stack.size - 1) {
                newStack.add(stack[idx])
                idx++
            }
            newStack.add(newHead)
            results.add(PatternStack(newStack))
        }
        return results
    }
}

private class PatternMatrix {
    public let rows: ArrayList<PatternStack> = ArrayList<PatternStack>()

    public init() {}

    public init(other: PatternMatrix) {
        for (row in other.rows) {
            rows.add(row)
        }
    }

    public func IsEmpty(): Bool {
        return rows.isEmpty()
    }

    public func HasSingleRowAndAllWildcard(): Bool {
        return rows.size == 1 && rows[0].AllWildcard()
    }

    public func MissingAll(): Bool {
        for (row in rows) {
            if (!row.IsEmpty()) {
                return false
            }
        }
        return true
    }

    public func HeadsAllWildcard(): Bool {
        if (rows.isEmpty()) {
            return false
        }
        for (row in rows) {
            if (row.IsEmpty() || !row.Head().AllWildcard()) {
                return false
            }
        }
        return true
    }

    public func Specialize(typeManager: TypeManager, ctor: PatternCtor): PatternMatrix {
        let newMatrix = PatternMatrix()
        for (row in rows) {
            if (!row.IsEmpty() && ctor.IsCoveredBy(typeManager, row.Head().ctor)) {
                newMatrix.rows.add(row.Specialize(ctor))
            }
        }
        return newMatrix
    }

    public func AppendRows(newRows: ArrayList<PatternStack>): Unit {
        for (row in newRows) {
            rows.add(row)
        }
    }
}

private class UsefulnessChecker {
    public let diag: BasicDiagnosticEngine
    public let typeManager: TypeManager
    public var matrix: PatternMatrix
    public var keepABIStable: Bool = true

    public init(diag: BasicDiagnosticEngine, typeManager: TypeManager) {
        this.diag = diag
        this.typeManager = typeManager
        this.matrix = PatternMatrix()
    }

    public init(diag: BasicDiagnosticEngine, typeManager: TypeManager, matrix: PatternMatrix) {
        this.diag = diag
        this.typeManager = typeManager
        this.matrix = matrix
    }

    public func FindWitnesses(vec: PatternStack): ArrayList<PatternStack> {
        if (vec.IsEmpty()) {
            let out = ArrayList<PatternStack>()
            if (matrix.IsEmpty()) {
                out.add(PatternStack())
            }
            return out
        }
        if (matrix.HasSingleRowAndAllWildcard()) {
            return ArrayList<PatternStack>()
        }
        let head = vec.Head()
        if (head.IsUnreachableTypePattern(typeManager)) {
            return ArrayList<PatternStack>()
        }
        if (head.ctor.kind == PatternCtorKind.WILDCARD) {
            return FindWitnessesForWildcard(vec)
        }
        if (head.ctor.kind == PatternCtorKind.OR) {
            return FindWitnessesForExpandedOr(vec.ExpandOr())
        }
        if (head.ctor.kind == PatternCtorKind.TYPE) {
            let wildcard = PatternStack(DestructedPattern(PatternCtor.Wildcard(),
                ArrayList<DestructedPattern>(), head.goalTy, None))
            if (FindWitnessesForWildcard(wildcard).isEmpty()) {
                return ArrayList<PatternStack>()
            }
        }
        return FindWitnessesBySpecialization(vec, head.ctor)
    }

    public func AddWitnesses(witnesses: ArrayList<PatternStack>): Unit {
        matrix.AppendRows(witnesses)
    }

    private static func SplitWildcard(typeManager: TypeManager, ty: Ty, matrix: PatternMatrix,
        isABIStable: Bool): ArrayList<PatternCtor> {
        let ctors = ArrayList<PatternCtor>()
        if (matrix.MissingAll()) {
            ctors.add(PatternCtor.Wildcard())
            return ctors
        }
        if (let Some(sealedTy) <- AsSealedLikeClassLikeTy(ty)) {
            if (!ty.IsCType() && !isABIStable) {
                SplitWildcardForSealed(ctors, sealedTy)
                return ctors
            }
        }
        if (!Ty.IsTyCorrect(ty)) {
            ctors.add(PatternCtor.Missing())
            return ctors
        }
        if (ty.IsUnit()) {
            ctors.add(PatternCtor.UnitCtor())
            return ctors
        }
        if (ty.IsBoolean()) {
            ctors.add(PatternCtor.Boolean(false))
            ctors.add(PatternCtor.Boolean(true))
            return ctors
        }
        if (ty.IsTuple()) {
            ctors.add(PatternCtor.Tuple(ty.typeArgs.size))
            return ctors
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            let subst = MultiTypeSubst()
            typeManager.GenerateGenericMapping(subst, ty)
            if (let Some(enumDecl) <- enumTy.declPtr) {
                for (decl in enumDecl.constructors) {
                    if (let Some(targetTy) <- decl.GetTy()) {
                        if (decl.astKind == ASTKind.FUNC_DECL) {
                            ctors.add(PatternCtor.Enum(decl, typeManager.GetBestInstantiatedTy(targetTy, subst)))
                        } else {
                            ctors.add(PatternCtor.Enum(decl, ty))
                        }
                    }
                }
            }
            if (enumTy.IsNonExhaustive()) {
                ctors.add(PatternCtor.NonExhaustiveEnum())
            }
            return ctors
        }
        ctors.add(PatternCtor.Missing())
        return ctors
    }

    private static func SplitWildcardForSealed(ctors: ArrayList<PatternCtor>, sealedTy: ClassLikeTy): Unit {
        let directSubtypes = ArrayList<Ty>()
        for (subTy in sealedTy.directSubtypes) {
            directSubtypes.add(subTy)
        }
        sort(directSubtypes, by: { left: Ty, right: Ty =>
            if (CompTyByNames(Some(left), Some(right))) {
                Ordering.LT
            } else if (CompTyByNames(Some(right), Some(left))) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (subTy in directSubtypes) {
            if (let Some(subSealed) <- AsSealedLikeClassLikeTy(subTy)) {
                if (!subTy.IsCType()) {
                    SplitWildcardForSealed(ctors, subSealed)
                    continue
                }
            }
            ctors.add(PatternCtor.Type(subTy))
        }
        if (let Some(classTy) <- (sealedTy as ClassTy)) {
            if (let Some(classDecl) <- classTy.declPtr) {
                if (!classDecl.TestAttr(Attribute.ABSTRACT)) {
                    ctors.add(PatternCtor.Type(sealedTy))
                }
            }
        }
    }

    private func FindWitnessesForWildcard(vec: PatternStack): ArrayList<PatternStack> {
        let head = vec.Head()
        if (matrix.HeadsAllWildcard()) {
            return FindWitnessesBySpecialization(vec, head.ctor)
        }
        let goalTy = head.goalTy
        if (goalTy.IsTuple()) {
            let tupleCtor = PatternCtor.Tuple(goalTy.typeArgs.size)
            let stack = vec.Specialize(tupleCtor).Apply(tupleCtor, goalTy)
            return FindWitnesses(stack)
        }
        let witnesses = ArrayList<PatternStack>()
        let ctors = UsefulnessChecker.SplitWildcard(typeManager, goalTy, matrix, keepABIStable)
        for (ctor in ctors) {
            let subWitnesses = FindWitnessesBySpecialization(vec, ctor)
            for (witness in subWitnesses) {
                witnesses.add(witness)
            }
        }
        return witnesses
    }

    private func FindWitnessesBySpecialization(vec: PatternStack, ctor: PatternCtor): ArrayList<PatternStack> {
        let witnesses = ArrayList<PatternStack>()
        let newChecker = UsefulnessChecker(diag, typeManager, matrix.Specialize(typeManager, ctor))
        let stack = vec.Specialize(ctor)
        let subWitnesses = newChecker.FindWitnesses(stack)
        for (witness in subWitnesses) {
            witnesses.add(witness.Apply(ctor, vec.Head().goalTy))
        }
        return witnesses
    }

    private func FindWitnessesForExpandedOr(vecs: ArrayList<PatternStack>): ArrayList<PatternStack> {
        let newChecker = UsefulnessChecker(diag, typeManager, PatternMatrix(matrix))
        let unreachables = ArrayList<Pattern>()
        let totalWitnesses = ArrayList<PatternStack>()
        for (vec in vecs) {
            let witnesses = newChecker.FindWitnesses(vec)
            if (witnesses.isEmpty()) {
                if (let Some(node) <- vec.Head().node) {
                    unreachables.add(node)
                }
            } else {
                for (witness in witnesses) {
                    totalWitnesses.add(witness)
                }
                newChecker.AddWitnesses(witnesses)
            }
        }
        if (!totalWitnesses.isEmpty()) {
            for (unreachable in unreachables) {
                unreachable.EnableAttr(Attribute.UNREACHABLE)
                SemaDiag(diag, BasicDiagKindRefactor.sema_unreachable_pattern, unreachable)
            }
        }
        return totalWitnesses
    }
}

private func IsValidUsefulnessTy(tyOpt: Option<Ty>): Bool {
    if (let Some(ty) <- tyOpt) {
        return IsValidUsefulnessTy(ty)
    }
    return false
}

private func IsValidUsefulnessTy(ty: Ty): Bool {
    if (!Ty.IsTyCorrect(ty)) {
        return false
    }
    if (let Some(enumTy) <- (ty as EnumTy)) {
        if (let None <- enumTy.declPtr) {
            return false
        }
        let enumDecl = enumTy.declPtr.getOrThrow()
        for (ctor in enumDecl.constructors) {
            if (!Ty.IsTyCorrect(ctor.GetTy())) {
                return false
            }
        }
    }
    return true
}

private func HasVisibleInit(classDecl: ClassDecl): Bool {
    if (let Some(body) <- classDecl.body) {
        for (decl in body.decls) {
            if (decl.TestAttr(Attribute.CONSTRUCTOR) && decl.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) {
                return true
            }
        }
    }
    return false
}

private func IsSealedLike(ty: Ty): Bool {
    if (let Some(classTy) <- (ty as ClassTy)) {
        if (let Some(classDecl) <- classTy.declPtr) {
            return classDecl.TestAttr(Attribute.SEALED) || classDecl.TestAttr(Attribute.PRIVATE) ||
                !HasVisibleInit(classDecl)
        }
        return false
    }
    if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
        if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
            return interfaceDecl.TestAttr(Attribute.SEALED) || interfaceDecl.TestAttr(Attribute.PRIVATE)
        }
        return false
    }
    return true
}

private func AsSealedLikeClassLikeTy(ty: Ty): Option<ClassLikeTy> {
    if (!ty.IsClassLike() || !ty.typeArgs.isEmpty()) {
        return None
    }
    if (!IsSealedLike(ty)) {
        return None
    }
    return ty as ClassLikeTy
}

private func LitConstExprEq(left: LitConstExpr, right: LitConstExpr): Bool {
    if (left.kind != right.kind) {
        return false
    }
    if (left.kind == LitConstKind.UNIT || left.kind == LitConstKind.NONE) {
        return true
    }
    if (left.kind == LitConstKind.BOOL) {
        return left.constNumValue.asBoolean == right.constNumValue.asBoolean
    }
    if (left.kind == LitConstKind.INTEGER || left.kind == LitConstKind.RUNE_BYTE) {
        return left.constNumValue.asInt.Uint64() == right.constNumValue.asInt.Uint64()
    }
    if (left.kind == LitConstKind.FLOAT) {
        return left.constNumValue.asFloat.value == right.constNumValue.asFloat.value
    }
    if (left.kind == LitConstKind.RUNE || left.kind == LitConstKind.STRING || left.kind == LitConstKind.JSTRING) {
        return left.stringValue == right.stringValue
    }
    return false
}

private func CollectCasePatterns(patterns: ArrayList<Pattern>): ArrayList<Pattern> {
    let out = ArrayList<Pattern>()
    for (pattern in patterns) {
        out.add(pattern)
    }
    return out
}

public func CheckMatchExprHasSelectorExhaustivenessAndReachability(
    diag: BasicDiagnosticEngine, typeManager: TypeManager, me: MatchExpr): Bool {
    if (let None <- me.selector) {
        return true
    }
    let selector = me.selector.getOrThrow()
    if (!IsValidUsefulnessTy(selector.GetTy())) {
        return true
    }
    let selectorTy = selector.GetTy().getOrThrow()
    let checker = UsefulnessChecker(diag, typeManager)
    for (mc in me.matchCases) {
        if (mc.patterns.isEmpty()) {
            continue
        }
        for (pattern in mc.patterns) {
            if (Ty.IsInitialTy(pattern.GetTy())) {
                pattern.SetTy(typeManager.TryGreedySubst(selectorTy))
            }
        }
        let vec = PatternStack(DestructedPattern.FromPatterns(typeManager,
            typeManager.TryGreedySubst(selectorTy), CollectCasePatterns(mc.patterns)))
        let witnesses = checker.FindWitnesses(vec)
        if (!witnesses.isEmpty()) {
            if (let None <- mc.patternGuard) {
                checker.AddWitnesses(witnesses)
            }
        } else {
            mc.EnableAttr(Attribute.UNREACHABLE)
            let _ = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_unreachable_pattern,
                MatchCasePatternRange(mc))
        }
    }
    let stack = PatternStack(DestructedPattern(PatternCtor.Wildcard(),
        ArrayList<DestructedPattern>(), typeManager.TryGreedySubst(selectorTy), None))
    let witnesses = checker.FindWitnesses(stack)
    if (witnesses.isEmpty()) {
        return true
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_nonexhuastive_patterns, selector.begin,
        arguments: [selectorTy.String()])
    for (witness in witnesses) {
        if (witness.Size() == 1) {
            builder.AddNote(witness.Head().ToString() + " is not covered")
        }
    }
    return false
}

public func SelfhostPortStatus_PatternUsefulness(): Bool {
    return true
}
