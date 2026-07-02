package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.Range as BasicRange
import cangjie_compiler::ast.*
import cangjie_compiler::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK}

private func GetParamsType(typeList: Array<Option<Ty>>): String {
    let result = StringBuilder()
    result.append("(")
    var idx: Int64 = 0
    while (idx < typeList.size) {
        let tyName = if (let Some(ty) <- typeList[idx]) {
            ty.String()
        } else {
            "UnknownType"
        }
        result.append(tyName)
        if (idx + 1 < typeList.size) {
            result.append(", ")
        }
        idx++
    }
    result.append(")")
    return result.toString()
}

private func DiagWrongNumberOfArgumentsCommon(diag: BasicDiagnosticEngine, ce: CallExpr,
    paramTys: Array<Option<Ty>>, fd: Option<FuncDecl>): Unit {
    let expectedNum = paramTys.size
    let foundNum = ce.args.size
    CJC_ASSERT(expectedNum != foundNum)
    let symptom = if (expectedNum > foundNum) {
        if (expectedNum - foundNum == 1) { "missing argument" } else { "missing arguments" }
    } else {
        if (foundNum - expectedNum == 1) { "extra argument given" } else { "extra arguments given" }
    }
    let lst = GetParamsType(paramTys)
    let expected = expectedNum.toString() + (if (expectedNum == 1) { " argument" } else { " arguments" })
    let parenPosExist = !ce.leftParenPos.IsZero() && !ce.rightParenPos.IsZero()
    let beginPos = if (parenPosExist) { ce.leftParenPos } else { ce.begin }
    let lastArgAfterParen = !ce.args.isEmpty() && ce.args[ce.args.size - 1].end > ce.rightParenPos
    let endPos = if (parenPosExist) {
        if (lastArgAfterParen) { ce.args[ce.args.size - 1].end } else { ce.rightParenPos + 1 }
    } else {
        ce.end
    }
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_wrong_number_of_arguments,
        MakeRange(beginPos, endPos), arguments: [symptom, lst])
    builder.AddMainHintArguments([expected, foundNum.toString()])
    if (let Some(funcDecl) <- fd) {
        if (funcDecl.ShouldDiagnose()) {
            builder.AddNote(MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End()), "found candidate")
        }
    } else if (let Some(baseFunc) <- ce.baseFunc) {
        if (let Some(target) <- baseFunc.GetTarget()) {
            if (let Some(varDecl) <- (target as VarDecl)) {
                if (varDecl.ShouldDiagnose()) {
                    builder.AddNote(MakeRange(varDecl.identifier.Begin(), varDecl.identifier.End()), "found candidate")
                }
            }
        }
    }
    builder.Emit()
}

public func DiagWrongNumberOfArguments(diag: BasicDiagnosticEngine, ce: CallExpr, paramTys: Array<Ty>): Unit {
    if (!ce.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    let optionParamTys = ArrayList<Option<Ty>>()
    for (paramTy in paramTys) {
        optionParamTys.add(Some(paramTy))
    }
    DiagWrongNumberOfArgumentsCommon(diag, ce, optionParamTys.toArray(), None)
}

public func MakeRangeForDeclIdentifier(decl: Decl): BasicRange {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
            CJC_NULLPTR_CHECK(funcDecl.outerDecl)
            let outerDecl = funcDecl.outerDecl.getOrThrow()
            if (funcDecl.identifier.Begin().IsZero()) {
                return MakeRange(outerDecl.identifier.Begin(), outerDecl.identifier.End())
            } else if (funcDecl.TestAttr(Attribute.PRIMARY_CONSTRUCTOR)) {
                return MakeRange(funcDecl.identifier.Begin(), outerDecl.identifier.End())
            } else {
                return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.End())
            }
        }
    } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(extendedType) <- extendDecl.extendedType) {
            if (extendDecl.TestAttr(Attribute.FROM_COMMON_PART)) {
                return MakeRange(extendDecl.begin, extendDecl.end)
            }
            return MakeRange(extendedType.begin, extendedType.end)
        }
    } else if (let Some(vpd) <- (decl as VarWithPatternDecl)) {
        if (let Some(pattern) <- vpd.irrefutablePattern) {
            return MakeRange(pattern.begin, pattern.end)
        }
    }
    if (decl.identifier.Begin().IsZero()) {
        return MakeRange(decl.begin, decl.end)
    } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (funcDecl.isGetter || funcDecl.isSetter) {
            return MakeRange(funcDecl.identifier.Begin(), funcDecl.identifier.Begin() + 3)
        }
    }
    return MakeRange(decl.identifier.Begin(), decl.identifier.End())
}

public func DiagMismatchedTypesWithFoundTy(diag: BasicDiagnosticEngine, node: Node, expected: String,
    found: String, note!: String = ""): Unit {
    if (!node.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    CJC_ASSERT(expected != found)
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_mismatched_types, MakeRange(node.begin, node.end))
    builder.AddMainHintArguments([expected, found])
    if (!note.isEmpty()) {
        builder.AddNote(note)
    }
    builder.Emit()
}

public func DiagMismatchedTypesWithFoundTy(diag: BasicDiagnosticEngine, node: Node, expected: Ty,
    found: Ty, note!: String = ""): Unit {
    if (!node.ShouldDiagnose(allowCompilerAdd: true)) {
        return
    }
    CJC_ASSERT(Ty.IsTyCorrect(expected))
    CJC_ASSERT(Ty.IsTyCorrect(found))
    var expectedStr = expected.String()
    var foundStr = found.String()
    if (expectedStr == foundStr) {
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_mismatched_types, MakeRange(node.begin, node.end))
        if (let Some(expectedDecl) <- Ty.GetDeclPtrOfTy(Some(expected))) {
            expectedStr += "' in '" + expectedDecl.fullPackageName
            builder.AddNote(MakeRangeForDeclIdentifier(expectedDecl), "'" + expectedStr + "'")
        }
        if (let Some(foundDecl) <- Ty.GetDeclPtrOfTy(Some(found))) {
            foundStr += "' in '" + foundDecl.fullPackageName
            builder.AddNote(MakeRangeForDeclIdentifier(foundDecl), "'" + foundStr + "'")
        }
        builder.AddMainHintArguments([expectedStr, foundStr])
        if (!note.isEmpty()) {
            builder.AddNote(note)
        }
        builder.Emit()
    } else {
        DiagMismatchedTypesWithFoundTy(diag, node, expectedStr, foundStr, note: note)
    }
}

public func DiagMismatchedTypes(diag: BasicDiagnosticEngine, node: Node, target: Ty,
    note!: String = ""): Unit {
    if (!Ty.IsTyCorrect(node.GetTy())) {
        return
    }
    DiagMismatchedTypesWithFoundTy(diag, node, target, node.GetTy().getOrThrow(), note: note)
}
