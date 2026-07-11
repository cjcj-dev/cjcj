package cjcj::sema.GenericInstantiation

import std.collection.*
import cjcj::ast.*
import cjcj::ast.AnnotationKind as AstAnnotationKind
import cjcj::sema.*
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::option.OptimizationLevel
import cjcj::option.OutputMode
import cjcj::option.enumIndex
import cjcj::utils.CJC_ASSERT

private var currentOptLevel: OptimizationLevel = OptimizationLevel.O0
private var currentOutputMode: OutputMode = OutputMode.EXECUTABLE

private let ins2generic: HashMap<Int64, Decl> = HashMap<Int64, Decl>()
private let generic2ins: HashMap<Int64, ArrayList<Decl>> = HashMap<Int64, ArrayList<Decl>>()

public type ReversedTypeSubst = TreeMap<Int64, GenericsTy>

// This function should be called in each node which inherits Node directly.
private func CopyNodeField(source: Node, target: Node): Unit {
    target.begin = source.begin
    target.end = source.end
    target.SetTy(source.GetTy().getOrThrow())
    target.curMacroCall = source.curMacroCall
    target.isInMacroCall = source.isInMacroCall
    CopyNodeScopeInfo(target, source)
    target.CopyAttrs(source.GetAttrs())
}

private func hasInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Bool {
    if (let Some(values) <- generic2ins.get(genericDecl.objectId)) {
        for (value in values) {
            if (SameDecl(value, instantiatedDecl)) {
                return true
            }
        }
    }
    return false
}

private func registerInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
    if (hasInstantiation(genericDecl, instantiatedDecl)) {
        return
    }
    let genericKey = genericDecl.objectId
    if (!generic2ins.contains(genericKey)) {
        generic2ins[genericKey] = ArrayList<Decl>()
    }
    if (let Some(values) <- generic2ins.get(genericKey)) {
        values.add(instantiatedDecl)
    }
    ins2generic[instantiatedDecl.objectId] = genericDecl
}

public func SetOptLevel(opts: OptionGlobalOptions): Unit {
    currentOptLevel = opts.optimizationLevel
    currentOutputMode = opts.outputMode
}

private func IsCPointerFrozenMember(decl: Decl): Bool {
    if (decl.fullPackageName != "std.core" || decl.astKind != ASTKind.FUNC_DECL ||
        !decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return false
    }
    if (let Some(outer) <- decl.outerDecl) {
        if (let Some(extendDecl) <- (outer as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    return extendedTy.IsPointer()
                }
            }
        }
    }
    return false
}

public func RequireInstantiation(decl: Decl): Bool {
    if (currentOutputMode == OutputMode.CHIR || decl.IsCommonMatchedWithSpecific()) {
        return false
    }
    if (IsCPointerFrozenMember(decl)) {
        return true
    }
    if (decl.astKind == ASTKind.INTERFACE_DECL) {
        return false
    }
    if (decl.IsNominalDecl()) {
        if (enumIndex(currentOptLevel) >= enumIndex(OptimizationLevel.O2) && !decl.TestAttr(Attribute.IMPORTED)) {
            return true
        }
        if (decl.TestAttr(Attribute.GENERIC)) {
            for (member in decl.GetMemberDecls()) {
                if (RequireInstantiation(member)) {
                    return true
                }
            }
        }
        return false
    }
    if (IsVirtualMember(decl)) {
        return false
    }
    if (decl.IsConst()) {
        return true
    }
    if (decl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL) && decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return true
    }
    if (enumIndex(currentOptLevel) < enumIndex(OptimizationLevel.O2)) {
        return false
    }
    if (!IsInDeclWithAttribute(decl, Attribute.IMPORTED)) {
        return true
    }
    return decl.HasAnno(AstAnnotationKind.FROZEN)
}

public func GetOptLevel(): OptimizationLevel {
    return currentOptLevel
}

public func IsOpenDecl(decl: Decl): Bool {
    if (!decl.IsClassLikeDecl()) {
        return false
    }
    if (decl.TestAttr(Attribute.OPEN_TO_MOCK)) {
        return false
    }
    if (decl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
        return true
    }
    return decl.astKind == ASTKind.INTERFACE_DECL
}

private func generalizeTypeArgs(typeArgs: ArrayList<Ty>, generalizer: TyGeneralizer): Array<Ty> {
    let out = ArrayList<Ty>()
    for (ty in typeArgs) {
        out.add(generalizer.Generalize(ty))
    }
    return out.toArray()
}

private func generalizeSetTys(typeArgs: ArrayList<Ty>, generalizer: TyGeneralizer): Array<Ty> {
    let out = ArrayList<Ty>()
    let tys = TreeMap<Int64, Ty>()
    for (ty in typeArgs) {
        let generalized = generalizer.Generalize(ty)
        if (!tys.contains(generalized.objectId)) {
            tys.add(generalized.objectId, generalized)
        }
    }
    for (key in tys.keys()) {
        if (let Some(ty) <- tys.get(key)) {
            out.add(ty)
        }
    }
    return out.toArray()
}

public func GetReversedTypeSubst(typeMapping: TypeSubst): ReversedTypeSubst {
    let out = ReversedTypeSubst()
    for (entry in typeMapping.entries) {
        if (!out.contains(entry.ty.objectId)) {
            out.add(entry.ty.objectId, entry.tyVar)
        }
    }
    return out
}

public class TyGeneralizer {
    private var tyMgr: TypeManager
    private var typeMapping: ReversedTypeSubst

    public init(tyMgr: TypeManager, mapping: ReversedTypeSubst) {
        this.tyMgr = tyMgr
        typeMapping = mapping
    }

    public func Generalize(ty: Ty): Ty {
        if (typeMapping.size == 0 || !Ty.IsTyCorrect(ty)) {
            return ty
        }
        if (let Some(genericTy) <- typeMapping.get(ty.objectId)) {
            return genericTy
        }
        if (let Some(funcTy) <- (ty as FuncTy)) {
            let paramTys = ArrayList<Ty>()
            for (paramTy in funcTy.paramTys) {
                paramTys.add(Generalize(paramTy))
            }
            let cfg = FuncTyConfig()
            cfg.isC = funcTy.IsCFunc()
            cfg.isClosureTy = funcTy.isClosureTy
            cfg.hasVariableLenArg = funcTy.hasVariableLenArg
            return tyMgr.GetFunctionTy(paramTys.toArray(), Generalize(funcTy.retTy), cfg: cfg)
        }
        if (let Some(tupleTy) <- (ty as TupleTy)) {
            return tyMgr.GetTupleTy(generalizeTypeArgs(tupleTy.typeArgs, this), isClosureTy: tupleTy.isClosureTy)
        }
        if (let Some(arrayTy) <- (ty as ArrayTy)) {
            if (arrayTy.typeArgs.isEmpty()) {
                return arrayTy
            }
            return tyMgr.GetArrayTy(Generalize(arrayTy.typeArgs[0]), arrayTy.dims)
        }
        if (let Some(pointerTy) <- (ty as PointerTy)) {
            if (pointerTy.typeArgs.isEmpty()) {
                return pointerTy
            }
            return tyMgr.GetPointerTy(Generalize(pointerTy.typeArgs[0]))
        }
        if (let Some(structTy) <- (ty as StructTy)) {
            if (let Some(decl) <- structTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetStructTy(decl, generalizeTypeArgs(structTy.typeArgs, this))
                }
            }
            return structTy
        }
        if (let Some(classThisTy) <- (ty as ClassThisTy)) {
            if (let Some(decl) <- classThisTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetClassThisTy(decl, generalizeTypeArgs(classThisTy.typeArgs, this))
                }
            }
            return classThisTy
        }
        if (let Some(classTy) <- (ty as ClassTy)) {
            if (let Some(decl) <- classTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetClassTy(decl, generalizeTypeArgs(classTy.typeArgs, this))
                }
            }
            return classTy
        }
        if (let Some(interfaceTy) <- (ty as InterfaceTy)) {
            if (let Some(decl) <- interfaceTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetInterfaceTy(decl, generalizeTypeArgs(interfaceTy.typeArgs, this))
                }
            }
            return interfaceTy
        }
        if (let Some(refEnumTy) <- (ty as RefEnumTy)) {
            if (let Some(decl) <- refEnumTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    return tyMgr.GetRefEnumTy(decl, generalizeTypeArgs(refEnumTy.typeArgs, this))
                }
            }
            return refEnumTy
        }
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (let Some(decl) <- enumTy.declPtr) {
                if (let Some(_) <- decl.generic) {
                    let generalized = tyMgr.GetEnumTy(decl, typeArgs: generalizeTypeArgs(enumTy.typeArgs, this))
                    generalized.hasCorrespondRefEnumTy = enumTy.hasCorrespondRefEnumTy
                    return generalized
                }
            }
            return enumTy
        }
        if (let Some(aliasTy) <- (ty as TypeAliasTy)) {
            if (let Some(decl) <- aliasTy.declPtr) {
                return tyMgr.GetTypeAliasTy(decl, generalizeTypeArgs(aliasTy.typeArgs, this))
            }
            return aliasTy
        }
        if (let Some(intersectionTy) <- (ty as IntersectionTy)) {
            return tyMgr.GetIntersectionTy(generalizeSetTys(intersectionTy.tys, this))
        }
        if (let Some(unionTy) <- (ty as UnionTy)) {
            return tyMgr.GetUnionTy(generalizeSetTys(unionTy.tys, this))
        }
        return ty
    }
}

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    let _ = source
    let _ = target
}

public func InstantiateMacroInvocation(invocation: MacroInvocation): MacroInvocation {
    let target = MacroInvocation()
    target.macroCallDiagInfo.fullName = invocation.macroCallDiagInfo.fullName
    for (position in invocation.fullNameDotPos) {
        target.fullNameDotPos.add(position)
    }
    target.macroCallDiagInfo.identifier = invocation.macroCallDiagInfo.identifier
    target.macroCallDiagInfo.identifierPos = invocation.macroCallDiagInfo.identifierPos
    target.leftSquarePos = invocation.leftSquarePos
    for (token in invocation.attrs) {
        target.attrs.add(token)
    }
    target.rightSquarePos = invocation.rightSquarePos
    target.leftParenPos = invocation.leftParenPos
    for (token in invocation.args) {
        target.args.add(token)
    }
    target.rightParenPos = invocation.rightParenPos
    for (token in invocation.newTokens) {
        target.newTokens.add(token)
    }
    target.newTokensStr = invocation.newTokensStr
    target.parent = invocation.parent
    target.scopeKind = invocation.scopeKind
    target.exprKind = invocation.exprKind
    return target
}

