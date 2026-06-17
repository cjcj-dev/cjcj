package cangjie_compiler::chir

import std.collection.*

let AST2CHIR_LITERAL_NONE: Int64 = 0
let AST2CHIR_LITERAL_BOOL: Int64 = 1
let AST2CHIR_LITERAL_INT: Int64 = 2
let AST2CHIR_LITERAL_FLOAT: Int64 = 3
let AST2CHIR_LITERAL_UNIT: Int64 = 4

public class AST2CHIRResult {
    public let pkg: Package

    public init(pkg: Package) {
        this.pkg = pkg
    }
}

public class AST2CHIRGlobalSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let packageName: String
    public let ty: Type
    public let initialValue: Option<LiteralValue>
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let features: ArrayList<String> = ArrayList<String>()
    public var useRefStorage: Bool = false
    public var debugLocation: Option<DebugLocation> = None

    public init(name: String, ty: Type, srcCodeIdentifier!: String = "", rawMangledName!: String = "",
        packageName!: String = "", initialValue!: Option<LiteralValue> = None) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.packageName = packageName
        this.ty = ty
        this.initialValue = initialValue
    }

    public func AddAttribute(attr: Attribute): AST2CHIRGlobalSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddFeature(name: String): AST2CHIRGlobalSpec {
        AddStringUnique(features, name)
        return this
    }

    public func SetUseRefStorage(value: Bool): AST2CHIRGlobalSpec {
        useRefStorage = value
        return this
    }

    public func SetDebugLocation(loc: DebugLocation): AST2CHIRGlobalSpec {
        debugLocation = Some(loc)
        return this
    }
}

// Recursive statement/expression model for the real-expression body-lowering path. Models Int64 and
// Bool values: arithmetic/relational/logical ops, Int64 and Bool literals, `!`/`-` unary ops. This
// keeps `packages/chir` decoupled from `parse`/`frontend`: the frontend adapter builds these spec
// trees directly and hands them to CreateRealBody, which emits genuine runtime CHIR (Allocate/
// Constant/Store/Load/BinaryExpression/UnaryExpression/Branch/GoTo/Exit) -- no constant folding. The
// translator infers each value's CHIR type (Int64 vs Bool) from the materialized CHIR Value, so slot
// allocation, loads, and prints stay correctly typed.
//
// Expression spec: a tree of Int64-valued or Bool-valued expressions.
//   - LITERAL: an Int64 constant.  BOOL_LITERAL: a Bool constant.
//   - REF: a reference to a local slot by name (loaded with the slot's element type).
//   - BINARY: an arithmetic (ADD/SUB/MUL/...) op (Int64 result), a relational (LT/LE/GT/GE/EQUAL/
//             NOTEQUAL) op, or a logical AND/OR (Bool result) over two sub-expression specs.
//   - UNARY: `!` (NOT, Bool result) or `-` (NEG, Int64 result) over one sub-expression spec.
let AST2CHIR_EXPR_LITERAL: Int64 = 0
let AST2CHIR_EXPR_REF: Int64 = 1
let AST2CHIR_EXPR_BINARY: Int64 = 2
let AST2CHIR_EXPR_CALL: Int64 = 3
// BOOL_LITERAL: a Bool constant (`true`/`false`). UNARY: a unary op (`!` -> ExprKind.NOT,
// `-` -> ExprKind.NEG) over a single sub-expression carried in `lhs`. These extend the Int64-only
// model with first-class Bool values; the relational/AND/OR binary ops already produce Bool results.
let AST2CHIR_EXPR_BOOL_LITERAL: Int64 = 4
let AST2CHIR_EXPR_UNARY: Int64 = 5
// STR_LITERAL: a String constant. Modeled at runtime as a CString (i8*) value -- a private constant
// C-string global whose first-byte pointer is the value. The literal text is carried in `name`.
// String concatenation reuses BINARY with op == ADD; the translator detects CString operands at
// lowering time and emits a runtime concat (libc strlen/malloc/strcpy/strcat) instead of an int add.
let AST2CHIR_EXPR_STR_LITERAL: Int64 = 6

public class AST2CHIRExprSpec {
    public let kind: Int64
    public let literalValue: Int64       // LITERAL
    public let boolValue: Bool           // BOOL_LITERAL
    public let name: String              // REF / CALL (callee source identifier)
    public let op: ExprKind              // BINARY / UNARY
    public let lhs: Option<AST2CHIRExprSpec> // BINARY (left) / UNARY (operand)
    public let rhs: Option<AST2CHIRExprSpec> // BINARY (right)
    public let args: ArrayList<AST2CHIRExprSpec> // CALL argument expressions, in order

