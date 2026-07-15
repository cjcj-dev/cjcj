package cjcj::chir

import cjcj::utils.{CJC_ASSERT, ProfileRecorder}
import std.collection.*

private func IsExpectedValueType(expectedValueType: Type, curType: Type, builder: CHIRBuilder,
    doCheck: Bool, visited: HashSet<Type>): Bool {
    if (doCheck && curType == expectedValueType) {
        return true
    }
    if (visited.contains(curType)) {
        return false
    }
    visited.add(curType)
    if (let Some(enumType) <- (curType as EnumType)) {
        for (ctorInfo in enumType.GetConstructorInfos(builder)) {
            for (ty in ctorInfo.funcType.getOrThrow().GetParamTypes()) {
                if (IsExpectedValueType(expectedValueType, ty, builder, true, visited)) {
                    return true
                }
            }
        }
    } else if (let Some(structType) <- (curType as StructType)) {
        for (ty in structType.GetInstantiatedMemberTys(builder)) {
            if (IsExpectedValueType(expectedValueType, ty, builder, true, visited)) {
                return true
            }
        }
    } else if (let Some(tupleType) <- (curType as TupleType)) {
        for (ty in tupleType.GetElementTypes()) {
            if (IsExpectedValueType(expectedValueType, ty, builder, true, visited)) {
                return true
            }
        }
    }
    return false
}

private func IsRecursionType(specifiedType: Type, builder: CHIRBuilder): Bool {
    let visited = HashSet<Type>()
    return IsExpectedValueType(specifiedType, specifiedType, builder, false, visited)
}

private func GetTargetType(baseType: Type, path: ArrayList<UInt64>, builder: CHIRBuilder): Type {
    var subType = baseType
    for (p in path) {
        subType = GetFieldOfType(subType, p, builder).getOrThrow()
    }
    return subType
}

// BoxRecursionValueType.cpp:74-103, the named recursive lambda leftIsGenericOrEqualToRight.
private func leftIsGenericOrEqualToRight(left: Type, right: Type): Bool {
    let leftType = left.StripAllRefs()
    let rightType = right.StripAllRefs()
    if (leftType == rightType) {
        return true
    }
    if (leftType.IsGeneric()) {
        return true
    }
    if (leftType.GetTypeKind() != rightType.GetTypeKind()) {
        return false
    }
    let leftTypeArgs = leftType.GetTypeArgs()
    let rightTypeArgs = rightType.GetTypeArgs()
    if (leftTypeArgs.size != rightTypeArgs.size) {
        return false
    }
    if ((leftType.IsClass() || leftType.IsStruct() || leftType.IsEnum()) &&
        (leftType as CustomType).getOrThrow().GetCustomTypeDef() !=
        (rightType as CustomType).getOrThrow().GetCustomTypeDef()) {
        return false
    }
    for (i in 0..leftTypeArgs.size) {
        if (!leftIsGenericOrEqualToRight(leftTypeArgs[i], rightTypeArgs[i])) {
            return false
        }
    }
    return true
}

private func LeftIsBoxTypeOfRight(left: Type, right: Type): Bool {
    let leftType = left.StripAllRefs()
    if (!leftType.IsBox()) {
        return false
    }
    return leftIsGenericOrEqualToRight((leftType as BoxType).getOrThrow().GetBaseType(), right)
}

private func BoxStoreElementRefSrcValueIfNeed(ser: StoreElementRef, builder: CHIRBuilder): Unit {
    let targetType = GetTargetType(ser.GetLocation().GetType().getOrThrow(), ser.GetPath(), builder)
    let srcValue = ser.GetValue()
    let srcType = srcValue.GetType().getOrThrow()
    if (LeftIsBoxTypeOfRight(targetType, srcType)) {
        let parent = ser.GetParentBlock().getOrThrow()
        let boxType = builder.context.GetRefTy(builder.context.GetBoxTy(srcType))
        let boxExpr = builder.CreateBox(boxType, srcValue, parent)
        boxExpr.MoveBefore(ser)
        ser.ReplaceOperand(srcValue, boxExpr.GetResult().getOrThrow())
    }
}

private func UnBoxGetElementRefResIfNeed(ger: GetElementRef, builder: CHIRBuilder): Unit {
    // If the base of the GetElementRef expression is enum, it must be the index on which we want to get enum.
    // Therefore, we do not need to box the targetType.
    let baseType = ger.GetLocation().GetType().getOrThrow().StripAllRefs()
    if (baseType.IsEnum()) {
        return
    }
    let srcType = GetTargetType(baseType, ger.GetPath(), builder)
    let gerResult = ger.GetResult().getOrThrow()
    let targetType = gerResult.GetType().getOrThrow().StripAllRefs()
    if (LeftIsBoxTypeOfRight(srcType, targetType)) {
        let users = gerResult.GetUsers()
        CJC_ASSERT(users.size == 1 && users[0].GetExprKind() == ExprKind.LOAD)
        let boxRefType = builder.context.GetRefTy(builder.context.GetBoxTy(targetType))
        let gerResType = builder.context.GetRefTy(boxRefType)
        gerResult.SetType(gerResType)

        let load = gerResult.GetUsers()[0]
        CJC_ASSERT(load.GetExprKind() == ExprKind.LOAD)
        let loadRes = load.GetResult().getOrThrow()
        loadRes.SetType(boxRefType)

        let loadResUsers = loadRes.GetUsers()
        let unbox = builder.CreateUnBox(targetType, loadRes, ger.GetParentBlock().getOrThrow())
        unbox.MoveAfter(load)
        for (user in loadResUsers) {
            user.ReplaceOperand(loadRes, unbox.GetResult().getOrThrow())
        }
    }
}