public func InstantiateGeneric(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    let target = Generic()
    for (typeParameter in generic.typeParameters) {
        if (let Some(cloned) <- (PartialInstantiation.Instantiate(typeParameter, visitor) as GenericParamDecl)) {
            target.typeParameters.add(cloned)
        }
    }
    for (genericConstraint in generic.genericConstraints) {
        if (let Some(cloned) <-
            (PartialInstantiation.Instantiate(genericConstraint, visitor) as GenericConstraint)) {
            target.genericConstraints.add(cloned)
        }
    }
    target.leftAnglePos = generic.leftAnglePos
    target.rightAnglePos = generic.rightAnglePos
    return target
}

public class PartialInstantiation {
    private let targetAddr2targetAddr: ArrayList<(Node, (Node) -> Unit)> =
        ArrayList<(Node, (Node) -> Unit)>()
    private let source2cloned: HashMap<Node, Node> = HashMap<Node, Node>()

    public init() {}

    private func TargetAddrMapInsert(from: Option<Node>, target: (Node) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, target))
        }
    }

    private func TargetAddrMapInsert(from: Option<Decl>, target: (Decl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Decl, target: (Decl) -> Unit): Unit {
        targetAddr2targetAddr.add((from, { cloned: Node => target((cloned as Decl).getOrThrow()) }))
    }

    private func TargetAddrMapInsert(from: Option<FuncDecl>, target: (FuncDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<PropDecl>, target: (PropDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as PropDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<Expr>, target: (Expr) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Expr).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<Pattern>, target: (Pattern) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as Pattern).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<FuncBody>, target: (FuncBody) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as FuncBody).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<ClassLikeDecl>, target: (ClassLikeDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as ClassLikeDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<StructDecl>, target: (StructDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as StructDecl).getOrThrow()) }))
        }
    }

    private func TargetAddrMapInsert(from: Option<EnumDecl>, target: (EnumDecl) -> Unit): Unit {
        if (let Some(value) <- from) {
            targetAddr2targetAddr.add((value, { cloned: Node => target((cloned as EnumDecl).getOrThrow()) }))
        }
    }

    public static func Instantiate(node: Node): Node {
        return Instantiate(node, DefaultVisitFunc)
    }

    public static func Instantiate(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        return PartialInstantiation().InstantiateWithRearrange(node, visitFunc)
    }

    private static func InstantiateGenericParamDecl(source: GenericParamDecl): Decl {
        let target = GenericParamDecl()
        target.outerDecl = source.outerDecl
        target.commaPos = source.commaPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateFuncParam(source: FuncParam, visitor: (Node, Node) -> Unit): VarDecl {
        let target = FuncParam()
        target.colonPos = source.colonPos
        target.assignment = InstantiateExpr(source.assignment, visitor)
        if (let Some(desugarDecl) <- source.desugarDecl) {
            let clonedDecl = InstantiateDecl(desugarDecl, visitor)
            clonedDecl.genericDecl = desugarDecl
            target.desugarDecl = clonedDecl as FuncDecl
        }
        target.isNamedParam = source.isNamedParam
        target.isMemberParam = source.isMemberParam
        target.commaPos = source.commaPos
        target.notMarkPos = source.notMarkPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateVarWithPatternDecl(
        source: VarWithPatternDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = VarWithPatternDecl()
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.assignPos = source.assignPos
        target.colonPos = source.colonPos
        target.isVar = source.isVar
        target.isConst = source.isConst
        target.irrefutablePattern = InstantiatePattern(source.irrefutablePattern, visitor)
        target.initializer = InstantiateExpr(source.initializer, visitor)
        return target
    }

    private static func InstantiateVarDecl(source: VarDecl, visitor: (Node, Node) -> Unit): Decl {
        let target: VarDecl = if (let Some(funcParam) <- (source as FuncParam)) {
            InstantiateFuncParam(funcParam, visitor)
        } else {
            VarDecl()
        }
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.colonPos = source.colonPos
        target.initializer = InstantiateExpr(source.initializer, visitor)
        target.assignPos = source.assignPos
        target.isVar = source.isVar
        target.isConst = source.isConst
        target.isResourceVar = source.isResourceVar
        target.isIdentifierCompilerAdd = source.isIdentifierCompilerAdd
        target.parentPattern = source.parentPattern
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateFuncDecl(source: FuncDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = FuncDecl()
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        let funcBody = source.funcBody.getOrThrow()
        let clonedBody = (InstantiateNode(funcBody, visitor) as FuncBody).getOrThrow()
        target.funcBody = clonedBody
        clonedBody.funcDecl = target
        target.propDecl = source.propDecl
        target.constructorCall = source.constructorCall
        target.op = source.op
        target.ownerFunc = source.ownerFunc
        target.overflowStrategy = source.overflowStrategy
        target.isFastNative = source.isFastNative
        target.isGetter = source.isGetter
        target.isSetter = source.isSetter
        target.isInline = source.isInline
        target.isConst = source.isConst
        target.isFrozen = source.isFrozen
        target.variadicArgIndex = source.variadicArgIndex
        target.hasVariableLenArg = source.hasVariableLenArg
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiatePrimaryCtorDecl(
        source: PrimaryCtorDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = PrimaryCtorDecl()
        let funcBody = source.funcBody.getOrThrow()
        target.funcBody = InstantiateNode(funcBody, visitor) as FuncBody
        target.overflowStrategy = source.overflowStrategy
        target.isFastNative = source.isFastNative
        target.isConst = source.isConst
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiatePropDecl(source: PropDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = PropDecl()
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.colonPos = source.colonPos
        target.leftCurlPos = source.leftCurlPos
        target.rightCurlPos = source.rightCurlPos
        target.isVar = source.isVar
        target.isConst = source.isConst
        for (setter in source.setters) {
            if (let Some(cloned) <- (InstantiateDecl(setter, visitor) as FuncDecl)) {
                cloned.EnableAttr(Attribute.COMPILER_ADD)
                target.setters.add(cloned)
            }
        }
        for (getter in source.getters) {
            if (let Some(cloned) <- (InstantiateDecl(getter, visitor) as FuncDecl)) {
                cloned.EnableAttr(Attribute.COMPILER_ADD)
                target.getters.add(cloned)
            }
        }
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateRefType(source: RefType, visitor: (Node, Node) -> Unit): RefType {
        let target = RefType()
        CopyNodeField(source, target)
        target.ref.identifier = SrcIdentifier(source.ref.identifier.Val(), source.ref.identifier.Begin(),
            source.ref.identifier.End(), source.ref.identifier.IsRaw())
        target.ref.target = source.ref.target
        for (decl in source.ref.targets) {
            target.ref.targets.add(decl)
        }
        target.leftAnglePos = source.leftAnglePos
        for (typeArgument in source.typeArguments) {
            target.typeArguments.add(InstantiateType(typeArgument, visitor))
        }
        target.rightAnglePos = source.rightAnglePos
        target.commaPos = source.commaPos
        target.bitAndPos = source.bitAndPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateExtendDecl(source: ExtendDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = ExtendDecl()
        target.extendedType = InstantiateType(source.extendedType, visitor)
        for (inheritedType in source.inheritedTypes) {
            target.inheritedTypes.add(InstantiateType(inheritedType, visitor))
        }
        for (member in source.members) {
            if (RequireInstantiation(member)) {
                target.members.add(InstantiateDecl(member, visitor))
            }
        }
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        if (let Some(bodyScope) <- source.bodyScope) {
            let clonedBodyScope = DummyBody()
            CopyNodeScopeInfo(clonedBodyScope, bodyScope)
            target.bodyScope = clonedBodyScope
        }
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateMacroExpandDecl(source: MacroExpandDecl): Decl {
        let target = MacroExpandDecl()
        target.invocation = InstantiateMacroInvocation(source.invocation)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateStructDecl(source: StructDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = StructDecl()
        for (inheritedType in source.inheritedTypes) {
            target.inheritedTypes.add(InstantiateType(inheritedType, visitor))
        }
        target.body = InstantiateNode(source.body.getOrThrow(), visitor) as StructBody
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        target.upperBoundPos = source.upperBoundPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateClassDecl(source: ClassDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = ClassDecl()
        for (inheritedType in source.inheritedTypes) {
            target.inheritedTypes.add(InstantiateType(inheritedType, visitor))
        }
        target.body = InstantiateNode(source.body.getOrThrow(), visitor) as ClassBody
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        target.upperBoundPos = source.upperBoundPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateInterfaceDecl(source: InterfaceDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = InterfaceDecl()
        for (inheritedType in source.inheritedTypes) {
            target.inheritedTypes.add(InstantiateType(inheritedType, visitor))
        }
        target.body = InstantiateNode(source.body.getOrThrow(), visitor) as InterfaceBody
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        target.upperBoundPos = source.upperBoundPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateEnumDecl(source: EnumDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = EnumDecl()
        for (inheritedType in source.inheritedTypes) {
            target.inheritedTypes.add(InstantiateType(inheritedType, visitor))
        }
        for (constructor in source.constructors) {
            target.constructors.add(InstantiateDecl(constructor, visitor))
        }
        for (member in source.members) {
            if (!RequireInstantiation(member)) {
                continue
            }
            target.members.add(InstantiateDecl(member, visitor))
        }
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        target.hasArguments = source.hasArguments
        if (let Some(bodyScope) <- source.bodyScope) {
            let clonedBodyScope = DummyBody()
            CopyNodeScopeInfo(clonedBodyScope, bodyScope)
            target.bodyScope = clonedBodyScope
        }
        target.leftCurlPos = source.leftCurlPos
        for (position in source.bitOrPosVector) {
            target.bitOrPosVector.add(position)
        }
        target.rightCurlPos = source.rightCurlPos
        target.upperBoundPos = source.upperBoundPos
        target.hasEllipsis = source.hasEllipsis
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateTypeAliasDecl(source: TypeAliasDecl, visitor: (Node, Node) -> Unit): Decl {
        let target = TypeAliasDecl()
        target.assignPos = source.assignPos
        target.typeNode = InstantiateType(source.typeNode, visitor)
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateQualifiedType(
        source: QualifiedType, visitor: (Node, Node) -> Unit): QualifiedType {
        let target = QualifiedType()
        target.baseType = InstantiateType(source.baseType, visitor)
        target.field = SrcIdentifier(
            source.field.Val(), source.field.Begin(), source.field.End(), source.field.IsRaw())
        target.target = source.target
        for (typeArgument in source.typeArguments) {
            target.typeArguments.add(InstantiateType(typeArgument, visitor))
        }
        return target
    }

    private static func InstantiateParenType(source: ParenType, visitor: (Node, Node) -> Unit): ParenType {
        let target = ParenType()
        target.innerType = InstantiateType(source.innerType, visitor)
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateOptionType(source: OptionType, visitor: (Node, Node) -> Unit): OptionType {
        let target = OptionType()
        target.componentType = InstantiateType(source.componentType, visitor)
        target.questNum = source.questNum
        for (position in source.questVector) {
            target.questVector.add(position)
        }
        if (let Some(desugarType) <- source.desugarType) {
            target.desugarType = PartialInstantiation.Instantiate(desugarType, visitor) as RefType
        }
        return target
    }

    private static func InstantiateFuncType(source: FuncType, visitor: (Node, Node) -> Unit): FuncType {
        let target = FuncType()
        for (paramType in source.paramTypes) {
            target.paramTypes.add(InstantiateType(paramType, visitor))
        }
        target.retType = InstantiateType(source.retType, visitor)
        target.isC = source.isC
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.arrowPos = source.arrowPos
        return target
    }

    private static func InstantiateTupleType(source: TupleType, visitor: (Node, Node) -> Unit): TupleType {
        let target = TupleType()
        for (fieldType in source.fieldTypes) {
            target.fieldTypes.add(InstantiateType(fieldType, visitor))
        }
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        return target
    }

    private static func InstantiateConstantType(
        source: ConstantType, visitor: (Node, Node) -> Unit): ConstantType {
        let target = ConstantType()
        target.constantExpr = InstantiateExpr(source.constantExpr, visitor)
        target.dollarPos = source.dollarPos
        return target
    }

    private static func InstantiateVArrayType(source: VArrayType, visitor: (Node, Node) -> Unit): VArrayType {
        let target = VArrayType()
        target.leftAnglePos = source.leftAnglePos
        target.typeArgument = InstantiateType(source.typeArgument, visitor)
        target.constantType = InstantiateType(source.constantType, visitor)
        target.rightAnglePos = source.rightAnglePos
        return target
    }

    private static func InstantiateType(node: Option<Type>, visitor: (Node, Node) -> Unit): Option<Type> {
        if (let Some(source) <- node) {
            return InstantiateType(source, visitor)
        }
        return None
    }

    private static func InstantiateType(source: Type, visitor: (Node, Node) -> Unit): Type {
        let target: Type = match (source.astKind) {
            case ASTKind.REF_TYPE => InstantiateRefType((source as RefType).getOrThrow(), visitor)
            case ASTKind.PRIMITIVE_TYPE =>
                let primitiveSource = (source as PrimitiveType).getOrThrow()
                let primitiveTarget = PrimitiveType()
                primitiveTarget.str = primitiveSource.str
                primitiveTarget.kind = primitiveSource.kind
                primitiveTarget
            case ASTKind.PAREN_TYPE => InstantiateParenType((source as ParenType).getOrThrow(), visitor)
            case ASTKind.QUALIFIED_TYPE =>
                InstantiateQualifiedType((source as QualifiedType).getOrThrow(), visitor)
            case ASTKind.OPTION_TYPE => InstantiateOptionType((source as OptionType).getOrThrow(), visitor)
            case ASTKind.FUNC_TYPE => InstantiateFuncType((source as FuncType).getOrThrow(), visitor)
            case ASTKind.TUPLE_TYPE => InstantiateTupleType((source as TupleType).getOrThrow(), visitor)
            case ASTKind.CONSTANT_TYPE => InstantiateConstantType((source as ConstantType).getOrThrow(), visitor)
            case ASTKind.VARRAY_TYPE => InstantiateVArrayType((source as VArrayType).getOrThrow(), visitor)
            case ASTKind.THIS_TYPE => ThisType(source.begin)
            case ASTKind.INVALID_TYPE => InvalidType(source.begin)
            case _ => Type()
        }
        CJC_ASSERT(target.astKind == source.astKind)
        target.commaPos = source.commaPos
        target.bitAndPos = source.bitAndPos
        target.typeParameterName = source.typeParameterName
        target.typeParameterNameIsRawId = source.typeParameterNameIsRawId
        target.typePos = source.typePos
        target.colonPos = source.colonPos
        CopyNodeField(source, target)
        visitor(source, target)
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateMacroExpandExpr(
        source: MacroExpandExpr, visitor: (Node, Node) -> Unit): MacroExpandExpr {
        let target = MacroExpandExpr()
        target.identifier = Identifier(source.identifier.Val(), source.identifier.Begin(), source.identifier.End())
        target.invocation = InstantiateMacroInvocation(source.invocation)
        for (annotation in source.annotations) {
            if (let Some(cloned) <- (InstantiateNode(annotation, visitor) as Annotation)) {
                target.annotations.add(cloned)
            }
        }
        for (modifier in source.modifiers) {
            let clonedModifier = Modifier(modifier.modifier, modifier.begin)
            CopyNodeField(modifier, clonedModifier)
            clonedModifier.isExplicit = modifier.isExplicit
            target.modifiers.add(clonedModifier)
        }
        return target
    }

    private static func InstantiateTokenPart(source: TokenPart, visitor: (Node, Node) -> Unit): TokenPart {
        let _ = visitor
        let target = TokenPart()
        for (token in source.tokens) {
            target.tokens.add(token)
        }
        return target
    }

    private static func InstantiateQuoteExpr(source: QuoteExpr, visitor: (Node, Node) -> Unit): QuoteExpr {
        let target = QuoteExpr()
        for (expr in source.exprs) {
            target.exprs.add(InstantiateExpr(expr, visitor))
        }
        target.quotePos = source.quotePos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateIfExpr(source: IfExpr, visitor: (Node, Node) -> Unit): IfExpr {
        let target = IfExpr()
        target.ifPos = source.ifPos
        target.leftParenPos = source.leftParenPos
        target.condExpr = InstantiateExpr(source.condExpr, visitor)
        target.rightParenPos = source.rightParenPos
        if (let Some(thenBody) <- source.thenBody) {
            target.thenBody = InstantiateExpr(thenBody, visitor) as Block
        }
        target.hasElse = source.hasElse
        target.isElseIf = source.isElseIf
        target.elsePos = source.elsePos
        target.elseBody = InstantiateExpr(source.elseBody, visitor)
        return target
    }

    private static func InstantiateTryExpr(source: TryExpr, visitor: (Node, Node) -> Unit): TryExpr {
        let target = TryExpr()
        target.tryPos = source.tryPos
        target.lParen = source.lParen
        for (resource in source.resourceSpec) {
            if (let Some(cloned) <- (InstantiateDecl(resource, visitor) as VarDecl)) {
                target.resourceSpec.add(cloned)
            }
        }
        target.isDesugaredFromSyncBlock = source.isDesugaredFromSyncBlock
        target.isDesugaredFromTryWithResources = source.isDesugaredFromTryWithResources
        target.isIllegalResourceSpec = source.isIllegalResourceSpec
        if (let Some(tryBlock) <- source.tryBlock) {
            target.tryBlock = InstantiateExpr(tryBlock, visitor) as Block
        }
        for (position in source.catchPosVector) {
            target.catchPosVector.add(position)
        }
        CJC_ASSERT(source.catchBlocks.size == source.catchPatterns.size)
        var catchIndex: Int64 = 0
        while (catchIndex < source.catchBlocks.size) {
            target.catchBlocks.add(
                (InstantiateExpr(source.catchBlocks[catchIndex], visitor) as Block).getOrThrow())
            target.catchPatterns.add(InstantiatePattern(source.catchPatterns[catchIndex], visitor))
            catchIndex++
        }
        target.finallyPos = source.finallyPos
        if (let Some(finallyBlock) <- source.finallyBlock) {
            target.finallyBlock = InstantiateExpr(finallyBlock, visitor) as Block
        }
        for (position in source.resourceSpecCommaPos) {
            target.resourceSpecCommaPos.add(position)
        }
        target.rParen = source.rParen
        for (position in source.catchLParenPosVector) {
            target.catchLParenPosVector.add(position)
        }
        for (position in source.catchRParenPosVector) {
            target.catchRParenPosVector.add(position)
        }
        return target
    }

    private static func InstantiateThrowExpr(source: ThrowExpr, visitor: (Node, Node) -> Unit): ThrowExpr {
        let target = ThrowExpr()
        target.throwPos = source.throwPos
        target.expr = InstantiateExpr(source.expr, visitor)
        return target
    }

    private static func InstantiateReturnExpr(source: ReturnExpr, visitor: (Node, Node) -> Unit): ReturnExpr {
        let target = ReturnExpr()
        target.returnPos = source.returnPos
        target.expr = InstantiateExpr(source.expr, visitor)
        target.refFuncBody = source.refFuncBody
        return target
    }

    private static func InstantiateWhileExpr(source: WhileExpr, visitor: (Node, Node) -> Unit): WhileExpr {
        let target = WhileExpr()
        target.whilePos = source.whilePos
        target.leftParenPos = source.leftParenPos
        target.condExpr = InstantiateExpr(source.condExpr, visitor)
        if (let Some(body) <- source.body) {
            target.body = InstantiateExpr(body, visitor) as Block
        }
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateDoWhileExpr(source: DoWhileExpr, visitor: (Node, Node) -> Unit): DoWhileExpr {
        let target = DoWhileExpr()
        target.doPos = source.doPos
        if (let Some(body) <- source.body) {
            target.body = InstantiateExpr(body, visitor) as Block
        }
        target.whilePos = source.whilePos
        target.leftParenPos = source.leftParenPos
        target.condExpr = InstantiateExpr(source.condExpr, visitor)
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateAssignExpr(source: AssignExpr, visitor: (Node, Node) -> Unit): AssignExpr {
        let target = AssignExpr()
        target.leftValue = InstantiateExpr(source.leftValue, visitor)
        target.op = source.op
        target.rightExpr = InstantiateExpr(source.rightExpr, visitor)
        target.isCompound = source.isCompound
        target.assignPos = source.assignPos
        return target
    }

    private static func InstantiateIncOrDecExpr(
        source: IncOrDecExpr, visitor: (Node, Node) -> Unit): IncOrDecExpr {
        let target = IncOrDecExpr()
        target.op = source.op
        target.operatorPos = source.operatorPos
        target.expr = InstantiateExpr(source.expr, visitor)
        return target
    }

    private static func InstantiateUnaryExpr(source: UnaryExpr, visitor: (Node, Node) -> Unit): UnaryExpr {
        let target = UnaryExpr()
        target.op = source.op
        target.expr = InstantiateExpr(source.expr, visitor)
        target.operatorPos = source.operatorPos
        return target
    }

    private static func InstantiateBinaryExpr(source: BinaryExpr, visitor: (Node, Node) -> Unit): BinaryExpr {
        let target = BinaryExpr()
        target.op = source.op
        target.leftExpr = InstantiateExpr(source.leftExpr, visitor)
        target.rightExpr = InstantiateExpr(source.rightExpr, visitor)
        target.operatorPos = source.operatorPos
        return target
    }

    private static func InstantiateRangeExpr(source: RangeExpr, visitor: (Node, Node) -> Unit): RangeExpr {
        let target = RangeExpr()
        target.startExpr = InstantiateExpr(source.startExpr, visitor)
        target.rangePos = source.rangePos
        target.stopExpr = InstantiateExpr(source.stopExpr, visitor)
        target.colonPos = source.colonPos
        target.stepExpr = InstantiateExpr(source.stepExpr, visitor)
        target.isClosed = source.isClosed
        target.decl = source.decl
        return target
    }

    private static func InstantiateSubscriptExpr(
        source: SubscriptExpr, visitor: (Node, Node) -> Unit): SubscriptExpr {
        let target = SubscriptExpr()
        target.baseExpr = InstantiateExpr(source.baseExpr, visitor)
        target.leftParenPos = source.leftParenPos
        for (indexExpr in source.indexExprs) {
            target.indexExprs.add(InstantiateExpr(indexExpr, visitor))
        }
        for (position in source.commaPos) {
            target.commaPos.add(position)
        }
        target.rightParenPos = source.rightParenPos
        target.isTupleAccess = source.isTupleAccess
        return target
    }

    private static func InstantiateMemberAccess(
        source: MemberAccess, visitor: (Node, Node) -> Unit): MemberAccess {
        let target = MemberAccess()
        target.baseExpr = InstantiateExpr(source.baseExpr, visitor)
        target.dotPos = source.dotPos
        target.field = SrcIdentifier(
            source.field.Val(), source.field.Begin(), source.field.End(), source.field.IsRaw())
        target.target = source.target
        for (decl in source.targets) {
            target.targets.add(decl)
        }
        target.isPattern = source.isPattern
        target.isAlone = source.isAlone
        for (ty in source.instTys) {
            target.instTys.add(ty)
        }
        target.matchedParentTy = source.matchedParentTy
        target.callOrPattern = source.callOrPattern
        for ((decl, sourceTys) in source.foundUpperBoundMap) {
            let clonedTys = ArrayList<Ty>()
            for (ty in sourceTys) {
                clonedTys.add(ty)
            }
            target.foundUpperBoundMap.add((decl, clonedTys))
        }
        target.isExposedAccess = source.isExposedAccess
        for (typeArgument in source.typeArguments) {
            target.typeArguments.add(InstantiateType(typeArgument, visitor))
        }
        return target
    }

    private static func InstantiateCallExpr(source: CallExpr, visitor: (Node, Node) -> Unit): CallExpr {
        let target = CallExpr()
        target.baseFunc = InstantiateExpr(source.baseFunc, visitor)
        target.leftParenPos = source.leftParenPos
        target.needCheckToTokens = source.needCheckToTokens
        let cloneTable = HashMap<Node, FuncArg>()
        for (arg in source.args) {
            let cloned = (InstantiateNode(arg, visitor) as FuncArg).getOrThrow()
            target.args.add(cloned)
            cloneTable[arg] = cloned
        }
        if (let Some(sourceDesugarArgs) <- source.desugarArgs) {
            for (arg in source.defaultArgs) {
                let cloned = (InstantiateNode(arg, visitor) as FuncArg).getOrThrow()
                target.defaultArgs.add(cloned)
                cloneTable[arg] = cloned
            }
            let clonedDesugarArgs = ArrayList<FuncArg>()
            for (sourceArg in sourceDesugarArgs) {
                clonedDesugarArgs.add(cloneTable.get(sourceArg).getOrThrow())
            }
            target.desugarArgs = clonedDesugarArgs
        }
        target.rightParenPos = source.rightParenPos
        target.resolvedFunction = source.resolvedFunction
        target.callKind = source.callKind
        target.sugarKind = source.sugarKind
        if (let Some(baseFunc) <- target.baseFunc) {
            if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                memberAccess.callOrPattern = target
            }
        }
        return target
    }

    private static func InstantiateParenExpr(source: ParenExpr, visitor: (Node, Node) -> Unit): ParenExpr {
        let target = ParenExpr()
        target.leftParenPos = source.leftParenPos
        target.expr = InstantiateExpr(source.expr, visitor)
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateLambdaExpr(source: LambdaExpr, visitor: (Node, Node) -> Unit): LambdaExpr {
        let target = LambdaExpr((InstantiateNode(source.funcBody.getOrThrow(), visitor) as FuncBody).getOrThrow())
        if (source.TestAttr(Attribute.MOCK_SUPPORTED)) {
            target.EnableAttr(Attribute.MOCK_SUPPORTED)
        }
        return target
    }

    private static func InstantiateLitConstExpr(
        source: LitConstExpr, visitor: (Node, Node) -> Unit): LitConstExpr {
        let target = LitConstExpr(source.kind, source.stringValue)
        for (codepoint in source.codepoint) {
            target.codepoint.add(codepoint)
        }
        target.delimiterNum = source.delimiterNum
        target.stringKind = source.stringKind
        target.rawString = source.rawString
        if (let Some(refType) <- source.ref) {
            let clonedRef = InstantiateRefType(refType, visitor)
            target.ref = clonedRef
            visitor(refType, clonedRef)
        }
        if (let Some(siExpr) <- source.siExpr) {
            target.siExpr = InstantiateExpr(siExpr, visitor) as StrInterpolationExpr
        }
        return target
    }

    private static func InstantiateInterpolationExpr(
        source: InterpolationExpr, visitor: (Node, Node) -> Unit): InterpolationExpr {
        let target = InterpolationExpr()
        target.rawString = source.rawString
        target.dollarPos = source.dollarPos
        if (let Some(block) <- source.block) {
            target.block = InstantiateExpr(block, visitor) as Block
        }
        return target
    }

    private static func InstantiateStrInterpolationExpr(
        source: StrInterpolationExpr, visitor: (Node, Node) -> Unit): StrInterpolationExpr {
        let target = StrInterpolationExpr()
        target.rawString = source.rawString
        for (part in source.strParts) {
            target.strParts.add(part)
        }
        for (partExpr in source.strPartExprs) {
            target.strPartExprs.add(InstantiateExpr(partExpr, visitor))
        }
        return target
    }

    private static func InstantiateArrayLit(source: ArrayLit, visitor: (Node, Node) -> Unit): ArrayLit {
        let target = ArrayLit()
        target.leftSquarePos = source.leftSquarePos
        for (child in source.children) {
            target.children.add(InstantiateExpr(child, visitor))
        }
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        target.rightSquarePos = source.rightSquarePos
        target.initFunc = source.initFunc
        return target
    }

    private static func InstantiateArrayExpr(source: ArrayExpr, visitor: (Node, Node) -> Unit): ArrayExpr {
        let target = ArrayExpr()
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.leftParenPos = source.leftParenPos
        for (arg in source.args) {
            target.args.add((InstantiateNode(arg, visitor) as FuncArg).getOrThrow())
        }
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        target.rightParenPos = source.rightParenPos
        target.initFunc = source.initFunc
        target.isValueArray = source.isValueArray
        return target
    }

    private static func InstantiatePointerExpr(
        source: PointerExpr, visitor: (Node, Node) -> Unit): PointerExpr {
        let target = PointerExpr()
        target.typeNode = InstantiateType(source.typeNode, visitor)
        if (let Some(arg) <- source.arg) {
            target.arg = InstantiateNode(arg, visitor) as FuncArg
        }
        return target
    }

    private static func InstantiateTupleLit(source: TupleLit, visitor: (Node, Node) -> Unit): TupleLit {
        let target = TupleLit()
        target.leftParenPos = source.leftParenPos
        for (child in source.children) {
            target.children.add(InstantiateExpr(child, visitor))
        }
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateRefExpr(source: RefExpr, visitor: (Node, Node) -> Unit): RefExpr {
        let target = RefExpr(SrcIdentifier(source.ref.identifier.Val(), source.ref.identifier.Begin(),
            source.ref.identifier.End(), source.ref.identifier.IsRaw()))
        target.leftAnglePos = source.leftAnglePos
        target.ref.target = source.ref.target
        for (decl in source.ref.targets) {
            target.ref.targets.add(decl)
        }
        for (typeArgument in source.typeArguments) {
            target.typeArguments.add(InstantiateType(typeArgument, visitor))
        }
        target.rightAnglePos = source.rightAnglePos
        target.isSuper = source.isSuper
        target.isThis = source.isThis
        target.isAlone = source.isAlone
        for (ty in source.instTys) {
            target.instTys.add(ty)
        }
        target.matchedParentTy = source.matchedParentTy
        target.callOrPattern = source.callOrPattern
        return target
    }

    private static func InstantiateForInExpr(source: ForInExpr, visitor: (Node, Node) -> Unit): ForInExpr {
        let target = ForInExpr()
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.pattern = InstantiatePattern(source.pattern, visitor)
        target.inPos = source.inPos
        target.inExpression = InstantiateExpr(source.inExpression, visitor)
        target.wherePos = source.wherePos
        target.patternGuard = InstantiateExpr(source.patternGuard, visitor)
        target.patternInDesugarExpr = source.patternInDesugarExpr
        if (let Some(body) <- source.body) {
            target.body = InstantiateExpr(body, visitor) as Block
        }
        target.forInKind = source.forInKind
        return target
    }

    private static func InstantiateMatchExpr(source: MatchExpr, visitor: (Node, Node) -> Unit): MatchExpr {
        let target = MatchExpr()
        target.matchMode = source.matchMode
        target.sugarKind = source.sugarKind
        target.selector = InstantiateExpr(source.selector, visitor)
        for (matchCase in source.matchCases) {
            if (let Some(cloned) <- (InstantiateNode(matchCase, visitor) as MatchCase)) {
                target.matchCases.add(cloned)
            }
        }
        for (matchCaseOther in source.matchCaseOthers) {
            if (let Some(cloned) <- (InstantiateNode(matchCaseOther, visitor) as MatchCaseOther)) {
                target.matchCaseOthers.add(cloned)
            }
        }
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        target.leftCurlPos = source.leftCurlPos
        target.rightCurlPos = source.rightCurlPos
        return target
    }

    private static func InstantiateJumpExpr(source: JumpExpr): JumpExpr {
        let target = JumpExpr()
        target.isBreak = source.isBreak
        target.refLoop = source.refLoop
        return target
    }

    private static func InstantiateTypeConvExpr(
        source: TypeConvExpr, visitor: (Node, Node) -> Unit): TypeConvExpr {
        let target = TypeConvExpr()
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.expr = InstantiateExpr(source.expr, visitor)
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateSpawnExpr(source: SpawnExpr, visitor: (Node, Node) -> Unit): SpawnExpr {
        let target = SpawnExpr()
        target.task = InstantiateExpr(source.task, visitor)
        target.arg = InstantiateExpr(source.arg, visitor)
        if (let Some(futureObj) <- source.futureObj) {
            target.futureObj = InstantiateDecl(futureObj, visitor) as VarDecl
        }
        target.spawnPos = source.spawnPos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateSynchronizedExpr(
        source: SynchronizedExpr, visitor: (Node, Node) -> Unit): SynchronizedExpr {
        let target = SynchronizedExpr()
        target.mutex = InstantiateExpr(source.mutex, visitor)
        if (let Some(body) <- source.body) {
            target.body = InstantiateExpr(body, visitor) as Block
        }
        target.syncPos = source.syncPos
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        return target
    }

    private static func InstantiateInvalidExpr(source: InvalidExpr): InvalidExpr {
        let target = InvalidExpr(source.begin)
        target.value = source.value
        return target
    }

    private static func InstantiateTrailingClosureExpr(
        source: TrailingClosureExpr, visitor: (Node, Node) -> Unit): TrailingClosureExpr {
        let target = TrailingClosureExpr()
        target.leftLambda = source.leftLambda
        target.rightLambda = source.rightLambda
        if (let Some(expr) <- source.expr) {
            target.expr = InstantiateExpr(expr, visitor)
        }
        if (let Some(lambda) <- source.lambda) {
            target.lambda = InstantiateExpr(lambda, visitor) as LambdaExpr
        }
        return target
    }

    private static func InstantiateIsExpr(source: IsExpr, visitor: (Node, Node) -> Unit): IsExpr {
        let target = IsExpr()
        target.leftExpr = InstantiateExpr(source.leftExpr, visitor)
        target.isType = InstantiateType(source.isType, visitor)
        target.isPos = source.isPos
        return target
    }

    private static func InstantiateAsExpr(source: AsExpr, visitor: (Node, Node) -> Unit): AsExpr {
        let target = AsExpr()
        target.leftExpr = InstantiateExpr(source.leftExpr, visitor)
        target.asType = InstantiateType(source.asType, visitor)
        target.asPos = source.asPos
        return target
    }

    private static func InstantiateOptionalExpr(
        source: OptionalExpr, visitor: (Node, Node) -> Unit): OptionalExpr {
        let target = OptionalExpr()
        target.baseExpr = InstantiateExpr(source.baseExpr, visitor)
        target.questPos = source.questPos
        return target
    }

    private static func InstantiateOptionalChainExpr(
        source: OptionalChainExpr, visitor: (Node, Node) -> Unit): OptionalChainExpr {
        let target = OptionalChainExpr()
        target.expr = InstantiateExpr(source.expr, visitor)
        return target
    }

    private static func InstantiateLetPatternDestructor(
        source: LetPatternDestructor, visitor: (Node, Node) -> Unit): LetPatternDestructor {
        let target = LetPatternDestructor()
        target.backarrowPos = source.backarrowPos
        for (pattern in source.patterns) {
            target.patterns.add(InstantiatePattern(pattern, visitor))
        }
        for (position in source.orPos) {
            target.orPos.add(position)
        }
        target.initializer = InstantiateExpr(source.initializer, visitor)
        return target
    }

    private static func InstantiateExpr(node: Option<Expr>, visitor: (Node, Node) -> Unit): Option<Expr> {
        if (let Some(source) <- node) {
            return InstantiateExpr(source, visitor)
        }
        return None
    }

    private static func InstantiateExpr(source: Expr, visitor: (Node, Node) -> Unit): Expr {
        let clonedExpr: Expr = match (source.astKind) {
            case ASTKind.IF_EXPR => InstantiateIfExpr((source as IfExpr).getOrThrow(), visitor)
            case ASTKind.PRIMITIVE_TYPE_EXPR =>
                PrimitiveTypeExpr((source as PrimitiveTypeExpr).getOrThrow().typeKind)
            case ASTKind.MACRO_EXPAND_EXPR =>
                InstantiateMacroExpandExpr((source as MacroExpandExpr).getOrThrow(), visitor)
            case ASTKind.TOKEN_PART => InstantiateTokenPart((source as TokenPart).getOrThrow(), visitor)
            case ASTKind.QUOTE_EXPR => InstantiateQuoteExpr((source as QuoteExpr).getOrThrow(), visitor)
            case ASTKind.TRY_EXPR => InstantiateTryExpr((source as TryExpr).getOrThrow(), visitor)
            case ASTKind.THROW_EXPR => InstantiateThrowExpr((source as ThrowExpr).getOrThrow(), visitor)
            case ASTKind.RETURN_EXPR => InstantiateReturnExpr((source as ReturnExpr).getOrThrow(), visitor)
            case ASTKind.WHILE_EXPR => InstantiateWhileExpr((source as WhileExpr).getOrThrow(), visitor)
            case ASTKind.DO_WHILE_EXPR => InstantiateDoWhileExpr((source as DoWhileExpr).getOrThrow(), visitor)
            case ASTKind.ASSIGN_EXPR => InstantiateAssignExpr((source as AssignExpr).getOrThrow(), visitor)
            case ASTKind.INC_OR_DEC_EXPR =>
                InstantiateIncOrDecExpr((source as IncOrDecExpr).getOrThrow(), visitor)
            case ASTKind.UNARY_EXPR => InstantiateUnaryExpr((source as UnaryExpr).getOrThrow(), visitor)
            case ASTKind.BINARY_EXPR => InstantiateBinaryExpr((source as BinaryExpr).getOrThrow(), visitor)
            case ASTKind.RANGE_EXPR => InstantiateRangeExpr((source as RangeExpr).getOrThrow(), visitor)
            case ASTKind.SUBSCRIPT_EXPR =>
                InstantiateSubscriptExpr((source as SubscriptExpr).getOrThrow(), visitor)
            case ASTKind.MEMBER_ACCESS =>
                InstantiateMemberAccess((source as MemberAccess).getOrThrow(), visitor)
            case ASTKind.CALL_EXPR => InstantiateCallExpr((source as CallExpr).getOrThrow(), visitor)
            case ASTKind.PAREN_EXPR => InstantiateParenExpr((source as ParenExpr).getOrThrow(), visitor)
            case ASTKind.LAMBDA_EXPR => InstantiateLambdaExpr((source as LambdaExpr).getOrThrow(), visitor)
            case ASTKind.LIT_CONST_EXPR =>
                InstantiateLitConstExpr((source as LitConstExpr).getOrThrow(), visitor)
            case ASTKind.ARRAY_LIT => InstantiateArrayLit((source as ArrayLit).getOrThrow(), visitor)
            case ASTKind.ARRAY_EXPR => InstantiateArrayExpr((source as ArrayExpr).getOrThrow(), visitor)
            case ASTKind.POINTER_EXPR => InstantiatePointerExpr((source as PointerExpr).getOrThrow(), visitor)
            case ASTKind.TUPLE_LIT => InstantiateTupleLit((source as TupleLit).getOrThrow(), visitor)
            case ASTKind.REF_EXPR => InstantiateRefExpr((source as RefExpr).getOrThrow(), visitor)
            case ASTKind.FOR_IN_EXPR => InstantiateForInExpr((source as ForInExpr).getOrThrow(), visitor)
            case ASTKind.MATCH_EXPR => InstantiateMatchExpr((source as MatchExpr).getOrThrow(), visitor)
            case ASTKind.JUMP_EXPR => InstantiateJumpExpr((source as JumpExpr).getOrThrow())
            case ASTKind.TYPE_CONV_EXPR =>
                InstantiateTypeConvExpr((source as TypeConvExpr).getOrThrow(), visitor)
            case ASTKind.SPAWN_EXPR => InstantiateSpawnExpr((source as SpawnExpr).getOrThrow(), visitor)
            case ASTKind.SYNCHRONIZED_EXPR =>
                InstantiateSynchronizedExpr((source as SynchronizedExpr).getOrThrow(), visitor)
            case ASTKind.INVALID_EXPR => InstantiateInvalidExpr((source as InvalidExpr).getOrThrow())
            case ASTKind.BLOCK => InstantiateBlock((source as Block).getOrThrow(), visitor)
            case ASTKind.INTERPOLATION_EXPR =>
                InstantiateInterpolationExpr((source as InterpolationExpr).getOrThrow(), visitor)
            case ASTKind.STR_INTERPOLATION_EXPR =>
                InstantiateStrInterpolationExpr((source as StrInterpolationExpr).getOrThrow(), visitor)
            case ASTKind.TRAIL_CLOSURE_EXPR =>
                InstantiateTrailingClosureExpr((source as TrailingClosureExpr).getOrThrow(), visitor)
            case ASTKind.IS_EXPR => InstantiateIsExpr((source as IsExpr).getOrThrow(), visitor)
            case ASTKind.AS_EXPR => InstantiateAsExpr((source as AsExpr).getOrThrow(), visitor)
            case ASTKind.OPTIONAL_EXPR => InstantiateOptionalExpr((source as OptionalExpr).getOrThrow(), visitor)
            case ASTKind.OPTIONAL_CHAIN_EXPR =>
                InstantiateOptionalChainExpr((source as OptionalChainExpr).getOrThrow(), visitor)
            case ASTKind.WILDCARD_EXPR => WildcardExpr()
            case ASTKind.LET_PATTERN_DESTRUCTOR =>
                InstantiateLetPatternDestructor((source as LetPatternDestructor).getOrThrow(), visitor)
            case _ => InvalidExpr(source.begin)
        }
        if (clonedExpr.astKind != ASTKind.INVALID_EXPR) {
            CopyNodeField(source, clonedExpr)
            clonedExpr.isConst = source.isConst
            clonedExpr.isBaseFunc = source.isBaseFunc
            clonedExpr.isInFlowExpr = source.isInFlowExpr
            clonedExpr.constNumValue.asInt.Assign(source.constNumValue.asInt)
            clonedExpr.constNumValue.asFloat.value = source.constNumValue.asFloat.value
            clonedExpr.constNumValue.asFloat.flowStatus = source.constNumValue.asFloat.flowStatus
            clonedExpr.constNumValue.asBoolean = source.constNumValue.asBoolean
            clonedExpr.hasSemi = source.hasSemi
            clonedExpr.mapExpr = if (let Some(mapExpr) <- source.mapExpr) {
                if (mapExpr == source) { clonedExpr } else { mapExpr }
            } else {
                None
            }
            clonedExpr.sourceExpr = source.sourceExpr
            clonedExpr.overflowStrategy = source.overflowStrategy
            if (source.desugarExpr.isSome() && clonedExpr.desugarExpr.isNone()) {
                clonedExpr.desugarExpr = InstantiateExpr(source.desugarExpr, visitor)
            }
            clonedExpr.EnableAttr(Attribute.COMPILER_ADD)
            visitor(source, clonedExpr)
        }
        return clonedExpr
    }

    private static func InstantiateDecl(source: Decl, visitor: (Node, Node) -> Unit): Decl {
        let target: Decl = match (source.astKind) {
            case ASTKind.GENERIC_PARAM_DECL =>
                InstantiateGenericParamDecl((source as GenericParamDecl).getOrThrow())
            case ASTKind.PROP_DECL => InstantiatePropDecl((source as PropDecl).getOrThrow(), visitor)
            case ASTKind.VAR_DECL => InstantiateVarDecl((source as VarDecl).getOrThrow(), visitor)
            case ASTKind.FUNC_PARAM => InstantiateVarDecl((source as VarDecl).getOrThrow(), visitor)
            case ASTKind.FUNC_DECL => InstantiateFuncDecl((source as FuncDecl).getOrThrow(), visitor)
            case ASTKind.STRUCT_DECL => InstantiateStructDecl((source as StructDecl).getOrThrow(), visitor)
            case ASTKind.CLASS_DECL => InstantiateClassDecl((source as ClassDecl).getOrThrow(), visitor)
            case ASTKind.INTERFACE_DECL =>
                InstantiateInterfaceDecl((source as InterfaceDecl).getOrThrow(), visitor)
            case ASTKind.ENUM_DECL => InstantiateEnumDecl((source as EnumDecl).getOrThrow(), visitor)
            case ASTKind.PRIMARY_CTOR_DECL =>
                InstantiatePrimaryCtorDecl((source as PrimaryCtorDecl).getOrThrow(), visitor)
            case ASTKind.EXTEND_DECL => InstantiateExtendDecl((source as ExtendDecl).getOrThrow(), visitor)
            case ASTKind.MACRO_EXPAND_DECL =>
                InstantiateMacroExpandDecl((source as MacroExpandDecl).getOrThrow())
            case ASTKind.VAR_WITH_PATTERN_DECL =>
                InstantiateVarWithPatternDecl((source as VarWithPatternDecl).getOrThrow(), visitor)
            case ASTKind.TYPE_ALIAS_DECL =>
                InstantiateTypeAliasDecl((source as TypeAliasDecl).getOrThrow(), visitor)
            case ASTKind.MACRO_DECL => InvalidDecl(source.begin)
            case ASTKind.MAIN_DECL => InvalidDecl(source.begin)
            case ASTKind.INVALID_DECL => InvalidDecl(source.begin)
            case _ => InvalidDecl(source.begin)
        }
        CopyNodeField(source, target)
        for (modifier in source.modifiers) {
            let clonedModifier = Modifier(modifier.modifier, modifier.begin)
            CopyNodeField(modifier, clonedModifier)
            clonedModifier.isExplicit = modifier.isExplicit
            target.modifiers.add(clonedModifier)
        }
        target.identifier = SrcIdentifier(
            source.identifier.Val(), source.identifier.Begin(), source.identifier.End(), source.identifier.IsRaw())
        target.identifierForLsp = source.identifierForLsp
        target.keywordPos = source.keywordPos
        target.moduleName = source.moduleName
        target.fullPackageName = source.fullPackageName
        target.outerDecl = source.outerDecl
        target.checkFlag = source.checkFlag
        target.captureIndex = source.captureIndex
        target.linkage = source.linkage
        for (annotation in source.annotations) {
            if (let Some(cloned) <- (InstantiateNode(annotation, visitor) as Annotation)) {
                target.annotations.add(cloned)
            }
        }
        if (let Some(annotationsArray) <- source.annotationsArray) {
            target.annotationsArray = InstantiateNode(annotationsArray, visitor) as ArrayLit
        }
        visitor(source, target)
        return target
    }

    private static func InstantiateConstPattern(
        source: ConstPattern, visitor: (Node, Node) -> Unit): ConstPattern {
        let target = ConstPattern()
        target.literal = InstantiateExpr(source.literal, visitor)
        if (let Some(operatorCallExpr) <- source.operatorCallExpr) {
            target.operatorCallExpr = InstantiateExpr(operatorCallExpr, visitor) as CallExpr
        }
        return target
    }

    private static func InstantiateVarPattern(source: VarPattern, visitor: (Node, Node) -> Unit): VarPattern {
        let target = if (let Some(varDecl) <- source.varDecl) {
            let clonedPattern = VarPattern(varDecl.identifier, nodePos: source.begin)
            clonedPattern.varDecl = InstantiateDecl(varDecl, visitor) as VarDecl
            clonedPattern
        } else {
            VarPattern()
        }
        target.desugarExpr = InstantiateExpr(source.desugarExpr, visitor)
        return target
    }

    private static func InstantiateTuplePattern(
        source: TuplePattern, visitor: (Node, Node) -> Unit): TuplePattern {
        let target = TuplePattern()
        for (pattern in source.patterns) {
            target.patterns.add(InstantiatePattern(pattern, visitor))
        }
        target.leftBracePos = source.leftBracePos
        target.rightBracePos = source.rightBracePos
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        return target
    }

    private static func InstantiateTypePattern(
        source: TypePattern, visitor: (Node, Node) -> Unit): TypePattern {
        let target = TypePattern()
        target.pattern = InstantiatePattern(source.pattern, visitor)
        target.typeNode = InstantiateType(source.typeNode, visitor)
        target.colonPos = source.colonPos
        if (let Some(desugarExpr) <- source.desugarExpr) {
            target.desugarExpr = InstantiateExpr(desugarExpr, visitor)
        }
        if (let Some(desugarVarPattern) <- source.desugarVarPattern) {
            target.desugarVarPattern = PartialInstantiation.Instantiate(desugarVarPattern, visitor) as VarPattern
        }
        target.needRuntimeTypeCheck = source.needRuntimeTypeCheck
        target.matchBeforeRuntime = source.matchBeforeRuntime
        return target
    }

    private static func InstantiateEnumPattern(
        source: EnumPattern, visitor: (Node, Node) -> Unit): EnumPattern {
        let target = EnumPattern()
        target.constructor = InstantiateExpr(source.constructor, visitor)
        for (pattern in source.patterns) {
            target.patterns.add(InstantiatePattern(pattern, visitor))
        }
        target.leftParenPos = source.leftParenPos
        target.rightParenPos = source.rightParenPos
        for (position in source.commaPosVector) {
            target.commaPosVector.add(position)
        }
        return target
    }

    private static func InstantiateExceptTypePattern(
        source: ExceptTypePattern, visitor: (Node, Node) -> Unit): ExceptTypePattern {
        let target = ExceptTypePattern()
        target.pattern = InstantiatePattern(source.pattern, visitor)
        for (typeNode in source.types) {
            target.types.add(InstantiateType(typeNode, visitor))
        }
        target.patternPos = source.patternPos
        target.colonPos = source.colonPos
        for (position in source.bitOrPosVector) {
            target.bitOrPosVector.add(position)
        }
        return target
    }

    private static func InstantiateVarOrEnumPattern(
        source: VarOrEnumPattern, visitor: (Node, Node) -> Unit): VarOrEnumPattern {
        let target = VarOrEnumPattern(SrcIdentifier(source.identifier.Val(), source.identifier.Begin(),
            source.identifier.End(), source.identifier.IsRaw()))
        if (let Some(pattern) <- source.pattern) {
            target.pattern = InstantiatePattern(pattern, visitor)
        }
        return target
    }

    private static func InstantiatePattern(
        node: Option<Pattern>, visitor: (Node, Node) -> Unit): Option<Pattern> {
        if (let Some(source) <- node) {
            return InstantiatePattern(source, visitor)
        }
        return None
    }

    private static func InstantiatePattern(source: Pattern, visitor: (Node, Node) -> Unit): Pattern {
        let target: Pattern = match (source.astKind) {
            case ASTKind.CONST_PATTERN =>
                InstantiateConstPattern((source as ConstPattern).getOrThrow(), visitor)
            case ASTKind.WILDCARD_PATTERN => WildcardPattern()
            case ASTKind.VAR_PATTERN => InstantiateVarPattern((source as VarPattern).getOrThrow(), visitor)
            case ASTKind.TUPLE_PATTERN =>
                InstantiateTuplePattern((source as TuplePattern).getOrThrow(), visitor)
            case ASTKind.TYPE_PATTERN => InstantiateTypePattern((source as TypePattern).getOrThrow(), visitor)
            case ASTKind.ENUM_PATTERN => InstantiateEnumPattern((source as EnumPattern).getOrThrow(), visitor)
            case ASTKind.EXCEPT_TYPE_PATTERN =>
                InstantiateExceptTypePattern((source as ExceptTypePattern).getOrThrow(), visitor)
            case ASTKind.VAR_OR_ENUM_PATTERN =>
                InstantiateVarOrEnumPattern((source as VarOrEnumPattern).getOrThrow(), visitor)
            case ASTKind.INVALID_PATTERN => InvalidPattern(source.begin)
            case _ => InvalidPattern()
        }
        CJC_ASSERT(target.astKind == source.astKind)
        CopyNodeField(source, target)
        target.ctxExpr = source.ctxExpr
        target.EnableAttr(Attribute.COMPILER_ADD)
        visitor(source, target)
        return target
    }

    private static func InstantiateBlock(source: Block, visitor: (Node, Node) -> Unit): Block {
        let target = Block()
        CopyNodeField(source, target)
        target.unsafePos = source.unsafePos
        target.leftCurlPos = source.leftCurlPos
        for (node in source.body) {
            target.body.add(InstantiateNode(node, visitor))
        }
        target.rightCurlPos = source.rightCurlPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateClassBody(source: ClassBody, visitor: (Node, Node) -> Unit): ClassBody {
        let target = ClassBody()
        CopyNodeField(source, target)
        target.leftCurlPos = source.leftCurlPos
        for (decl in source.decls) {
            if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
                (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
                IsStaticInitializer(decl)) {
                continue
            }
            target.decls.add(InstantiateDecl(decl, visitor))
        }
        target.rightCurlPos = source.rightCurlPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateStructBody(
        source: StructBody, visitor: (Node, Node) -> Unit): StructBody {
        let target = StructBody()
        CopyNodeField(source, target)
        target.leftCurlPos = source.leftCurlPos
        for (decl in source.decls) {
            if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
                (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
                IsStaticInitializer(decl)) {
                continue
            }
            target.decls.add(InstantiateDecl(decl, visitor))
        }
        target.rightCurlPos = source.rightCurlPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateInterfaceBody(
        source: InterfaceBody, visitor: (Node, Node) -> Unit): InterfaceBody {
        let target = InterfaceBody()
        CopyNodeField(source, target)
        target.leftCurlPos = source.leftCurlPos
        for (decl in source.decls) {
            if (decl.astKind == ASTKind.PROP_DECL ||
                (decl.astKind == ASTKind.FUNC_DECL && !RequireInstantiation(decl))) {
                continue
            }
            target.decls.add(InstantiateDecl(decl, visitor))
        }
        target.rightCurlPos = source.rightCurlPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateGenericConstraint(
        source: GenericConstraint, visitor: (Node, Node) -> Unit): GenericConstraint {
        let target = GenericConstraint()
        CopyNodeField(source, target)
        if (let Some(refType) <- source.refType) {
            target.refType = InstantiateType(refType, visitor) as RefType
        }
        for (upperBound in source.upperBounds) {
            target.upperBounds.add(InstantiateType(upperBound, visitor))
        }
        target.wherePos = source.wherePos
        target.operatorPos = source.operatorPos
        for (position in source.bitAndPos) {
            target.bitAndPos.add(position)
        }
        target.commaPos = source.commaPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateFuncBody(source: FuncBody, visitor: (Node, Node) -> Unit): FuncBody {
        let target = FuncBody()
        CopyNodeField(source, target)
        for (paramList in source.paramLists) {
            if (let Some(cloned) <- (InstantiateNode(paramList, visitor) as FuncParamList)) {
                target.paramLists.add(cloned)
            }
        }
        target.doubleArrowPos = source.doubleArrowPos
        target.colonPos = source.colonPos
        target.retType = InstantiateType(source.retType, visitor)
        if (let Some(body) <- source.body) {
            target.body = InstantiateExpr(body, visitor) as Block
        }
        if (let Some(generic) <- source.generic) {
            target.generic = InstantiateGeneric(generic, visitor)
        }
        for (capturedVar in source.capturedVars) {
            target.capturedVars.add(capturedVar)
        }
        target.captureKind = source.captureKind
        target.outerFunc = source.outerFunc
        target.parentClassLike = source.parentClassLike
        target.parentStruct = source.parentStruct
        target.parentEnum = source.parentEnum
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateFuncParamList(
        source: FuncParamList, visitor: (Node, Node) -> Unit): FuncParamList {
        let target = FuncParamList()
        CopyNodeField(source, target)
        target.leftParenPos = source.leftParenPos
        for (param in source.params) {
            if (let Some(cloned) <- (InstantiateDecl(param, visitor) as FuncParam)) {
                target.params.add(cloned)
            }
        }
        target.variadicArgIndex = source.variadicArgIndex
        target.hasVariableLenArg = source.hasVariableLenArg
        target.rightParenPos = source.rightParenPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateFuncArg(source: FuncArg, visitor: (Node, Node) -> Unit): FuncArg {
        let target = FuncArg()
        CopyNodeField(source, target)
        target.name = SrcIdentifier(source.name.Val(), source.name.Begin(), source.name.End(), source.name.IsRaw())
        target.withInout = source.withInout
        target.colonPos = source.colonPos
        target.expr = InstantiateExpr(source.expr, visitor)
        target.commaPos = source.commaPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateAnnotation(
        source: Annotation, visitor: (Node, Node) -> Unit): Annotation {
        let target = Annotation(source.identifier.Val(), source.kind, source.begin)
        CopyNodeField(source, target)
        target.kind = source.kind
        target.definedPackage = source.definedPackage
        target.isCompileTimeVisible = source.isCompileTimeVisible
        target.identifier = Identifier(source.identifier.Val(), source.identifier.Begin(), source.identifier.End())
        for (token in source.attrs) {
            target.attrs.add(token)
        }
        for (position in source.attrCommas) {
            target.attrCommas.add(position)
        }
        target.rsquarePos = source.rsquarePos
        target.lsquarePos = source.lsquarePos
        for (arg in source.args) {
            if (let Some(cloned) <- (InstantiateNode(arg, visitor) as FuncArg)) {
                target.args.add(cloned)
            }
        }
        target.condExpr = InstantiateExpr(source.condExpr, DefaultVisitFunc)
        target.baseExpr = InstantiateExpr(source.baseExpr, DefaultVisitFunc)
        return target
    }

    private static func cloneContent(source: ImportContent, target: ImportContent): Unit {
        CopyNodeField(source, target)
        target.kind = source.kind
        for (path in source.prefixPaths) {
            target.prefixPaths.add(path)
        }
        for (position in source.prefixPoses) {
            target.prefixPoses.add(position)
        }
        for (position in source.prefixDotPoses) {
            target.prefixDotPoses.add(position)
        }
        target.identifier = Identifier(source.identifier.Val(), source.identifier.Begin(), source.identifier.End())
        target.asPos = source.asPos
        target.aliasName = Identifier(source.aliasName.Val(), source.aliasName.Begin(), source.aliasName.End())
        target.leftCurlPos = source.leftCurlPos
        for (item in source.items) {
            let clonedItem = ImportContent()
            cloneContent(item, clonedItem)
            target.items.add(clonedItem)
        }
        for (position in source.commaPoses) {
            target.commaPoses.add(position)
        }
        target.rightCurlPos = source.rightCurlPos
    }

    private static func InstantiateImportSpec(
        source: ImportSpec, visitor: (Node, Node) -> Unit): ImportSpec {
        let target = ImportSpec()
        CopyNodeField(source, target)
        if (let Some(modifier) <- source.modifier) {
            let clonedModifier = Modifier(modifier.modifier, modifier.begin)
            CopyNodeField(modifier, clonedModifier)
            clonedModifier.isExplicit = modifier.isExplicit
            target.modifier = clonedModifier
        }
        cloneContent(source.content, target.content)
        for (annotation in source.annotations) {
            if (let Some(cloned) <- (InstantiateNode(annotation, visitor) as Annotation)) {
                target.annotations.add(cloned)
            }
        }
        return target
    }

    private static func InstantiateMatchCase(source: MatchCase, visitor: (Node, Node) -> Unit): MatchCase {
        let target = MatchCase()
        CopyNodeField(source, target)
        for (pattern in source.patterns) {
            target.patterns.add(InstantiatePattern(pattern, visitor))
        }
        target.patternGuard = InstantiateExpr(source.patternGuard, visitor)
        if (let Some(exprOrDecls) <- source.exprOrDecls) {
            target.exprOrDecls = InstantiateExpr(exprOrDecls, visitor) as Block
        }
        target.wherePos = source.wherePos
        target.arrowPos = source.arrowPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        for (position in source.bitOrPosVector) {
            target.bitOrPosVector.add(position)
        }
        return target
    }

    private static func InstantiateMatchCaseOther(
        source: MatchCaseOther, visitor: (Node, Node) -> Unit): MatchCaseOther {
        let target = MatchCaseOther()
        CopyNodeField(source, target)
        target.matchExpr = InstantiateExpr(source.matchExpr, visitor)
        if (let Some(exprOrDecls) <- source.exprOrDecls) {
            target.exprOrDecls = InstantiateExpr(exprOrDecls, visitor) as Block
        }
        target.arrowPos = source.arrowPos
        target.EnableAttr(Attribute.COMPILER_ADD)
        return target
    }

    private static func InstantiateNode(node: Node, visitor: (Node, Node) -> Unit): Node {
        let target: Option<Node> = if (let Some(typeNode) <- (node as Type)) {
            InstantiateType(typeNode, visitor)
        } else if (let Some(expr) <- (node as Expr)) {
            InstantiateExpr(expr, visitor)
        } else if (let Some(decl) <- (node as Decl)) {
            InstantiateDecl(decl, visitor)
        } else if (let Some(pattern) <- (node as Pattern)) {
            InstantiatePattern(pattern, visitor)
        } else if (let Some(classBody) <- (node as ClassBody)) {
            InstantiateClassBody(classBody, visitor)
        } else if (let Some(structBody) <- (node as StructBody)) {
            InstantiateStructBody(structBody, visitor)
        } else if (let Some(interfaceBody) <- (node as InterfaceBody)) {
            InstantiateInterfaceBody(interfaceBody, visitor)
        } else if (let Some(genericConstraint) <- (node as GenericConstraint)) {
            InstantiateGenericConstraint(genericConstraint, visitor)
        } else if (let Some(funcBody) <- (node as FuncBody)) {
            InstantiateFuncBody(funcBody, visitor)
        } else if (let Some(funcParamList) <- (node as FuncParamList)) {
            InstantiateFuncParamList(funcParamList, visitor)
        } else if (let Some(funcArg) <- (node as FuncArg)) {
            InstantiateFuncArg(funcArg, visitor)
        } else if (let Some(matchCase) <- (node as MatchCase)) {
            InstantiateMatchCase(matchCase, visitor)
        } else if (let Some(matchCaseOther) <- (node as MatchCaseOther)) {
            InstantiateMatchCaseOther(matchCaseOther, visitor)
        } else if (let Some(annotation) <- (node as Annotation)) {
            InstantiateAnnotation(annotation, visitor)
        } else if (let Some(_) <- (node as DummyBody)) {
            None
        } else if (let Some(importSpec) <- (node as ImportSpec)) {
            InstantiateImportSpec(importSpec, visitor)
        } else {
            InvalidExpr()
        }
        CJC_ASSERT(target.isSome())
        let clonedNode = target.getOrThrow()
        visitor(node, clonedNode)
        clonedNode.EnableAttr(Attribute.COMPILER_ADD)
        return clonedNode
    }

    private func InstantiateWithRearrange(node: Node, visitor: (Node, Node) -> Unit): Node {
        let collectMap = { from: Node, target: Node =>
            if (let Some(sourceDecl) <- (from as Decl)) {
                if (let Some(targetDecl) <- (target as Decl)) {
                    source2cloned[sourceDecl] = targetDecl
                    registerInstantiation(sourceDecl, targetDecl)
                    TargetAddrMapInsert(sourceDecl.outerDecl,
                        { value: Decl => targetDecl.outerDecl = value })
                    TargetAddrMapInsert(sourceDecl.genericDecl,
                        { value: Decl => targetDecl.genericDecl = value })
                }
            }
            if (let Some(sourceExpr) <- (from as Expr)) {
                if (let Some(targetExpr) <- (target as Expr)) {
                    source2cloned[sourceExpr] = targetExpr
                    TargetAddrMapInsert(sourceExpr.sourceExpr,
                        { value: Expr => targetExpr.sourceExpr = value })
                    TargetAddrMapInsert(sourceExpr.mapExpr,
                        { value: Expr => targetExpr.mapExpr = value })
                }
            }
            if (let Some(sourceFuncBody) <- (from as FuncBody)) {
                if (let Some(targetFuncBody) <- (target as FuncBody)) {
                    source2cloned[sourceFuncBody] = targetFuncBody
                    TargetAddrMapInsert(sourceFuncBody.funcDecl,
                        { value: FuncDecl => targetFuncBody.funcDecl = value })
                    TargetAddrMapInsert(sourceFuncBody.outerFunc,
                        { value: FuncBody => targetFuncBody.outerFunc = value })
                    TargetAddrMapInsert(sourceFuncBody.parentClassLike,
                        { value: ClassLikeDecl => targetFuncBody.parentClassLike = value })
                    TargetAddrMapInsert(sourceFuncBody.parentStruct,
                        { value: StructDecl => targetFuncBody.parentStruct = value })
                    TargetAddrMapInsert(sourceFuncBody.parentEnum,
                        { value: EnumDecl => targetFuncBody.parentEnum = value })
                }
            }
            if (let Some(sourcePattern) <- (from as Pattern)) {
                if (let Some(targetPattern) <- (target as Pattern)) {
                    source2cloned[sourcePattern] = targetPattern
                    TargetAddrMapInsert(sourcePattern.ctxExpr,
                        { value: Expr => targetPattern.ctxExpr = value })
                }
            }

            match (from.astKind) {
                case ASTKind.REF_EXPR =>
                    let sourceRefExpr = (from as RefExpr).getOrThrow()
                    let targetRefExpr = (target as RefExpr).getOrThrow()
                    var isCallStaticMemberByVirtual = false
                    if (let Some(refTarget) <- sourceRefExpr.ref.target) {
                        if (refTarget.IsFunc() && refTarget.TestAttr(Attribute.STATIC)) {
                            if (let Some(outerDecl) <- refTarget.outerDecl) {
                                isCallStaticMemberByVirtual = IsOpenDecl(outerDecl)
                            }
                        }
                    }
                    if (!isCallStaticMemberByVirtual) {
                        TargetAddrMapInsert(sourceRefExpr.ref.target,
                            { value: Decl => targetRefExpr.ref.target = value })
                    }
                    TargetAddrMapInsert(sourceRefExpr.callOrPattern,
                        { value: Node => targetRefExpr.callOrPattern = value })
                case ASTKind.ARRAY_EXPR =>
                    let sourceArrayExpr = (from as ArrayExpr).getOrThrow()
                    let targetArrayExpr = (target as ArrayExpr).getOrThrow()
                    TargetAddrMapInsert(sourceArrayExpr.initFunc,
                        { value: FuncDecl => targetArrayExpr.initFunc = value })
                case ASTKind.ARRAY_LIT =>
                    let sourceArrayLit = (from as ArrayLit).getOrThrow()
                    let targetArrayLit = (target as ArrayLit).getOrThrow()
                    TargetAddrMapInsert(sourceArrayLit.initFunc,
                        { value: FuncDecl => targetArrayLit.initFunc = value })
                case ASTKind.MEMBER_ACCESS =>
                    let sourceMemberAccess = (from as MemberAccess).getOrThrow()
                    var rearrangeMemberAccess = false
                    if (let Some(baseExpr) <- sourceMemberAccess.baseExpr) {
                        if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                            rearrangeMemberAccess = refExpr.isThis
                        }
                    }
                    if (rearrangeMemberAccess) {
                        let targetMemberAccess = (target as MemberAccess).getOrThrow()
                        TargetAddrMapInsert(sourceMemberAccess.target,
                            { value: Decl => targetMemberAccess.target = value })
                        TargetAddrMapInsert(sourceMemberAccess.callOrPattern,
                            { value: Node => targetMemberAccess.callOrPattern = value })
                        CJC_ASSERT(sourceMemberAccess.targets.size == targetMemberAccess.targets.size)
                        var targetIndex: Int64 = 0
                        while (targetIndex < sourceMemberAccess.targets.size) {
                            let capturedIndex = targetIndex
                            TargetAddrMapInsert(sourceMemberAccess.targets[capturedIndex],
                                { value: Decl => targetMemberAccess.targets[capturedIndex] = Some(value) })
                            targetIndex++
                        }
                    }
                case ASTKind.FOR_IN_EXPR =>
                    let sourceForInExpr = (from as ForInExpr).getOrThrow()
                    let targetForInExpr = (target as ForInExpr).getOrThrow()
                    TargetAddrMapInsert(sourceForInExpr.patternInDesugarExpr,
                        { value: Pattern => targetForInExpr.patternInDesugarExpr = value })
                case ASTKind.CALL_EXPR =>
                    let sourceCallExpr = (from as CallExpr).getOrThrow()
                    var rearrangeResolvedFunction = true
                    if (let Some(baseFunc) <- sourceCallExpr.baseFunc) {
                        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                            rearrangeResolvedFunction = false
                            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                                if (let Some(refExpr) <- (baseExpr as RefExpr)) {
                                    rearrangeResolvedFunction = refExpr.isThis
                                }
                            }
                        }
                    }
                    if (rearrangeResolvedFunction) {
                        let targetCallExpr = (target as CallExpr).getOrThrow()
                        TargetAddrMapInsert(sourceCallExpr.resolvedFunction,
                            { value: FuncDecl => targetCallExpr.resolvedFunction = value })
                    }
                case ASTKind.RETURN_EXPR =>
                    let sourceReturnExpr = (from as ReturnExpr).getOrThrow()
                    let targetReturnExpr = (target as ReturnExpr).getOrThrow()
                    TargetAddrMapInsert(sourceReturnExpr.refFuncBody,
                        { value: FuncBody => targetReturnExpr.refFuncBody = value })
                case ASTKind.JUMP_EXPR =>
                    let sourceJumpExpr = (from as JumpExpr).getOrThrow()
                    let targetJumpExpr = (target as JumpExpr).getOrThrow()
                    TargetAddrMapInsert(sourceJumpExpr.refLoop,
                        { value: Expr => targetJumpExpr.refLoop = value })
                case ASTKind.REF_TYPE =>
                    let sourceRefType = (from as RefType).getOrThrow()
                    let targetRefType = (target as RefType).getOrThrow()
                    TargetAddrMapInsert(sourceRefType.ref.target,
                        { value: Decl => targetRefType.ref.target = value })
                case ASTKind.QUALIFIED_TYPE =>
                    let sourceQualifiedType = (from as QualifiedType).getOrThrow()
                    let targetQualifiedType = (target as QualifiedType).getOrThrow()
                    TargetAddrMapInsert(sourceQualifiedType.target,
                        { value: Decl => targetQualifiedType.target = value })
                case ASTKind.FUNC_DECL =>
                    let sourceFuncDecl = (from as FuncDecl).getOrThrow()
                    let targetFuncDecl = (target as FuncDecl).getOrThrow()
                    TargetAddrMapInsert(sourceFuncDecl.ownerFunc,
                        { value: FuncDecl => targetFuncDecl.ownerFunc = value })
                    TargetAddrMapInsert(sourceFuncDecl.propDecl,
                        { value: PropDecl => targetFuncDecl.propDecl = value })
                case ASTKind.VAR_DECL =>
                    let sourceVarDecl = (from as VarDecl).getOrThrow()
                    let targetVarDecl = (target as VarDecl).getOrThrow()
                    TargetAddrMapInsert(sourceVarDecl.parentPattern,
                        { value: Pattern => targetVarDecl.parentPattern = value })
                case _ => ()
            }
            visitor(from, target)
        }

        let targetNode = InstantiateNode(node, collectMap)
        for ((source, setter) in targetAddr2targetAddr) {
            if (let Some(cloned) <- source2cloned.get(source)) {
                setter(cloned)
            }
        }
        return targetNode
    }

    public static func GetGeneralDecl(clonedDecl: Decl): Decl {
        if (let Some(genericDecl) <- clonedDecl.genericDecl) {
            return genericDecl
        }
        if (clonedDecl.TestAttr(Attribute.GENERATED_TO_MOCK)) {
            return clonedDecl
        }
        if (let Some(genericDecl) <- ins2generic.get(clonedDecl.objectId)) {
            return genericDecl
        }
        CJC_ASSERT(false)
        return clonedDecl
    }

    public static func GetInstantiatedDecl(genericDecl: Decl): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        if (let Some(values) <- generic2ins.get(genericDecl.objectId)) {
            for (value in values) {
                out.add(value)
            }
        }
        return out
    }

    public static func RegisterInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
        registerInstantiation(genericDecl, instantiatedDecl)
    }

    public static func ResetGlobalMap(): Unit {
        generic2ins.clear()
        ins2generic.clear()
    }
}