    private init(kind: Int64, literalValue: Int64, boolValue: Bool, name: String, op: ExprKind,
        lhs: Option<AST2CHIRExprSpec>, rhs: Option<AST2CHIRExprSpec>,
        args: ArrayList<AST2CHIRExprSpec>) {
        this.kind = kind
        this.literalValue = literalValue
        this.boolValue = boolValue
        this.name = name
        this.op = op
        this.lhs = lhs
        this.rhs = rhs
        this.args = args
    }

    public func IsLiteral(): Bool { return kind == AST2CHIR_EXPR_LITERAL }
    public func IsBoolLiteral(): Bool { return kind == AST2CHIR_EXPR_BOOL_LITERAL }
    public func IsRef(): Bool { return kind == AST2CHIR_EXPR_REF }
    public func IsBinary(): Bool { return kind == AST2CHIR_EXPR_BINARY }
    public func IsUnary(): Bool { return kind == AST2CHIR_EXPR_UNARY }
    public func IsCall(): Bool { return kind == AST2CHIR_EXPR_CALL }
    public func IsStrLiteral(): Bool { return kind == AST2CHIR_EXPR_STR_LITERAL }

    public static func Literal(value: Int64): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_LITERAL, value, false, "", ExprKind.ADD, None, None,
            ArrayList<AST2CHIRExprSpec>())
    }

    public static func BoolLit(value: Bool): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_BOOL_LITERAL, 0, value, "", ExprKind.ADD, None, None,
            ArrayList<AST2CHIRExprSpec>())
    }

    public static func Ref(name: String): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_REF, 0, false, name, ExprKind.ADD, None, None,
            ArrayList<AST2CHIRExprSpec>())
    }

    // STR_LITERAL: a String constant whose text is `text` (carried in the name slot). Lowered to a
    // CString (i8*) CHIR Constant -- the first-byte pointer of a private constant C-string global.
    public static func StrLit(text: String): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_STR_LITERAL, 0, false, text, ExprKind.ADD, None, None,
            ArrayList<AST2CHIRExprSpec>())
    }

    public static func Binary(op: ExprKind, lhs: AST2CHIRExprSpec, rhs: AST2CHIRExprSpec): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_BINARY, 0, false, "", op, Some(lhs), Some(rhs),
            ArrayList<AST2CHIRExprSpec>())
    }

    // UNARY: a unary op (`!` -> ExprKind.NOT, `-` -> ExprKind.NEG) over `operand`. The result type
    // mirrors the operand's type (Bool for `!`, Int64 for `-`).
    public static func Unary(op: ExprKind, operand: AST2CHIRExprSpec): AST2CHIRExprSpec {
        return AST2CHIRExprSpec(AST2CHIR_EXPR_UNARY, 0, false, "", op, Some(operand), None,
            ArrayList<AST2CHIRExprSpec>())
    }

    // CALL: invoke a user-defined top-level function named `calleeName` (the source identifier) with
    // `args` evaluated in order. The translator resolves the callee Function by name at lowering time
    // so call sites do not depend on lowering order.
    public static func Call(calleeName: String, args: ArrayList<AST2CHIRExprSpec>): AST2CHIRExprSpec {
        let copied = ArrayList<AST2CHIRExprSpec>()
        for (arg in args) {
            copied.add(arg)
        }
        return AST2CHIRExprSpec(AST2CHIR_EXPR_CALL, 0, false, calleeName, ExprKind.ADD, None, None, copied)
    }
}

// Statement spec:
//   - LET:    declare a local `name` (immutable `let` or mutable `var` per isVar) initialized to `expr`.
//   - ASSIGN: store `expr` into the existing slot `name` (var reassignment).
//   - RETURN: Exit with `expr` (Some) or nothing (None).
//   - IF:     branch on `cond`; run `thenBody` or `elseBody` statement lists.
//   - WHILE:  loop while `cond`; run `body` statement list each iteration.
let AST2CHIR_STMT_LET: Int64 = 0
let AST2CHIR_STMT_ASSIGN: Int64 = 1
let AST2CHIR_STMT_RETURN: Int64 = 2
let AST2CHIR_STMT_IF: Int64 = 3
let AST2CHIR_STMT_WHILE: Int64 = 4
let AST2CHIR_STMT_PRINT: Int64 = 5
let AST2CHIR_STMT_PRINT_STR: Int64 = 6
// FOR: a `for (name in <start>..<end>)` / `..=` range loop. The loop variable `name` is an Int64
// local; `expr` carries the start bound and `cond` the (exclusive or inclusive) end bound. isVar
// records inclusivity (true => `..=`, the end is included). `thenBody` is the loop body.
// BREAK / CONTINUE: loop control that jumps to the innermost loop's exit / continue target.
let AST2CHIR_STMT_FOR: Int64 = 7
let AST2CHIR_STMT_BREAK: Int64 = 8
let AST2CHIR_STMT_CONTINUE: Int64 = 9