private func BoxTupleOpIfNeed(tuple: Tuple, builder: CHIRBuilder): Unit {
    let tupleRes = tuple.GetResult().getOrThrow()
    if (!tupleRes.GetType().getOrThrow().IsEnum()) {
        return
    }
    let operands = tuple.GetOperands()
    let indexExpr = ((operands[0] as LocalVar).getOrThrow().GetExpr().getOrThrow() as Constant).getOrThrow()
    let index = if (indexExpr.IsBoolLit()) {
        if (indexExpr.GetBoolLitVal()) { 1 } else { 0 }
    } else {
        Int64(indexExpr.GetUnsignedIntLitVal())
    }
    operands.remove(at: 0)
    let enumDef = (tupleRes.GetType().getOrThrow() as EnumType).getOrThrow().GetEnumDef()
    let ctor = enumDef.GetCtor(index)
    let paramTypes = ctor.funcType.getOrThrow().GetParamTypes()
    CJC_ASSERT(operands.size == paramTypes.size)
    for (i in 0..paramTypes.size) {
        let paramType = paramTypes[i]
        let targetType = operands[i].GetType().getOrThrow()
        if (LeftIsBoxTypeOfRight(paramType, targetType)) {
            let srcValue = tuple.GetOperand(i + 1)
            let boxRefType = builder.context.GetRefTy(builder.context.GetBoxTy(srcValue.GetType().getOrThrow()))
            let boxExpr = builder.CreateBox(boxRefType, srcValue, tuple.GetParentBlock().getOrThrow())
            boxExpr.MoveBefore(tuple)
            tuple.ReplaceOperand(i + 1, boxExpr.GetResult().getOrThrow())
        }
    }
}

private func InsertUnBoxAfterField(field: Field, builder: CHIRBuilder): Unit {
    let fieldRes = field.GetResult().getOrThrow()
    let resType = fieldRes.GetType().getOrThrow()
    let boxRefType = builder.context.GetRefTy(builder.context.GetBoxTy(resType))
    fieldRes.SetType(boxRefType)
    let parent = field.GetParentBlock().getOrThrow()
    let oldUsers = fieldRes.GetUsers()
    let unbox = builder.CreateUnBox(resType, fieldRes, parent)
    unbox.MoveAfter(field)
    for (user in oldUsers) {
        user.ReplaceOperand(fieldRes, unbox.GetResult().getOrThrow())
    }
}

private func CastEnumTypeToTupleWithBoxArg(typecast: TypeCast, path: ArrayList<Int64>,
    builder: CHIRBuilder): Unit {
    let typecastRes = typecast.GetResult().getOrThrow()
    let targetType = (typecastRes.GetType().getOrThrow() as TupleType).getOrThrow()
    let eleTypes = targetType.GetElementTypes()
    for (i in path) {
        let boxType = builder.context.GetRefTy(builder.context.GetBoxTy(eleTypes[i]))
        CJC_ASSERT(i < eleTypes.size)
        eleTypes[i] = boxType
    }
    let newTargetType = builder.context.GetTupleTy(eleTypes)
    typecastRes.SetType(newTargetType)
}

