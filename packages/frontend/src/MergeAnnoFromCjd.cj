package cangjie_compiler::frontend

import std.collection.*

public func MergeCusAnno(target: Package, source: Package): Unit {
    let topDeclMapping = HashMap<String, (Decl, Option<Decl>)>()
    collectSourceTopDecls(source, topDeclMapping)
    matchTargetTopDecls(target, topDeclMapping)
    for ((_, pair) in topDeclMapping) {
        if (let Some(targetDecl) <- pair[1]) {
            mergeMemberDecl(pair[0], targetDecl)
        }
    }
}

private func collectSourceTopDecls(source: Package, mapping: HashMap<String, (Decl, Option<Decl>)>): Unit {
    for (file in source.files) {
        for (decl in file.decls) {
            let expandedDecl = expandApiLevelDeclIfNeeded(decl)
            if (expandedDecl.astKind == ASTKind.MAIN_DECL || expandedDecl.astKind == ASTKind.BUILTIN_DECL) {
                continue
            }
            let key = declMatchKey(expandedDecl)
            if (!mapping.contains(key)) {
                mapping.add(key, (expandedDecl, None))
            }
        }
    }
}

private func matchTargetTopDecls(target: Package, mapping: HashMap<String, (Decl, Option<Decl>)>): Unit {
    for (file in target.files) {
        for (decl in file.decls) {
            if (decl.astKind == ASTKind.BUILTIN_DECL || !decl.IsExportedDecl()) {
                continue
            }
            let key = declMatchKey(decl)
            if (let Some(pair) <- mapping.get(key)) {
                moveCustomAnnotations(pair[0], decl)
                mapping.remove(key)
                mapping.add(key, (pair[0], Some(decl)))
            }
        }
    }
}

private func mergeMemberDecl(source: Decl, target: Decl): Unit {
    let memberMapping = HashMap<String, (Decl, Option<Decl>)>()
    for (member in source.GetMemberDecls()) {
        let expandedDecl = expandApiLevelDeclIfNeeded(member)
        let key = declMatchKey(expandedDecl)
        if (!memberMapping.contains(key)) {
            memberMapping.add(key, (expandedDecl, None))
        }
    }
    for (member in target.GetMemberDecls()) {
        let key = declMatchKey(member)
        if (let Some(pair) <- memberMapping.get(key)) {
            moveCustomAnnotations(pair[0], member)
            memberMapping.remove(key)
            memberMapping.add(key, (pair[0], Some(member)))
        }
    }
    for ((_, pair) in memberMapping) {
        if (let Some(targetMember) <- pair[1]) {
            mergeFuncParamAnnotations(pair[0], targetMember)
        }
    }
}

private func mergeFuncParamAnnotations(source: Decl, target: Decl): Unit {
    if (!source.IsFunc() || !target.IsFunc()) {
        return
    }
    if (let Some(sourceFunc) <- (source as FuncDecl)) {
        if (let Some(targetFunc) <- (target as FuncDecl)) {
            let srcParams = sourceFunc.funcBody.params
            let dstParams = targetFunc.funcBody.params
            var idx: Int64 = 0
            while (idx < srcParams.size && idx < dstParams.size) {
                moveCustomAnnotationsFromParam(srcParams[idx], dstParams[idx])
                idx++
            }
        }
    }
}