public class AST2CHIRStmtSpec {
    public let kind: Int64
    public let name: String                       // LET / ASSIGN
    public let isVar: Bool                         // LET
    public let expr: Option<AST2CHIRExprSpec>      // LET / ASSIGN / RETURN
    public let cond: Option<AST2CHIRExprSpec>      // IF / WHILE
    public let thenBody: ArrayList<AST2CHIRStmtSpec> // IF then / WHILE body
    public let elseBody: ArrayList<AST2CHIRStmtSpec> // IF else

    private init(kind: Int64, name: String, isVar: Bool, expr: Option<AST2CHIRExprSpec>,
        cond: Option<AST2CHIRExprSpec>, thenBody: ArrayList<AST2CHIRStmtSpec>,
        elseBody: ArrayList<AST2CHIRStmtSpec>) {
        this.kind = kind
        this.name = name
        this.isVar = isVar
        this.expr = expr
        this.cond = cond
        this.thenBody = thenBody
        this.elseBody = elseBody
    }

    public func IsLet(): Bool { return kind == AST2CHIR_STMT_LET }
    public func IsAssign(): Bool { return kind == AST2CHIR_STMT_ASSIGN }
    public func IsReturn(): Bool { return kind == AST2CHIR_STMT_RETURN }
    public func IsIf(): Bool { return kind == AST2CHIR_STMT_IF }
    public func IsWhile(): Bool { return kind == AST2CHIR_STMT_WHILE }
    public func IsPrint(): Bool { return kind == AST2CHIR_STMT_PRINT }
    public func IsPrintStr(): Bool { return kind == AST2CHIR_STMT_PRINT_STR }
    public func IsFor(): Bool { return kind == AST2CHIR_STMT_FOR }
    public func IsBreak(): Bool { return kind == AST2CHIR_STMT_BREAK }
    public func IsContinue(): Bool { return kind == AST2CHIR_STMT_CONTINUE }

    public static func Let(name: String, expr: AST2CHIRExprSpec, isVar!: Bool = false): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_LET, name, isVar, Some(expr), None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    public static func Assign(name: String, expr: AST2CHIRExprSpec): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_ASSIGN, name, false, Some(expr), None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    public static func Return(expr: AST2CHIRExprSpec): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_RETURN, "", false, Some(expr), None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    public static func ReturnNone(): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_RETURN, "", false, None, None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    public static func If(cond: AST2CHIRExprSpec, thenBody: ArrayList<AST2CHIRStmtSpec>,
        elseBody: ArrayList<AST2CHIRStmtSpec>): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_IF, "", false, None, Some(cond), thenBody, elseBody)
    }

    public static func While(cond: AST2CHIRExprSpec, body: ArrayList<AST2CHIRStmtSpec>): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_WHILE, "", false, None, Some(cond), body,
            ArrayList<AST2CHIRStmtSpec>())
    }

    // FOR: `for (name in start..end)` (inclusive == false) or `for (name in start..=end)`
    // (inclusive == true). `start` and `end` are Int64 bound expressions; `body` is the loop body.
    public static func For(name: String, start: AST2CHIRExprSpec, end: AST2CHIRExprSpec,
        inclusive: Bool, body: ArrayList<AST2CHIRStmtSpec>): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_FOR, name, inclusive, Some(start), Some(end), body,
            ArrayList<AST2CHIRStmtSpec>())
    }

    public static func Break(): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_BREAK, "", false, None, None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    public static func Continue(): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_CONTINUE, "", false, None, None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    // PRINT: evaluate `expr` to a runtime Int64 Value and print it. `newline` (carried in the isVar
    // slot) distinguishes println (true, trailing newline) from print (false). Lowered to a real
    // printf at the value's materialization point in body flow -- not the entry-block side-channel.
    public static func Print(expr: AST2CHIRExprSpec, newline!: Bool = true): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_PRINT, "", newline, Some(expr), None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }

    // PRINT_STR: print a literal string `text` (carried in the name slot) in body flow order.
    // `newline` (carried in the isVar slot) distinguishes println (puts, trailing newline) from
    // print (fputs, no newline). Lowered to an in-body puts/fputs at an anchor point so it
    // interleaves correctly with runtime-value prints in a mixed body.
    public static func PrintStr(text: String, newline!: Bool = true): AST2CHIRStmtSpec {
        return AST2CHIRStmtSpec(AST2CHIR_STMT_PRINT_STR, text, newline, None, None,
            ArrayList<AST2CHIRStmtSpec>(), ArrayList<AST2CHIRStmtSpec>())
    }
}

