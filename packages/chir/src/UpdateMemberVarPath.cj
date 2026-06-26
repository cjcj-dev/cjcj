package cangjie_compiler::chir

import std.collection.*

public class UpdateMemberVarPath {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Unit {
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
        let customTy = CustomTypeFromValue(location) ?? return
        let path = ChangeNameToPath(customTy, expr.GetNames()) ?? return
        let parent = expr.GetParentBlock() ?? return
        let replacement = builder.CreateGetElementRef(RequiredResultType(expr), location, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        expr.ReplaceWith(replacement)
    }

    private func UpdateToStoreElementRef(expr: StoreElementByName): Unit {
        let location = expr.GetLocation()
        let customTy = CustomTypeFromValue(location) ?? return
        let path = ChangeNameToPath(customTy, expr.GetNames()) ?? return
        let parent = expr.GetParentBlock() ?? return
        let replacement = builder.CreateStoreElementRef(expr.GetValue(), location, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        expr.ReplaceWith(replacement)
    }

    private func UpdateToField(expr: FieldByName): Unit {
        let base = expr.GetBase()
        let customTy = CustomTypeFromValue(base) ?? return
        let path = ChangeNameToPath(customTy, expr.GetNames()) ?? return
        let parent = expr.GetParentBlock() ?? return
        let replacement = builder.CreateField(RequiredResultType(expr), base, path, parent)
        replacement.CopyBaseInfoFrom(expr)
        expr.ReplaceWith(replacement)
    }

    private func ChangeNameToPath(rootType: CustomType, names: ArrayList<String>): Option<ArrayList<UInt64>> {
        let path = ArrayList<UInt64>()
        var current: Option<CustomType> = rootType
        for (name in names) {
            let baseType = current ?? return None
            let indexAndType = GetIndexByName(baseType, name) ?? return None
            path.add(UInt64(indexAndType.index))
            current = indexAndType.memberType.StripAllRefs() as CustomType
        }
        return Some(path)
    }

    private func GetIndexByName(baseType: CustomType, name: String): Option<MemberPathIndex> {
        let members = baseType.GetCustomTypeDef().GetAllInstanceVars()
        let memberTypes = baseType.GetInstantiatedMemberTys()
        var index = members.size - 1
        while (index >= 0) {
            if (members[index].name == name) {
                if (index < memberTypes.size) {
                    return Some(MemberPathIndex(index, memberTypes[index]))
                }
                return Some(MemberPathIndex(index, members[index].ty))
            }
            index--
        }
        return None
    }

    private func CustomTypeFromValue(value: Value): Option<CustomType> {
        if (let Some(ty) <- value.GetType()) {
            return ty.StripAllRefs() as CustomType
        }
        return None
    }
}

private class MemberPathIndex {
    public let index: Int64
    public let memberType: Type

    public init(index: Int64, memberType: Type) {
        this.index = index
        this.memberType = memberType
    }
}
