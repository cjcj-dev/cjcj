package cangjie_compiler::chir

import cangjie_compiler::utils.{CJC_NULLPTR_CHECK, ProfileRecorder}
import std.collection.*

public class UpdateMemberVarPath {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Unit {
        try (recorder = ProfileRecorder("Canonicalization", "UpdateMemberVarPath")) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                if (let Some(body) <- fn.GetBody()) {
                    for (block in body.GetBlocks()) {
                        for (expr in block.GetExpressions()) {
                            UpdateExpression(expr)
                        }
                    }
                }
            }
        }
    }

    private func UpdateExpression(expr: Expression): Unit {
        if (let Some(get) <- (expr as GetElementByName)) {
            UpdateToGetElementRef(get)
        } else if (let Some(store) <- (expr as StoreElementByName)) {
            UpdateToStoreElementRef(store)
        } else if (let Some(field) <- (expr as FieldByName)) {
            UpdateToField(field)
        }
    }

    private func UpdateToGetElementRef(expr: GetElementByName): Unit {
        let location = expr.GetLocation()
        let locationType = (location.GetType().getOrThrow().StripAllRefs() as CustomType).getOrThrow()
        let path = ChangeNameToPath(locationType, expr.GetNames())
        let parent = expr.GetParentBlock().getOrThrow()
        let replacement = builder.CreateGetElementRef(expr.GetResult().getOrThrow().GetType().getOrThrow(), location, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        let rawResult = expr.GetResult().getOrThrow()
        let replacementResult = replacement.GetResult().getOrThrow()
        replacementResult.CopyBaseInfoFrom(rawResult)
        replacementResult.AppendAttributeInfo(rawResult.GetAttributeInfo())
        expr.ReplaceWith(replacement)
    }

    private func UpdateToStoreElementRef(expr: StoreElementByName): Unit {
        let location = expr.GetLocation()
        let locationType = (location.GetType().getOrThrow().StripAllRefs() as CustomType).getOrThrow()
        let path = ChangeNameToPath(locationType, expr.GetNames())
        let parent = expr.GetParentBlock().getOrThrow()
        let replacement = builder.CreateStoreElementRef(expr.GetValue(), location, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        let rawResult = expr.GetResult().getOrThrow()
        let replacementResult = replacement.GetResult().getOrThrow()
        replacementResult.CopyBaseInfoFrom(rawResult)
        replacementResult.AppendAttributeInfo(rawResult.GetAttributeInfo())
        expr.ReplaceWith(replacement)
    }

    private func UpdateToField(expr: FieldByName): Unit {
        let base = expr.GetBase()
        let locationType = (base.GetType().getOrThrow().StripAllRefs() as CustomType).getOrThrow()
        let path = ChangeNameToPath(locationType, expr.GetNames())
        let parent = expr.GetParentBlock().getOrThrow()
        let replacement = builder.CreateField(expr.GetResult().getOrThrow().GetType().getOrThrow(), base, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        let rawResult = expr.GetResult().getOrThrow()
        let replacementResult = replacement.GetResult().getOrThrow()
        replacementResult.CopyBaseInfoFrom(rawResult)
        replacementResult.AppendAttributeInfo(rawResult.GetAttributeInfo())
        expr.ReplaceWith(replacement)
    }

    private func ChangeNameToPath(rootType: CustomType, names: ArrayList<String>): ArrayList<UInt64> {
        let path = ArrayList<UInt64>()
        var current: Option<CustomType> = rootType
        for (name in names) {
            CJC_NULLPTR_CHECK(current)
            let baseType = current.getOrThrow()
            let indexAndType = GetIndexByName(baseType, name)
            path.add(indexAndType[1])
            current = indexAndType[0] as CustomType
        }
        return path
    }

    private func GetIndexByName(baseType: CustomType, name: String): (Type, UInt64) {
        var memberVarInstType: Option<Type> = None
        let allMemberVars = baseType.GetCustomTypeDef().GetAllInstanceVars()
        let memberVarInstTypes = baseType.GetInstantiatedMemberTys()
        var index = allMemberVars.size
        while (index > 0) {
            index--
            if (allMemberVars[index].name == name) {
                memberVarInstType = memberVarInstTypes[index]
                break
            }
        }
        CJC_NULLPTR_CHECK(memberVarInstType)
        return (memberVarInstType.getOrThrow(), UInt64(index))
    }
}