public class AST2CHIRFunctionSpec {
    public let name: String
    public let srcCodeIdentifier: String
    public let rawMangledName: String
    public let packageName: String
    public let paramTypes: ArrayList<Type> = ArrayList<Type>()
    public let returnType: Type
    public let funcKind: FuncKind
    public let emitBody: Bool
    public let paramNames: ArrayList<String> = ArrayList<String>()
    public let attributes: ArrayList<Attribute> = ArrayList<Attribute>()
    public let features: ArrayList<String> = ArrayList<String>()
    public let genericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public let defaultParamFunctions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let genericInstantiations: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public var ownerTypeName: Option<String> = None
    public var isInstanceMember: Bool = false
    public var genericDeclName: Option<String> = None
    public var sourceFileKey: String = ""
    public var isCommonMatchedWithSpecific: Bool = false
    public var debugLocation: Option<DebugLocation> = None
    public var propertyLocation: Option<DebugLocation> = None
    public var hasVariableLenArg: Bool = false
    public var isCFunc: Bool = false
    public var hasLiteralReturn: Bool = false
    // When true, LowerFunction emits a real CHIR body from `bodyStatements` (Allocate/Constant/
    // Store/Load/BinaryExpression/Exit) instead of the literal-return/empty summary paths.
    // Default false so every existing (already-verified) path is byte-for-byte unchanged.
    public var hasRealBody: Bool = false
    public let bodyStatements: ArrayList<AST2CHIRStmtSpec> = ArrayList<AST2CHIRStmtSpec>()
    public var literalReturnKind: Int64 = AST2CHIR_LITERAL_NONE
    public var literalReturnBoolValue: Bool = false
    public var literalReturnIntValue: Int64 = 0
    public var literalReturnFloatValue: Float64 = 0.0
    // Literal strings to print when the function body runs, in source order. printNewlines is a
    // parallel list: true => println (puts, trailing newline), false => print (fputs, no newline).
    // printIsInt is a parallel list: true => integer print (printStrings holds the decimal text,
    // lowered via printf("%ld[\n]")); false => string print.
    public let printStrings: ArrayList<String> = ArrayList<String>()
    public let printNewlines: ArrayList<Bool> = ArrayList<Bool>()
    public let printIsInt: ArrayList<Bool> = ArrayList<Bool>()

    public init(name: String, paramTypes: ArrayList<Type>, returnType: Type, srcCodeIdentifier!: String = "",
        rawMangledName!: String = "", packageName!: String = "", funcKind!: FuncKind = FuncKind.DEFAULT,
        emitBody!: Bool = true) {
        this.name = name
        this.srcCodeIdentifier = srcCodeIdentifier
        this.rawMangledName = rawMangledName
        this.packageName = packageName
        for (ty in paramTypes) {
            this.paramTypes.add(ty)
        }
        this.returnType = returnType
        this.funcKind = funcKind
        this.emitBody = emitBody
    }

    public func AddPrintString(value: String, newline!: Bool = true, isInt!: Bool = false): AST2CHIRFunctionSpec {
        printStrings.add(value)
        printNewlines.add(newline)
        printIsInt.add(isInt)
        return this
    }

    public func EnableRealBody(): AST2CHIRFunctionSpec {
        hasRealBody = true
        return this
    }

    public func AddBodyStatement(stmt: AST2CHIRStmtSpec): AST2CHIRFunctionSpec {
        bodyStatements.add(stmt)
        return this
    }

    public func AddParamName(name: String): AST2CHIRFunctionSpec {
        paramNames.add(name)
        return this
    }

    public func AddAttribute(attr: Attribute): AST2CHIRFunctionSpec {
        AddAttributeUnique(attributes, attr)
        return this
    }

    public func AddFeature(name: String): AST2CHIRFunctionSpec {
        AddStringUnique(features, name)
        return this
    }

    public func AddGenericTypeParam(param: GenericType): AST2CHIRFunctionSpec {
        genericTypeParams.add(param)
        return this
    }

    public func SetOwnerType(name: String, isInstanceMember!: Bool = true): AST2CHIRFunctionSpec {
        ownerTypeName = Some(name)
        this.isInstanceMember = isInstanceMember
        return this
    }