private func moveCustomAnnotations(source: Decl, target: Decl): Unit {
    var idx: Int64 = 0
    while (idx < source.annotations.size) {
        if (source.annotations[idx].kind == AnnotationKind.CUSTOM) {
            target.annotations.add(source.annotations[idx])
            source.annotations.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func moveCustomAnnotationsFromParam(source: FuncParam, target: FuncParam): Unit {
    var idx: Int64 = 0
    while (idx < source.annotations.size) {
        if (source.annotations[idx].kind == AnnotationKind.CUSTOM) {
            target.annotations.add(source.annotations[idx])
            source.annotations.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func expandApiLevelDeclIfNeeded(decl: Decl): Decl {
    if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
        if (macroDecl.invocation.identifier == "APILevel") {
            ExpandToAPILevel(macroDecl.invocation)
            if (let Some(expanded) <- macroDecl.invocation.decl) {
                return expanded
            }
        }
    }
    return decl
}

private func ExpandToAPILevel(invocation: MacroInvocation): Unit {
    if (let Some(decl) <- invocation.decl) {
        for (anno in decl.annotations) {
            if (anno.identifier.Val() == "APILevel") {
                return
            }
        }
        let apiLevelAnno = Annotation()
        apiLevelAnno.identifier = SrcIdentifier("APILevel")
        var lastIdentifier = ""
        for (attr in invocation.attrs) {
            if (attr.kind == FrontendTokenKind.IDENTIFIER) {
                lastIdentifier = attr.value
            }
            if (attr.kind == FrontendTokenKind.STRING_LITERAL || attr.kind == FrontendTokenKind.INTEGER_LITERAL ||
                attr.kind == FrontendTokenKind.BOOL_LITERAL) {
                if (lastIdentifier.isEmpty()) {
                    apiLevelAnno.args.add(attr.value)
                } else {
                    apiLevelAnno.args.add(lastIdentifier + ":" + attr.value)
                }
            }
        }
        apiLevelAnno.kind = AnnotationKind.CUSTOM
        decl.annotations.add(apiLevelAnno)
    }
}

private func declMatchKey(decl: Decl): String {
    let id = if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) { "init" } else { decl.identifier.Val() }
    let kind = if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL) { ASTKind.FUNC_DECL } else { decl.astKind }
    let builder = StringBuilder()
    builder.append(ASTKindName(kind))
    builder.append("|")
    builder.append(id)
    if (let Some(generic) <- decl.generic) {
        builder.append("|g:")
        for (param in generic.typeParameters) {
            builder.append(param)
            builder.append(";")
        }
        builder.append("|gc:")
        for (constraint in generic.genericConstraints) {
            builder.append(normalizeGenericConstraint(constraint))
            builder.append(";")
        }
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        builder.append("|params:")
        for (param in funcDecl.funcBody.params) {
            builder.append(param.identifier.Val())
            builder.append(":")
            if (let Some(paramType) <- param.typeNode) {
                builder.append(typeKey(paramType))
            }
            builder.append(";")
        }
        if (let Some(retType) <- funcDecl.funcBody.retType) {
            builder.append("|ret:")
            builder.append(typeKey(retType))
        }
    } else if (let Some(varDecl) <- (decl as VarDecl)) {
        if (let Some(typeNode) <- varDecl.typeNode) {
            builder.append("|type:")
            builder.append(typeKey(typeNode))
        }
    } else if (let Some(extendDecl) <- (decl as ExtendDecl)) {
        if (let Some(typeNode) <- extendDecl.extendedType) {
            builder.append("|extends:")
            builder.append(typeKey(typeNode))
        }
        for (typeNode in extendDecl.inheritedTypes) {
            builder.append("|inherit:")
            builder.append(typeKey(typeNode))
        }
    } else if (let Some(macroDecl) <- (decl as MacroExpandDecl)) {
        builder.append("|macro:")
        builder.append(macroDecl.invocation.fullName)
        builder.append("|")
        builder.append(macroDecl.invocation.identifier)
    }
    return builder.toString()
}

private func normalizeGenericConstraint(constraint: String): String {
    return constraint.replace(" ", "")
}

private func typeKey(typeNode: Type): String {
    let builder = StringBuilder()
    builder.append(ASTKindName(typeNode.astKind))
    builder.append(":")
    builder.append(typeNode.name)
    if (!typeNode.typeArguments.isEmpty()) {
        builder.append("<")
        var idx: Int64 = 0
        while (idx < typeNode.typeArguments.size) {
            if (idx > 0) {
                builder.append(",")
            }
            builder.append(typeKey(typeNode.typeArguments[idx]))
            idx++
        }
        builder.append(">")
    }
    return builder.toString()
}