private func FieldAndTypeCastNeedUnBox(field: Field, collected: HashMap<Expression, ArrayList<Int64>>,
    builder: CHIRBuilder): Bool {
    /** enum E {
     *      A | Box<Struct-S>&
     *  }
     *  %0: Enum-E = ...
     *  %1: Tuple<UInt64, Struct-S> = TypeCast(%0)
     *  %2: Struct-S = Field(%1, 1)
     *
     *  should be transform to:
     *  %0: Enum-E = ...
     *  %1: Tuple<UInt64, Box<Struct-S>&> = TypeCast(%0)
     *  %2: Box<Struct-S>& = Field(%1, 1)
     *  %3: Struct-S = UnBox(%2)
     */
    let index = field.GetPath()
    if (index.size != 1) {
        return false
    }
    if (index[0] == 0u64) {
        return false
    }
    let base = field.GetBase()
    if (!base.IsLocalVar()) {
        return false
    }
    let baseExpr = (base as LocalVar).getOrThrow().GetExpr().getOrThrow()
    if (baseExpr.GetExprKind() != ExprKind.TYPECAST) {
        return false
    }
    let typecast = (baseExpr as TypeCast).getOrThrow()
    let srcType = typecast.GetSourceTy().getOrThrow()
    if (!srcType.IsEnum()) {
        return false
    }
    let targetType = typecast.GetTargetTy().getOrThrow()
    if (!targetType.IsTuple()) {
        return false
    }
    if (let Some(collectedPath) <- collected.get(typecast)) {
        for (i in collectedPath) {
            if (UInt64(i) == index[0]) {
                InsertUnBoxAfterField(field, builder)
                break
            }
        }
        return true
    }
    let enumDef = (srcType as EnumType).getOrThrow().GetEnumDef()
    let tupleArgs = (targetType as TupleType).getOrThrow().GetElementTypes()
    tupleArgs.remove(at: 0)
    let path = ArrayList<Int64>()
    var fieldRes: Option<Field> = None
    let offset: Int64 = 1
    for (ctor in enumDef.GetCtors()) {
        let paramTypes = ctor.funcType.getOrThrow().GetParamTypes()
        if (paramTypes.size != tupleArgs.size) {
            continue
        }
        for (i in 0..paramTypes.size) {
            let paramType = paramTypes[i]
            let argType = tupleArgs[i]
            if (LeftIsBoxTypeOfRight(paramType, argType)) {
                path.add(i + offset)
                if (UInt64(i + offset) == index[0]) {
                    fieldRes = field
                }
            } else if (!paramType.IsEqualOrSubTypeOf(argType, builder)) {
                path.clear()
                fieldRes = None
                break
            }
        }
        if (!path.isEmpty()) {
            break
        }
    }
    if (path.isEmpty()) {
        return false
    }
    collected[typecast] = path
    CastEnumTypeToTupleWithBoxArg(typecast, path, builder)
    if (let Some(value) <- fieldRes) {
        InsertUnBoxAfterField(value, builder)
    }
    return true
}

private func UnBoxFieldResIfNeed(field: Field, builder: CHIRBuilder): Unit {
    let baseType = field.GetBase().GetType().getOrThrow()
    if (baseType.IsEnum()) {
        return
    }
    let targetType = GetTargetType(baseType, field.GetPath(), builder)
    let srcType = field.GetResult().getOrThrow().GetType().getOrThrow()
    if (LeftIsBoxTypeOfRight(targetType, srcType)) {
        InsertUnBoxAfterField(field, builder)
    }
}

public class BoxRecursionValueType {
    private let pkg: Package
    private let builder: CHIRBuilder

    public init(pkg: Package, builder: CHIRBuilder) {
        this.pkg = pkg
        this.builder = builder
    }

    private func CreateBoxTypeForRecursionEnum(): Unit {
        for (def in pkg.GetAllEnumDef()) {
            let allCtors = def.GetCtors()
            for (ctor in allCtors) {
                let paramTypes = ctor.funcType.getOrThrow().GetParamTypes()
                var hasRecursionType = false
                for (i in 0..paramTypes.size) {
                    if (IsRecursionType(paramTypes[i], builder)) {
                        hasRecursionType = true
                        paramTypes[i] = builder.context.GetRefTy(builder.context.GetBoxTy(paramTypes[i]))
                    }
                }
                if (hasRecursionType) {
                    let returnType = ctor.funcType.getOrThrow().GetReturnType()
                    ctor.funcType = builder.context.GetFuncTy(paramTypes, returnType)
                }
            }
            def.SetCtors(allCtors)
        }
    }

    private func CreateBoxTypeForRecursionStruct(): Unit {
        for (def in pkg.GetAllStructDef()) {
            let memberVars = def.GetDirectInstanceVars()
            for (memberVar in memberVars) {
                if (IsRecursionType(memberVar.ty, builder)) {
                    memberVar.ty = builder.context.GetRefTy(builder.context.GetBoxTy(memberVar.ty))
                }
            }
            def.SetDirectInstanceVars(memberVars)
        }
    }

    public func Run(): Unit {
        try (recorder = ProfileRecorder("Canonicalization", "BoxRecursionValueType")) {
            CreateBoxTypeForRecursionEnum()
            CreateBoxTypeForRecursionStruct()
            for (ty in builder.GetAllCustomTypes()) {
                (ty as CustomType).getOrThrow().ResetAllInstantiatedType()
            }
            InsertBoxAndUnboxExprForRecursionValueType()
        }
    }

    private func InsertBoxAndUnboxExprForRecursionValueType(): Unit {
        let typecasts = HashMap<Expression, ArrayList<Int64>>()
        let visitor: VisitExprActionFunc = { e: Expression =>
            if (let Some(ser) <- (e as StoreElementRef)) {
                BoxStoreElementRefSrcValueIfNeed(ser, builder)
            } else if (let Some(ger) <- (e as GetElementRef)) {
                UnBoxGetElementRefResIfNeed(ger, builder)
            } else if (let Some(tuple) <- (e as Tuple)) {
                BoxTupleOpIfNeed(tuple, builder)
            } else if (let Some(field) <- (e as Field)) {
                let res = FieldAndTypeCastNeedUnBox(field, typecasts, builder)
                if (!res) {
                    UnBoxFieldResIfNeed(field, builder)
                }
            }
            return VisitResult.CONTINUE
        }
        for (funcValue in pkg.GetGlobalFuncsWithBody()) {
            Visitor.Visit(funcValue, visitor)
        }
    }
}