    public func SetGenericDeclName(name: String): AST2CHIRFunctionSpec {
        genericDeclName = Some(name)
        return this
    }

    public func AddDefaultParamFunction(spec: AST2CHIRFunctionSpec): AST2CHIRFunctionSpec {
        defaultParamFunctions.add(spec)
        return this
    }

    public func AddGenericInstantiation(spec: AST2CHIRFunctionSpec): AST2CHIRFunctionSpec {
        genericInstantiations.add(spec)
        return this
    }

    public func SetSourceFileKey(key: String): AST2CHIRFunctionSpec {
        sourceFileKey = key
        return this
    }

    public func SetCommonMatchedWithSpecific(value: Bool): AST2CHIRFunctionSpec {
        isCommonMatchedWithSpecific = value
        return this
    }

    public func SetDebugLocation(loc: DebugLocation): AST2CHIRFunctionSpec {
        debugLocation = Some(loc)
        return this
    }

    public func SetPropertyLocation(loc: DebugLocation): AST2CHIRFunctionSpec {
        propertyLocation = Some(loc)
        return this
    }

    public func SetHasVariableLenArg(value: Bool): AST2CHIRFunctionSpec {
        hasVariableLenArg = value
        if (value) {
            isCFunc = true
        }
        return this
    }

    public func SetCFunc(value: Bool): AST2CHIRFunctionSpec {
        isCFunc = value
        return this
    }

    public func SetBoolLiteralReturn(value: Bool): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_BOOL
        literalReturnBoolValue = value
        return this
    }

    public func SetIntLiteralReturn(value: Int64): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_INT
        literalReturnIntValue = value
        return this
    }

    public func SetFloatLiteralReturn(value: Float64): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_FLOAT
        literalReturnFloatValue = value
        return this
    }

    public func SetUnitLiteralReturn(): AST2CHIRFunctionSpec {
        hasLiteralReturn = true
        literalReturnKind = AST2CHIR_LITERAL_UNIT
        return this
    }
}

public class AST2CHIRPackageSpec {
    public let name: String
    public let types: ArrayList<AST2CHIRNominalSpec> = ArrayList<AST2CHIRNominalSpec>()
    public let globals: ArrayList<AST2CHIRGlobalSpec> = ArrayList<AST2CHIRGlobalSpec>()
    public let functions: ArrayList<AST2CHIRFunctionSpec> = ArrayList<AST2CHIRFunctionSpec>()
    public let sourceFileIds: ArrayList<UInt32> = ArrayList<UInt32>()
    public let sourceFileNames: ArrayList<String> = ArrayList<String>()
    public var accessLevel: AccessLevel = AccessLevel.INVALID
    public var mergingSpecific: Bool = false
    public var packageInitFunction: Option<AST2CHIRFunctionSpec> = None
    public var packageLiteralInitFunction: Option<AST2CHIRFunctionSpec> = None

    public init(name: String) {
        this.name = name
    }

    public func SetMergingSpecific(value: Bool): AST2CHIRPackageSpec {
        mergingSpecific = value
        return this
    }

    public func SetAccessLevel(level: AccessLevel): AST2CHIRPackageSpec {
        accessLevel = level
        return this
    }

    public func RegisterSourceFile(fileId: UInt32, fileName: String): AST2CHIRPackageSpec {
        sourceFileIds.add(fileId)
        sourceFileNames.add(fileName)
        return this
    }

    public func AddType(spec: AST2CHIRNominalSpec): AST2CHIRPackageSpec {
        types.add(spec)
        return this
    }

    public func AddGlobal(spec: AST2CHIRGlobalSpec): AST2CHIRPackageSpec {
        globals.add(spec)
        return this
    }

    public func AddFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        functions.add(spec)
        return this
    }

    public func SetPackageInitFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        packageInitFunction = Some(spec)
        return this
    }

    public func SetPackageLiteralInitFunction(spec: AST2CHIRFunctionSpec): AST2CHIRPackageSpec {
        packageLiteralInitFunction = Some(spec)
        return this
    }
}

public class AST2CHIR {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CreateEmptyPackage(name: String): AST2CHIRResult {
        return AST2CHIRResult(builder.CreatePackage(name))
    }

    public func LowerPackage(spec: AST2CHIRPackageSpec): AST2CHIRResult {
        return AST2CHIRDeclTranslator(builder).LowerPackage(spec)
    }
}

public func ToCHIR(packageName: String, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).CreateEmptyPackage(packageName).pkg
}

public func ToCHIR(spec: AST2CHIRPackageSpec, builder: CHIRBuilder): Package {
    return AST2CHIR(builder).LowerPackage(spec).pkg
}
