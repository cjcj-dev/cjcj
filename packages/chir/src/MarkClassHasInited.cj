package cjcj::chir

import std.collection.*
import cjcj::utils.{HAS_INITED_IDENT, ProfileRecorder}

private func IsObjCMirror(classDef: ClassDef): Bool {
    return classDef.TestAttr(Attribute.OBJ_C_MIRROR)
}

private func IsJavaMirror(classDef: ClassDef): Bool {
    return classDef.TestAttr(Attribute.JAVA_MIRROR)
}

private func IsMirror(classDef: ClassDef): Bool {
    return IsObjCMirror(classDef) || IsJavaMirror(classDef)
}

public class MarkClassHasInited {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    private func AddHasInitedFlagToClassDef(classDef: ClassDef): Unit {
        if (IsMirror(classDef)) {
            return
        }

        let attributeInfo = AttributeInfo()
        attributeInfo.Enable(Attribute.NO_REFLECT_INFO)
        attributeInfo.Enable(Attribute.COMPILER_ADD)
        attributeInfo.Enable(Attribute.PRIVATE)
        attributeInfo.Enable(Attribute.HAS_INITED_FIELD)
        let memberInfo = MemberVarInfo(HAS_INITED_IDENT, builder.context.GetBoolTy())
        memberInfo.attributeInfo.CopyFrom(attributeInfo)
        classDef.AddInstanceVar(memberInfo)
    }

    private func AddGuardToFinalizer(classDef: ClassDef): Unit {
        let finalizer = classDef.GetFinalizer()
        if (finalizer.isNone() || !finalizer.getOrThrow().IsFuncWithBody()) {
            return
        }

        let finalizerFunc = finalizer.getOrThrow()
        let finalizerBody = finalizerFunc.GetBody().getOrThrow()
        let block = builder.CreateBlock(finalizerBody)
        let thisArg = finalizerFunc.GetParam(0)
        let boolTy = builder.context.GetBoolTy()
        let path = ArrayList<String>([HAS_INITED_IDENT])
        let ref = builder.CreateGetElementByName(builder.context.GetRefTy(boolTy), thisArg, path, block)
        block.AppendExpression(ref)
        let load = builder.CreateLoad(boolTy, ref.GetResult().getOrThrow(), block)
        block.AppendExpression(load)

        let entry = finalizerFunc.GetEntryBlock().getOrThrow()
        let exit = builder.CreateBlock(finalizerBody)
        let createdExit57 = builder.CreateExit(None, exit)
        exit.AppendExpression(createdExit57)
        let createdBranch58 = builder.CreateBranch(load.GetResult().getOrThrow(), entry, exit, block)
        block.AppendExpression(createdBranch58)
        finalizerBody.SetEntryBlock(block)
    }

    private func AssignHasInitedFlagToFalseInConstructorHead(constructor: Function): Unit {
        let boolTy = builder.context.GetBoolTy()
        let entry = constructor.GetEntryBlock().getOrThrow()
        let falseVal = builder.CreateConstant(boolTy, BoolLiteral(false), entry)
        entry.AppendExpression(falseVal)
        let thisArg = constructor.GetParam(0)
        let path = ArrayList<String>([HAS_INITED_IDENT])
        let storeRef = builder.CreateStoreElementByName(falseVal.GetResult().getOrThrow(), thisArg, path, entry)
        entry.AppendExpression(storeRef)
        entry.InsertExprIntoHead(storeRef)
        entry.InsertExprIntoHead(falseVal)
    }

    private func AssignHasInitedFlagToTrueInConstructorExit(constructor: Function): Unit {
        let boolTy = builder.context.GetBoolTy()
        let thisArg = constructor.GetParam(0)
        let constructorBody = constructor.GetBody().getOrThrow()
        for (block in constructorBody.GetBlocks()) {
            let terminator = block.GetTerminator()
            if (terminator.isNone() || terminator.getOrThrow().GetExprKind() != ExprKind.EXIT) {
                continue
            }
            let trueVal = builder.CreateConstant(boolTy, BoolLiteral(true), block)
            trueVal.MoveBefore(terminator.getOrThrow())
            let path = ArrayList<String>([HAS_INITED_IDENT])
            let storeRef = builder.CreateStoreElementByName(trueVal.GetResult().getOrThrow(), thisArg, path, block)
            storeRef.MoveBefore(terminator.getOrThrow())
        }
    }

    public func RunOnPackage(pkg: Package): Unit {
        try (recorder = ProfileRecorder("Canonicalization", "MarkClassHasInited")) {
            for (classDef in pkg.GetAllClassDef()) {
                if (classDef.GetFinalizer().isNone()) {
                    continue
                }
                AddHasInitedFlagToClassDef(classDef)
                for (method in classDef.GetMethods()) {
                    if (!method.IsConstructor() || !method.IsFuncWithBody()) {
                        continue
                    }
                    AssignHasInitedFlagToFalseInConstructorHead(method)
                    AssignHasInitedFlagToTrueInConstructorExit(method)
                }

                AddGuardToFinalizer(classDef)
            }
        }
    }
}
