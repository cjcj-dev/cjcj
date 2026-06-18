package cangjie_compiler::chir

import std.collection.*
import std.convert.*
import cangjie_compiler::ast.Package as AstPackage
import cangjie_compiler::ast.Decl as AstDecl
import cangjie_compiler::ast.FuncDecl as AstFuncDecl
import cangjie_compiler::ast.MainDecl as AstMainDecl
import cangjie_compiler::ast.FuncBody as AstFuncBody
import cangjie_compiler::ast.Type as AstType
import cangjie_compiler::ast.LitConstExpr as AstLitConstExpr
import cangjie_compiler::ast.LitConstKind as AstLitConstKind
import cangjie_compiler::ast.Node as AstNode
import cangjie_compiler::ast.ReturnExpr as AstReturnExpr
import cangjie_compiler::ast.VarDecl as AstVarDecl
import cangjie_compiler::ast.AssignExpr as AstAssignExpr
import cangjie_compiler::ast.RefExpr as AstRefExpr
import cangjie_compiler::ast.BinaryExpr as AstBinaryExpr
import cangjie_compiler::ast.UnaryExpr as AstUnaryExpr
import cangjie_compiler::ast.ParenExpr as AstParenExpr
import cangjie_compiler::ast.CallExpr as AstCallExpr
import cangjie_compiler::ast.Expr as AstExpr
import cangjie_compiler::ast.Block as AstBlock
import cangjie_compiler::ast.IfExpr as AstIfExpr
import cangjie_compiler::ast.WhileExpr as AstWhileExpr
import cangjie_compiler::ast.JumpExpr as AstJumpExpr
import cangjie_compiler::ast.TokenKind as AstTokenKind
import cangjie_compiler::ast.InterpolationExpr as AstInterpolationExpr
import cangjie_compiler::ast.StringPartKind as AstStringPartKind
import cangjie_compiler::ast.StructDecl as AstStructDecl
import cangjie_compiler::ast.EnumDecl as AstEnumDecl
import cangjie_compiler::ast.MemberAccess as AstMemberAccess
import cangjie_compiler::ast.Attribute as AstAttribute
import cangjie_compiler::ast.ImportKind as AstImportKind
import cangjie_compiler::ast.ImportSpec as AstImportSpec
import cangjie_compiler::ast.MatchExpr as AstMatchExpr
import cangjie_compiler::ast.Pattern as AstPattern
import cangjie_compiler::ast.WildcardPattern as AstWildcardPattern
import cangjie_compiler::ast.VarOrEnumPattern as AstVarOrEnumPattern
import cangjie_compiler::ast.VarPattern as AstVarPattern
import cangjie_compiler::ast.EnumPattern as AstEnumPattern

private let REAL_AST_RETURN_NONE: Int64 = 0
private let REAL_AST_RETURN_INT: Int64 = 1
private let REAL_AST_RETURN_BOOL: Int64 = 2
private let REAL_AST_RETURN_UNIT: Int64 = 3
private let REAL_AST_RETURN_STRING: Int64 = 4

private let REAL_AST_TYPE_NONE: String = ""
private let REAL_AST_TYPE_INT: String = "Int64"
private let REAL_AST_TYPE_BOOL: String = "Bool"
private let REAL_AST_TYPE_UNIT: String = "Unit"
private let REAL_AST_TYPE_STRING: String = "String"
private let REAL_AST_STRUCT_PREFIX: String = "struct:"
private let REAL_AST_ENUM_PREFIX: String = "enum:"
private let REAL_AST_MATCH_BODY_STMT: Int64 = 0
private let REAL_AST_MATCH_BODY_RETURN: Int64 = 1
private let REAL_AST_MATCH_BODY_ASSIGN: Int64 = 2

private class RealASTFunctionInfo {
    let paramKinds: ArrayList<Int64> = ArrayList<Int64>()
    let paramTypes: ArrayList<String> = ArrayList<String>()
    let returnKind: Int64
    let returnType: String

    init(returnKind: Int64) {
        this.returnKind = returnKind
        returnType = RealASTTypeKeyFromKind(returnKind)
    }

    init(returnType: String) {
        this.returnType = returnType
        returnKind = RealASTKindFromTypeKey(returnType)
    }
}

private class RealASTPackageLoweringScope {
    let functions = HashMap<String, RealASTFunctionInfo>()
    let structs = HashMap<String, RealASTStructInfo>()
    let enums = HashMap<String, RealASTEnumInfo>()
    let enumCtors = HashMap<String, RealASTEnumCtorInfo>()
    let importedFunctions = ArrayList<RealASTImportedFunctionInfo>()

    func AddFunction(name: String, info: RealASTFunctionInfo): Bool {
        if (name.isEmpty() || functions.contains(name)) {
            return false
        }
        functions[name] = info
        return true
    }

    func GetFunction(name: String): Option<RealASTFunctionInfo> {
        return functions.get(name)
    }

    func AddStruct(info: RealASTStructInfo): Bool {
        if (info.name.isEmpty() || structs.contains(info.name)) {
            return false
        }
        structs[info.name] = info
        return true
    }

    func GetStruct(name: String): Option<RealASTStructInfo> {
        return structs.get(name)
    }

    func IsStruct(name: String): Bool {
        return structs.contains(name)
    }

    func AddEnum(info: RealASTEnumInfo): Bool {
        if (info.name.isEmpty() || enums.contains(info.name)) {
            return false
        }
        enums[info.name] = info
        return true
    }

    func GetEnum(name: String): Option<RealASTEnumInfo> {
        return enums.get(name)
    }

    func IsEnum(name: String): Bool {
        return enums.contains(name)
    }

    func AddEnumCtor(info: RealASTEnumCtorInfo): Bool {
        if (info.name.isEmpty() || enumCtors.contains(info.name)) {
            return false
        }
        enumCtors[info.name] = info
        return true
    }

    func GetEnumCtor(name: String): Option<RealASTEnumCtorInfo> {
        return enumCtors.get(name)
    }

    func AddImportedFunction(info: RealASTImportedFunctionInfo): Bool {
        if (info.localName.isEmpty() || functions.contains(info.localName)) {
            return false
        }
        functions[info.localName] = info.funcInfo
        importedFunctions.add(info)
        return true
    }
}

private class RealASTEnumCtorInfo {
    let name: String
    let decl: AstDecl
    let ownerName: String
    let tag: Int64
    let payloadTypes = ArrayList<String>()

    init(name: String, decl: AstDecl, ownerName: String, tag: Int64) {
        this.name = name
        this.decl = decl
        this.ownerName = ownerName
        this.tag = tag
    }

    func AddPayload(typeKey: String): Unit {
        payloadTypes.add(typeKey)
    }
}

private class RealASTEnumInfo {
    let name: String
    let decl: AstEnumDecl
    let ctors = HashMap<String, RealASTEnumCtorInfo>()
    let ctorNames = ArrayList<String>()

    init(name: String, decl: AstEnumDecl) {
        this.name = name
        this.decl = decl
    }

    func AddCtor(info: RealASTEnumCtorInfo): Bool {
        if (info.name.isEmpty() || ctors.contains(info.name)) {
            return false
        }
        ctors[info.name] = info
        ctorNames.add(info.name)
        return true
    }

    func GetCtor(name: String): Option<RealASTEnumCtorInfo> {
        return ctors.get(name)
    }
}

private class RealASTMatchPatternInfo {
    let isWildcard: Bool
    let tag: Int64
    let bindNames = ArrayList<String>()
    let bindTypes = ArrayList<String>()

    init(isWildcard: Bool, tag: Int64) {
        this.isWildcard = isWildcard
        this.tag = tag
    }

    func AddBinding(name: String, typeKey: String): Bool {
        if (name.isEmpty() || HasBinding(name)) {
            return false
        }
        bindNames.add(name)
        bindTypes.add(typeKey)
        return true
    }

    private func HasBinding(name: String): Bool {
        for (existing in bindNames) {
            if (existing == name) {
                return true
            }
        }
        return false
    }
}

private class RealASTImportedFunctionInfo {
    let localName: String
    let packageName: String
    let sourceName: String
    let chirName: String
    let funcInfo: RealASTFunctionInfo

    init(localName: String, packageName: String, sourceName: String, chirName: String,
        funcInfo: RealASTFunctionInfo) {
        this.localName = localName
        this.packageName = packageName
        this.sourceName = sourceName
        this.chirName = chirName
        this.funcInfo = funcInfo
    }
}

private class RealASTStructInitAssign {
    let fieldName: String
    let rhs: AstExpr

    init(fieldName: String, rhs: AstExpr) {
        this.fieldName = fieldName
        this.rhs = rhs
    }
}

private class RealASTMethodInfo {
    let name: String
    let loweredName: String
    let funcDecl: AstFuncDecl
    let funcInfo: RealASTFunctionInfo

    init(name: String, loweredName: String, funcDecl: AstFuncDecl, funcInfo: RealASTFunctionInfo) {
        this.name = name
        this.loweredName = loweredName
        this.funcDecl = funcDecl
        this.funcInfo = funcInfo
    }
}

private class RealASTStructInfo {
    let name: String
    let decl: AstStructDecl
    let fieldNames = ArrayList<String>()
    let fieldTypes = HashMap<String, String>()
    let fieldMutable = HashMap<String, Bool>()
    let fieldIndex = HashMap<String, Int64>()
    let initParams = ArrayList<String>()
    let initParamTypes = ArrayList<String>()
    let initAssigns = ArrayList<RealASTStructInitAssign>()
    let methods = HashMap<String, RealASTMethodInfo>()

    init(name: String, decl: AstStructDecl) {
        this.name = name
        this.decl = decl
    }

    func AddField(name: String, ty: String, mutable: Bool): Bool {
        if (name.isEmpty() || fieldTypes.contains(name)) {
            return false
        }
        fieldIndex[name] = fieldNames.size
        fieldNames.add(name)
        fieldTypes[name] = ty
        fieldMutable[name] = mutable
        return true
    }

    func FieldType(name: String): Option<String> {
        return fieldTypes.get(name)
    }

    func FieldIndex(name: String): Option<Int64> {
        return fieldIndex.get(name)
    }

    func FieldCanWrite(name: String): Bool {
        return fieldMutable.get(name) ?? false
    }

    func AddMethod(info: RealASTMethodInfo): Bool {
        if (info.name.isEmpty() || methods.contains(info.name)) {
            return false
        }
        methods[info.name] = info
        return true
    }

    func GetMethod(name: String): Option<RealASTMethodInfo> {
        return methods.get(name)
    }
}

private class RealASTBodyLowering {
    let ok: Bool
    let stmts: ArrayList<AST2CHIRStmtSpec>
    let returnKind: Int64
    let returnType: String

    init(ok: Bool, stmts: ArrayList<AST2CHIRStmtSpec>, returnKind: Int64) {
        this.ok = ok
        this.stmts = stmts
        this.returnKind = returnKind
        returnType = RealASTTypeKeyFromKind(returnKind)
    }

    init(ok: Bool, stmts: ArrayList<AST2CHIRStmtSpec>, returnType: String) {
        this.ok = ok
        this.stmts = stmts
        this.returnType = returnType
        returnKind = RealASTKindFromTypeKey(returnType)
    }
}

private class RealASTParamLowering {
    let types: ArrayList<Type> = ArrayList<Type>()
    let names: ArrayList<String> = ArrayList<String>()
}

private class RealASTStmtLowering {
    let stmt: AST2CHIRStmtSpec
    let returnKind: Int64
    let returnType: String

    init(stmt: AST2CHIRStmtSpec, returnKind: Int64) {
        this.stmt = stmt
        this.returnKind = returnKind
        returnType = RealASTTypeKeyFromKind(returnKind)
    }

    init(stmt: AST2CHIRStmtSpec, returnType: String) {
        this.stmt = stmt
        this.returnType = returnType
        returnKind = RealASTKindFromTypeKey(returnType)
    }
}

private class RealASTScopeSnapshot {
    let locals = HashMap<String, Bool>()
    let localKinds = HashMap<String, Int64>()
    let localTypes = HashMap<String, String>()
    let loopDepth: Int64
    let thisStructName: String

    init(scope: RealASTLoweringScope) {
        for ((name, mutable) in scope.locals) {
            locals[name] = mutable
        }
        for ((name, kind) in scope.localKinds) {
            localKinds[name] = kind
        }
        for ((name, ty) in scope.localTypes) {
            localTypes[name] = ty
        }
        loopDepth = scope.loopDepth
        thisStructName = scope.thisStructName
    }
}

private class RealASTLoweringScope {
    let locals = HashMap<String, Bool>()
    let localKinds = HashMap<String, Int64>()
    let localTypes = HashMap<String, String>()
    var loopDepth: Int64 = 0
    var thisStructName: String = ""

    init(body: AstFuncBody, packageScope!: Option<RealASTPackageLoweringScope> = None,
        thisStructName!: String = "") {
        this.thisStructName = thisStructName
        if (!thisStructName.isEmpty()) {
            locals["this"] = false
            localKinds["this"] = REAL_AST_RETURN_INT
            localTypes["this"] = RealASTStructTypeKey(thisStructName)
        }
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                let name = param.identifier.Val()
                if (!name.isEmpty()) {
                    locals[name] = false
                    if (let Some(typeNode) <- param.typeNode) {
                        if (let Some(kind) <- RealASTValueTypeKind(typeNode)) {
                            localKinds[name] = kind
                        }
                        if (let Some(typeKey) <- RealASTValueTypeKey(typeNode,
                            packageScope: packageScope)) {
                            localTypes[name] = typeKey
                        }
                    }
                }
            }
        }
    }

    func Contains(name: String): Bool {
        return locals.contains(name)
    }

    func Add(name: String, mutable: Bool, typeKey: String): Bool {
        if (locals.contains(name)) {
            return false
        }
        locals[name] = mutable
        localKinds[name] = RealASTKindFromTypeKey(typeKey)
        localTypes[name] = typeKey
        return true
    }

    func CanAssign(name: String): Bool {
        return locals.get(name) ?? false
    }

    func TypeKey(name: String): Option<String> {
        return localTypes.get(name)
    }

    func Save(): RealASTScopeSnapshot {
        return RealASTScopeSnapshot(this)
    }

    func Restore(snapshot: RealASTScopeSnapshot): Unit {
        locals.clear()
        localKinds.clear()
        for ((name, mutable) in snapshot.locals) {
            locals[name] = mutable
        }
        for ((name, kind) in snapshot.localKinds) {
            localKinds[name] = kind
        }
        localTypes.clear()
        for ((name, ty) in snapshot.localTypes) {
            localTypes[name] = ty
        }
        loopDepth = snapshot.loopDepth
        thisStructName = snapshot.thisStructName
    }

    func EnterLoop(): Unit {
        loopDepth++
    }

    func ExitLoop(): Unit {
        if (loopDepth > 0) {
            loopDepth--
        }
    }

    func InLoop(): Bool {
        return loopDepth > 0
    }
}

public func DescribeRealASTFunctionLowering(pkg: AstPackage): ArrayList<String> {
    let out = ArrayList<String>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if ((decl as AstMainDecl).isSome() || (decl as AstFuncDecl).isSome()) {
                out.add(RealASTDisplayName(decl))
            } else if (let Some(structDecl) <- (decl as AstStructDecl)) {
                if (let Some(body) <- structDecl.body) {
                    for (member in body.decls) {
                        if (let Some(funcDecl) <- (member as AstFuncDecl)) {
                            if (!funcDecl.TestAttr(AstAttribute.CONSTRUCTOR) &&
                                funcDecl.identifier.Val() != "init") {
                                out.add(RealASTStructMethodName(structDecl.identifier.Val(),
                                    funcDecl.identifier.Val()))
                            }
                        }
                    }
                }
            }
        }
    }
    return out
}

public func TryLowerRealASTPackage(pkg: AstPackage, builder: CHIRBuilder,
    sourcePackages: ArrayList<AstPackage>): Option<Package> {
    if (pkg.files.isEmpty()) {
        return None
    }
    if (let Some(spec) <- BuildRealASTPackageSpec(pkg, builder.context, sourcePackages)) {
        return Some(AST2CHIR(builder).LowerPackage(spec).pkg)
    }
    return None
}

private func BuildRealASTPackageSpec(pkg: AstPackage, context: CHIRContext,
    sourcePackages: ArrayList<AstPackage>): Option<AST2CHIRPackageSpec> {
    let packageScope = match (BuildRealASTPackageLoweringScope(pkg, sourcePackages)) {
        case Some(value) => value
        case None => return None
    }
    let spec = AST2CHIRPackageSpec(pkg.fullPackageName)
    spec.SetAccessLevel(AccessLevel.PUBLIC)
    var funcCount: Int64 = 0
    for (importedFunction in packageScope.importedFunctions) {
        let importedSpec = match (BuildRealASTImportedFunctionSpec(importedFunction, context)) {
            case Some(value) => value
            case None => return None
        }
        spec.AddFunction(importedSpec)
    }
    for (file in pkg.files) {
        let fileName = if (file.filePath.isEmpty()) { file.fileName } else { file.filePath }
        spec.RegisterSourceFile(UInt32(file.begin.fileID), fileName)
        for (decl in file.decls) {
            if (let Some(enumDecl) <- (decl as AstEnumDecl)) {
                let enumSpec = match (BuildRealASTEnumSpec(pkg.fullPackageName, enumDecl, context, fileName,
                    packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
                spec.AddType(enumSpec)
            } else if (let Some(structDecl) <- (decl as AstStructDecl)) {
                let structSpec = match (BuildRealASTStructSpec(pkg.fullPackageName, structDecl, context, fileName,
                    packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
                spec.AddType(structSpec)
                if (let Some(info) <- packageScope.GetStruct(structDecl.identifier.Val())) {
                    for ((_, methodInfo) in info.methods) {
                        let methodSpec = match (BuildRealASTStructMethodSpec(pkg.fullPackageName, info,
                            methodInfo, context, fileName, packageScope)) {
                            case Some(value) => value
                            case None => return None
                        }
                        spec.AddFunction(methodSpec)
                        funcCount++
                    }
                }
            } else if (let Some(fnSpec) <- BuildRealASTFunctionSpec(pkg.fullPackageName, decl, context, fileName,
                packageScope)) {
                spec.AddFunction(fnSpec)
                funcCount++
            } else {
                return None
            }
        }
    }
    if (funcCount == 0) {
        return None
    }
    return Some(spec)
}

private func BuildRealASTPackageLoweringScope(pkg: AstPackage,
    sourcePackages: ArrayList<AstPackage>): Option<RealASTPackageLoweringScope> {
    let scope = match (BuildRealASTPackageLocalLoweringScope(pkg)) {
        case Some(value) => value
        case None => return None
    }
    if (!ResolveRealASTSimpleImports(pkg, scope, sourcePackages)) {
        return None
    }
    return Some(scope)
}

private func BuildRealASTPackageLocalLoweringScope(pkg: AstPackage): Option<RealASTPackageLoweringScope> {
    let scope = RealASTPackageLoweringScope()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(enumDecl) <- (decl as AstEnumDecl)) {
                let info = match (AnalyzeRealASTEnumHeader(enumDecl)) {
                    case Some(value) => value
                    case None => return None
                }
                if (!scope.AddEnum(info)) {
                    return None
                }
            }
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(enumDecl) <- (decl as AstEnumDecl)) {
                if (!AnalyzeRealASTEnumConstructors(enumDecl, scope)) {
                    return None
                }
            }
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(structDecl) <- (decl as AstStructDecl)) {
                let info = match (AnalyzeRealASTStruct(structDecl, scope)) {
                    case Some(value) => value
                    case None => return None
                }
                if (!scope.AddStruct(info)) {
                    return None
                }
            }
        }
    }
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(structDecl) <- (decl as AstStructDecl)) {
                if (let Some(info) <- scope.GetStruct(structDecl.identifier.Val())) {
                    for ((_, methodInfo) in info.methods) {
                        if (!scope.AddFunction(methodInfo.loweredName, methodInfo.funcInfo)) {
                            return None
                        }
                    }
                }
                continue
            }
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                let name = funcDecl.identifier.Val()
                let body = match (funcDecl.funcBody) {
                    case Some(value) => value
                    case None => return None
                }
                let info = match (BuildRealASTFunctionInfo(body, scope)) {
                    case Some(value) => value
                    case None => return None
                }
                if (!scope.AddFunction(name, info)) {
                    return None
                }
            }
        }
    }
    return Some(scope)
}

private func ResolveRealASTSimpleImports(pkg: AstPackage, scope: RealASTPackageLoweringScope,
    sourcePackages: ArrayList<AstPackage>): Bool {
    for (file in pkg.files) {
        for (importSpec in file.imports) {
            if (!ResolveRealASTSimpleImport(pkg, scope, importSpec, sourcePackages)) {
                return false
            }
        }
    }
    return true
}

private func ResolveRealASTSimpleImport(pkg: AstPackage, scope: RealASTPackageLoweringScope,
    importSpec: AstImportSpec, sourcePackages: ArrayList<AstPackage>): Bool {
    if (importSpec.modifier.isSome() || importSpec.IsImportAlias() || importSpec.IsImportAll() ||
        importSpec.IsImportMulti()) {
        return false
    }
    let content = importSpec.content
    if (content.kind != AstImportKind.IMPORT_SINGLE || content.isBroken || content.hasBroken ||
        content.prefixPaths.isEmpty()) {
        return false
    }
    let localName = content.identifier.Val()
    let importedPackageName = content.GetPrefixPath()
    if (localName.isEmpty() || importedPackageName.isEmpty() || importedPackageName == pkg.fullPackageName) {
        return false
    }
    let importedPackage = match (FindRealASTSourcePackage(importedPackageName, pkg, sourcePackages)) {
        case Some(value) => value
        case None => return false
    }
    let importedDecl = match (FindRealASTUniqueFunctionDecl(importedPackage, localName)) {
        case Some(value) => value
        case None => return false
    }
    if (!importedDecl.IsExportedDecl()) {
        return false
    }
    let importedScope = match (BuildRealASTPackageLocalLoweringScope(importedPackage)) {
        case Some(value) => value
        case None => return false
    }
    let importedInfo = match (importedScope.GetFunction(localName)) {
        case Some(value) => value
        case None => return false
    }
    let chirName = RealASTStableMangledName(importedPackage.fullPackageName, importedDecl)
    return scope.AddImportedFunction(RealASTImportedFunctionInfo(localName, importedPackage.fullPackageName,
        localName, chirName, importedInfo))
}

private func FindRealASTSourcePackage(packageName: String, currentPkg: AstPackage,
    sourcePackages: ArrayList<AstPackage>): Option<AstPackage> {
    if (currentPkg.fullPackageName == packageName) {
        return Some(currentPkg)
    }
    for (pkg in sourcePackages) {
        if (pkg.fullPackageName == packageName) {
            return Some(pkg)
        }
    }
    return None
}

private func FindRealASTUniqueFunctionDecl(pkg: AstPackage, name: String): Option<AstFuncDecl> {
    var found: Option<AstFuncDecl> = None
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
                if (funcDecl.identifier.Val() == name) {
                    if (found.isSome()) {
                        return None
                    }
                    found = Some(funcDecl)
                }
            }
        }
    }
    return found
}

private func BuildRealASTFunctionInfo(body: AstFuncBody,
    packageScope: RealASTPackageLoweringScope): Option<RealASTFunctionInfo> {
    if (body.generic.isSome() || body.paramLists.size != 1) {
        return None
    }
    let returnType = match (RealASTFunctionReturnType(body, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let info = RealASTFunctionInfo(returnType)
    let paramList = body.paramLists[0]
    if (paramList.hasVariableLenArg) {
        return None
    }
    for (param in paramList.params) {
        if (param.assignment.isSome()) {
            return None
        }
        let typeNode = match (param.typeNode) {
            case Some(value) => value
            case None => return None
        }
        let paramType = match (RealASTValueTypeKey(typeNode, packageScope: Some(packageScope))) {
            case Some(value) => value
            case None => return None
        }
        info.paramKinds.add(RealASTKindFromTypeKey(paramType))
        info.paramTypes.add(paramType)
    }
    return Some(info)
}

private func BuildRealASTMethodFunctionInfo(body: AstFuncBody,
    packageScope: RealASTPackageLoweringScope): Option<RealASTFunctionInfo> {
    return BuildRealASTFunctionInfo(body, packageScope)
}

private func RealASTFunctionReturnType(body: AstFuncBody,
    packageScope: RealASTPackageLoweringScope): Option<String> {
    if (let Some(retType) <- body.retType) {
        return RealASTReturnTypeKey(retType, packageScope)
    }
    if (RealASTBodyHasValueReturn(body)) {
        return None
    }
    return Some(REAL_AST_TYPE_UNIT)
}

private func RealASTBodyHasValueReturn(body: AstFuncBody): Bool {
    if (let Some(block) <- body.body) {
        return RealASTBlockHasValueReturn(block)
    }
    return false
}

private func RealASTBlockHasValueReturn(block: AstBlock): Bool {
    for (node in block.body) {
        if (RealASTNodeHasValueReturn(node)) {
            return true
        }
    }
    return false
}

private func RealASTNodeHasValueReturn(node: AstNode): Bool {
    if (let Some(ret) <- (node as AstReturnExpr)) {
        return ret.expr.isSome()
    }
    if (let Some(ifExpr) <- (node as AstIfExpr)) {
        if (let Some(thenBlock) <- ifExpr.thenBody) {
            if (RealASTBlockHasValueReturn(thenBlock)) {
                return true
            }
        }
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseBlock) <- (elseExpr as AstBlock)) {
                return RealASTBlockHasValueReturn(elseBlock)
            }
            if (RealASTNodeHasValueReturn(elseExpr)) {
                return true
            }
        }
    }
    if (let Some(whileExpr) <- (node as AstWhileExpr)) {
        if (let Some(bodyBlock) <- whileExpr.body) {
            return RealASTBlockHasValueReturn(bodyBlock)
        }
    }
    return false
}

private func AnalyzeRealASTEnumHeader(enumDecl: AstEnumDecl): Option<RealASTEnumInfo> {
    let name = enumDecl.identifier.Val()
    if (name.isEmpty() || enumDecl.generic.isSome() || !enumDecl.inheritedTypes.isEmpty() ||
        enumDecl.hasEllipsis || !enumDecl.members.isEmpty()) {
        return None
    }
    return Some(RealASTEnumInfo(name, enumDecl))
}

private func AnalyzeRealASTEnumConstructors(enumDecl: AstEnumDecl,
    packageScope: RealASTPackageLoweringScope): Bool {
    let enumName = enumDecl.identifier.Val()
    let info = match (packageScope.GetEnum(enumName)) {
        case Some(value) => value
        case None => return false
    }
    var tag: Int64 = 0
    for (ctorDecl in enumDecl.constructors) {
        let ctorName = ctorDecl.identifier.Val()
        if (ctorName.isEmpty()) {
            return false
        }
        let ctorInfo = RealASTEnumCtorInfo(ctorName, ctorDecl, enumName, tag)
        if ((ctorDecl as AstVarDecl).isSome()) {
            // Payload-less constructor.
        } else if (let Some(funcCtor) <- (ctorDecl as AstFuncDecl)) {
            let body = match (funcCtor.funcBody) {
                case Some(value) => value
                case None => return false
            }
            if (body.generic.isSome() || body.paramLists.size != 1 || body.retType.isSome()) {
                return false
            }
            let paramList = body.paramLists[0]
            if (paramList.hasVariableLenArg) {
                return false
            }
            for (param in paramList.params) {
                if (param.assignment.isSome()) {
                    return false
                }
                let typeNode = match (param.typeNode) {
                    case Some(value) => value
                    case None => return false
                }
                let payloadType = match (RealASTValueTypeKey(typeNode, packageScope: Some(packageScope))) {
                    case Some(value) => value
                    case None => return false
                }
                ctorInfo.AddPayload(payloadType)
            }
        } else {
            return false
        }
        if (!info.AddCtor(ctorInfo) || !packageScope.AddEnumCtor(ctorInfo)) {
            return false
        }
        tag++
    }
    return !info.ctorNames.isEmpty()
}

private func AnalyzeRealASTStruct(structDecl: AstStructDecl,
    packageScope: RealASTPackageLoweringScope): Option<RealASTStructInfo> {
    let name = structDecl.identifier.Val()
    if (name.isEmpty() || structDecl.generic.isSome() || !structDecl.inheritedTypes.isEmpty()) {
        return None
    }
    let body = match (structDecl.body) {
        case Some(value) => value
        case None => return None
    }
    let info = RealASTStructInfo(name, structDecl)
    var initCount: Int64 = 0
    let methodDecls = ArrayList<AstFuncDecl>()
    for (member in body.decls) {
        if (let Some(fieldDecl) <- (member as AstVarDecl)) {
            if (fieldDecl.isConst || fieldDecl.initializer.isSome()) {
                return None
            }
            let typeNode = match (fieldDecl.typeNode) {
                case Some(value) => value
                case None => return None
            }
            let fieldType = match (RealASTPrimitiveFieldTypeKey(typeNode)) {
                case Some(value) => value
                case None => return None
            }
            if (!info.AddField(fieldDecl.identifier.Val(), fieldType, fieldDecl.isVar)) {
                return None
            }
            continue
        }
        if (let Some(funcDecl) <- (member as AstFuncDecl)) {
            let body = match (funcDecl.funcBody) {
                case Some(value) => value
                case None => return None
            }
            if (funcDecl.TestAttr(AstAttribute.CONSTRUCTOR) || funcDecl.identifier.Val() == "init") {
                initCount++
                if (initCount != 1) {
                    return None
                }
                if (!AnalyzeRealASTStructInit(info, body, packageScope)) {
                    return None
                }
            } else {
                methodDecls.add(funcDecl)
            }
            continue
        }
        return None
    }
    if (initCount != 1 || info.fieldNames.isEmpty()) {
        return None
    }
    for (methodDecl in methodDecls) {
        let methodBody = match (methodDecl.funcBody) {
            case Some(value) => value
            case None => return None
        }
        let methodInfo = match (BuildRealASTMethodFunctionInfo(methodBody, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let methodName = methodDecl.identifier.Val()
        let loweredName = RealASTStructMethodName(info.name, methodName)
        if (!info.AddMethod(RealASTMethodInfo(methodName, loweredName, methodDecl, methodInfo))) {
            return None
        }
    }
    return Some(info)
}

private func AnalyzeRealASTStructInit(info: RealASTStructInfo, body: AstFuncBody,
    packageScope: RealASTPackageLoweringScope): Bool {
    if (body.generic.isSome() || body.paramLists.size != 1 || body.retType.isSome()) {
        return false
    }
    let paramList = body.paramLists[0]
    if (paramList.hasVariableLenArg) {
        return false
    }
    for (param in paramList.params) {
        if (param.assignment.isSome()) {
            return false
        }
        let typeNode = match (param.typeNode) {
            case Some(value) => value
            case None => return false
        }
        let paramType = match (RealASTValueTypeKey(typeNode, packageScope: Some(packageScope))) {
            case Some(value) => value
            case None => return false
        }
        info.initParams.add(param.identifier.Val())
        info.initParamTypes.add(paramType)
    }
    let block = match (body.body) {
        case Some(value) => value
        case None => return false
    }
    let assigned = HashSet<String>()
    for (node in block.body) {
        let assign = match (node as AstAssignExpr) {
            case Some(value) => value
            case None => return false
        }
        if (assign.op != AstTokenKind.ASSIGN) {
            return false
        }
        let left = match (assign.leftValue) {
            case Some(value) => value
            case None => return false
        }
        let fieldName = match (RealASTFieldNameFromThisTarget(left)) {
            case Some(value) => value
            case None => return false
        }
        if (assigned.contains(fieldName) || info.FieldType(fieldName).isNone()) {
            return false
        }
        let rhs = match (assign.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        info.initAssigns.add(RealASTStructInitAssign(fieldName, rhs))
        assigned.add(fieldName)
    }
    return assigned.size == info.fieldNames.size
}

private func BuildRealASTEnumSpec(packageName: String, enumDecl: AstEnumDecl, context: CHIRContext,
    sourceFileKey: String, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRNominalSpec> {
    let info = match (packageScope.GetEnum(enumDecl.identifier.Val())) {
        case Some(value) => value
        case None => return None
    }
    let spec = AST2CHIRNominalSpec(AST2CHIRNominalKind.ENUM, info.name, packageName: packageName,
        srcCodeIdentifier: info.name, rawMangledName: RealASTStableMangledName(packageName, enumDecl))
    spec.SetSourceFileKey(sourceFileKey)
    if (enumDecl.IsExportedDecl()) {
        spec.AddAttribute(Attribute.PUBLIC)
    } else {
        spec.AddAttribute(Attribute.PRIVATE)
    }
    for (ctorName in info.ctorNames) {
        let ctorInfo = match (info.GetCtor(ctorName)) {
            case Some(value) => value
            case None => return None
        }
        let payloadTys = ArrayList<Type>()
        for (payloadType in ctorInfo.payloadTypes) {
            let chirTy = match (RealASTCHIRTypeForKey(context, payloadType)) {
                case Some(value) => value
                case None => return None
            }
            payloadTys.add(chirTy)
        }
        spec.AddEnumCtor(AST2CHIREnumCtorSpec(ctorName, payloadTypes: payloadTys))
    }
    return Some(spec)
}

private func BuildRealASTStructSpec(packageName: String, structDecl: AstStructDecl, context: CHIRContext,
    sourceFileKey: String, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRNominalSpec> {
    let info = match (packageScope.GetStruct(structDecl.identifier.Val())) {
        case Some(value) => value
        case None => return None
    }
    let spec = AST2CHIRNominalSpec(AST2CHIRNominalKind.STRUCT, info.name, packageName: packageName,
        srcCodeIdentifier: info.name, rawMangledName: RealASTStableMangledName(packageName, structDecl))
    spec.SetSourceFileKey(sourceFileKey)
    if (structDecl.IsExportedDecl()) {
        spec.AddAttribute(Attribute.PUBLIC)
    } else {
        spec.AddAttribute(Attribute.PRIVATE)
    }
    for (fieldName in info.fieldNames) {
        let fieldTypeKey = match (info.FieldType(fieldName)) {
            case Some(value) => value
            case None => return None
        }
        let fieldTy = match (RealASTCHIRTypeForKey(context, fieldTypeKey)) {
            case Some(value) => value
            case None => return None
        }
        let memberSpec = AST2CHIRMemberVarSpec(fieldName, fieldTy, rawMangledName: fieldName,
            isReadOnly: !(info.FieldCanWrite(fieldName)))
        memberSpec.SetSourceFileKey(sourceFileKey)
        spec.AddInstanceVar(memberSpec)
    }
    return Some(spec)
}

private func BuildRealASTStructMethodSpec(packageName: String, structInfo: RealASTStructInfo,
    methodInfo: RealASTMethodInfo, context: CHIRContext, sourceFileKey: String,
    packageScope: RealASTPackageLoweringScope): Option<AST2CHIRFunctionSpec> {
    let body = match (methodInfo.funcDecl.funcBody) {
        case Some(value) => value
        case None => return None
    }
    let params = match (BuildRealASTParamLowering(context, body, packageScope, allowParams: true)) {
        case Some(value) => value
        case None => return None
    }
    params.types.add(context.GetInt64Ty(), at: 0)
    params.names.add("this", at: 0)
    let lowered = LowerRealASTBody(body, packageScope, thisStructName: structInfo.name)
    if (!lowered.ok) {
        return None
    }
    let returnTy = match (RealASTReturnType(context, body, lowered, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let fnSpec = AST2CHIRFunctionSpec(methodInfo.loweredName, params.types, returnTy,
        srcCodeIdentifier: methodInfo.loweredName, rawMangledName: methodInfo.loweredName,
        packageName: packageName, funcKind: FuncKind.DEFAULT, emitBody: true)
    fnSpec.EnableRealBody()
    for (name in params.names) {
        fnSpec.AddParamName(name)
    }
    for (stmt in lowered.stmts) {
        fnSpec.AddBodyStatement(stmt)
    }
    if (methodInfo.funcDecl.IsExportedDecl()) {
        fnSpec.AddAttribute(Attribute.PUBLIC)
    } else {
        fnSpec.AddAttribute(Attribute.PRIVATE)
    }
    if (!sourceFileKey.isEmpty()) {
        fnSpec.SetSourceFileKey(sourceFileKey)
    }
    return Some(fnSpec)
}

private func BuildRealASTImportedFunctionSpec(imported: RealASTImportedFunctionInfo,
    context: CHIRContext): Option<AST2CHIRFunctionSpec> {
    let paramTypes = ArrayList<Type>()
    for (paramType in imported.funcInfo.paramTypes) {
        let chirTy = match (RealASTCHIRTypeForKey(context, paramType)) {
            case Some(value) => value
            case None => return None
        }
        paramTypes.add(chirTy)
    }
    let returnTy = match (RealASTCHIRTypeForKey(context, imported.funcInfo.returnType)) {
        case Some(value) => value
        case None => return None
    }
    let fnSpec = AST2CHIRFunctionSpec(imported.chirName, paramTypes, returnTy,
        srcCodeIdentifier: imported.localName, rawMangledName: imported.chirName,
        packageName: imported.packageName, funcKind: FuncKind.DEFAULT, emitBody: false)
    fnSpec.AddAttribute(Attribute.IMPORTED)
    fnSpec.AddAttribute(Attribute.PUBLIC)
    return Some(fnSpec)
}

private func BuildRealASTFunctionSpec(
    packageName: String,
    decl: AstDecl,
    context: CHIRContext,
    sourceFileKey: String,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRFunctionSpec> {
    let isMain = (decl as AstMainDecl).isSome()
    if (!isMain && (decl as AstFuncDecl).isNone()) {
        return None
    }
    let body = match (GetRealASTFuncBody(decl)) {
        case Some(value) => value
        case None => return None
    }
    let params = match (BuildRealASTParamLowering(context, body, packageScope, allowParams: !isMain)) {
        case Some(value) => value
        case None => return None
    }
    let lowered = LowerRealASTBody(body, packageScope)
    if (!lowered.ok) {
        return None
    }
    let returnTy = match (RealASTReturnType(context, body, lowered, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let fnName = if (isMain) { "user.main" } else { RealASTStableMangledName(packageName, decl) }
    let srcName = if (decl.identifier.Empty()) {
        if (isMain) { "main" } else { fnName }
    } else {
        decl.identifier.Val()
    }
    let kind = if (isMain) { FuncKind.MAIN_ENTRY } else { FuncKind.DEFAULT }
    let fnSpec = AST2CHIRFunctionSpec(fnName, params.types, returnTy, srcCodeIdentifier: srcName,
        rawMangledName: fnName, packageName: packageName, funcKind: kind, emitBody: true)
    fnSpec.EnableRealBody()
    for (name in params.names) {
        fnSpec.AddParamName(name)
    }
    for (stmt in lowered.stmts) {
        fnSpec.AddBodyStatement(stmt)
    }
    if (decl.IsExportedDecl()) {
        fnSpec.AddAttribute(Attribute.PUBLIC)
    } else {
        fnSpec.AddAttribute(Attribute.PRIVATE)
    }
    if (!sourceFileKey.isEmpty()) {
        fnSpec.SetSourceFileKey(sourceFileKey)
    }
    return Some(fnSpec)
}

private func GetRealASTFuncBody(decl: AstDecl): Option<AstFuncBody> {
    if (let Some(funcDecl) <- (decl as AstFuncDecl)) {
        return funcDecl.funcBody
    }
    if (let Some(mainDecl) <- (decl as AstMainDecl)) {
        return mainDecl.funcBody
    }
    return None
}

private func BuildRealASTParamLowering(
    context: CHIRContext,
    body: AstFuncBody,
    packageScope: RealASTPackageLoweringScope,
    allowParams!: Bool = true
): Option<RealASTParamLowering> {
    if (body.generic.isSome()) {
        return None
    }
    if (body.paramLists.size != 1) {
        return None
    }
    let paramList = body.paramLists[0]
    if (paramList.hasVariableLenArg) {
        return None
    }
    if (!allowParams && !paramList.params.isEmpty()) {
        return None
    }
    let out = RealASTParamLowering()
    for (param in paramList.params) {
        if (param.assignment.isSome()) {
            return None
        }
        let paramTy = match (param.typeNode) {
            case Some(typeNode) =>
                match (RealASTParamType(context, typeNode, packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
            case None => return None
        }
        out.types.add(paramTy)
        out.names.add(param.identifier.Val())
    }
    return Some(out)
}

private func LowerRealASTBody(body: AstFuncBody, packageScope: RealASTPackageLoweringScope,
    thisStructName!: String = ""): RealASTBodyLowering {
    let empty = ArrayList<AST2CHIRStmtSpec>()
    let block = match (body.body) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, empty, REAL_AST_RETURN_NONE)
    }
    let stmts = ArrayList<AST2CHIRStmtSpec>()
    if (block.body.isEmpty()) {
        return RealASTBodyLowering(true, stmts, REAL_AST_RETURN_NONE)
    }
    let scope = RealASTLoweringScope(body, packageScope: Some(packageScope), thisStructName: thisStructName)
    let lowered = match (LowerRealASTBlock(block, scope, packageScope, scoped: false)) {
        case Some(value) => value
        case None => return RealASTBodyLowering(false, empty, REAL_AST_RETURN_NONE)
    }
    return lowered
}

private func LowerRealASTBlock(
    block: AstBlock,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope,
    scoped!: Bool = true
): Option<RealASTBodyLowering> {
    let snapshot: Option<RealASTScopeSnapshot> = if (scoped) { Some(scope.Save()) } else { None }
    let stmts = ArrayList<AST2CHIRStmtSpec>()
    var returnType = REAL_AST_TYPE_NONE
    for (node in block.body) {
        let lowered = match (LowerRealASTBodyNode(node, scope, packageScope)) {
            case Some(value) => value
            case None =>
                if (let Some(value) <- snapshot) {
                    scope.Restore(value)
                }
                return None
        }
        stmts.add(lowered.stmt)
        if (!lowered.returnType.isEmpty()) {
            returnType = lowered.returnType
        }
    }
    if (let Some(value) <- snapshot) {
        scope.Restore(value)
    }
    return Some(RealASTBodyLowering(true, stmts, returnType))
}

private func LowerRealASTBodyNode(
    node: AstNode,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (let Some(varDecl) <- (node as AstVarDecl)) {
        return LowerRealASTVarDecl(varDecl, scope, packageScope)
    }
    if (let Some(assign) <- (node as AstAssignExpr)) {
        return LowerRealASTAssign(assign, scope, packageScope)
    }
    if (let Some(ret) <- (node as AstReturnExpr)) {
        return LowerRealASTReturn(ret, scope, packageScope)
    }
    if (let Some(ifExpr) <- (node as AstIfExpr)) {
        return LowerRealASTIf(ifExpr, scope, packageScope)
    }
    if (let Some(whileExpr) <- (node as AstWhileExpr)) {
        return LowerRealASTWhile(whileExpr, scope, packageScope)
    }
    if (let Some(jumpExpr) <- (node as AstJumpExpr)) {
        return LowerRealASTJump(jumpExpr, scope)
    }
    if (let Some(matchExpr) <- (node as AstMatchExpr)) {
        let matchType = match (RealASTMatchExprValueType(matchExpr, scope, packageScope)) {
            case Some(value) => value
            case None => REAL_AST_TYPE_UNIT
        }
        let selectorSpec = match (LowerRealASTMatchSelector(matchExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let mode = if (matchType == REAL_AST_TYPE_UNIT) {
            REAL_AST_MATCH_BODY_STMT
        } else {
            REAL_AST_MATCH_BODY_RETURN
        }
        let cases = match (LowerRealASTMatchCases(matchExpr, scope, packageScope, mode)) {
            case Some(value) => value
            case None => return None
        }
        return Some(RealASTStmtAndType(AST2CHIRStmtSpec.Match(selectorSpec, cases), matchType))
    }
    if (let Some(call) <- (node as AstCallExpr)) {
        if (let Some(printStmt) <- LowerRealASTPrint(call, scope, packageScope)) {
            return Some(printStmt)
        }
        let callSpec = match (LowerRealASTCall(call, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ExprStmt(callSpec), REAL_AST_RETURN_NONE))
    }
    return None
}

private func RealASTStmtAndKind(stmt: AST2CHIRStmtSpec, kind: Int64): RealASTStmtLowering {
    return RealASTStmtLowering(stmt, kind)
}

private func RealASTStmtAndType(stmt: AST2CHIRStmtSpec, typeKey: String): RealASTStmtLowering {
    return RealASTStmtLowering(stmt, typeKey)
}

private func LowerRealASTVarDecl(
    varDecl: AstVarDecl,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (varDecl.isConst) {
        return None
    }
    var declaredType: Option<String> = None
    if (let Some(typeNode) <- varDecl.typeNode) {
        declaredType = match (RealASTLocalTypeKey(typeNode, packageScope)) {
            case Some(kind) => Some(kind)
            case None => return None
        }
    }
    let name = varDecl.identifier.Val()
    if (name.isEmpty() || scope.Contains(name)) {
        return None
    }
    let initExpr = match (varDecl.initializer) {
        case Some(value) => value
        case None => return None
    }
    let initType = match (RealASTExprValueType(initExpr, scope, packageScope)) {
        case Some(kind) => kind
        case None => return None
    }
    if (let Some(targetType) <- declaredType) {
        if (targetType != initType) {
            return None
        }
    }
    if (let Some(matchInit) <- (initExpr as AstMatchExpr)) {
        let selectorSpec = match (LowerRealASTMatchSelector(matchInit, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let cases = match (LowerRealASTMatchCases(matchInit, scope, packageScope,
            REAL_AST_MATCH_BODY_ASSIGN, resultName: name)) {
            case Some(value) => value
            case None => return None
        }
        if (!scope.Add(name, varDecl.isVar, initType)) {
            return None
        }
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.MatchLet(name, initType, selectorSpec, cases,
            isVar: varDecl.isVar), REAL_AST_RETURN_NONE))
    }
    let exprSpec = match (LowerRealASTExpr(initExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (!scope.Add(name, varDecl.isVar, initType)) {
        return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Let(name, exprSpec, isVar: varDecl.isVar),
        REAL_AST_RETURN_NONE))
}

private func LowerRealASTAssign(
    assign: AstAssignExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (assign.op != AstTokenKind.ASSIGN) {
        return None
    }
    let left = match (assign.leftValue) {
        case Some(value) => value
        case None => return None
    }
    if (let Some(member) <- (left as AstMemberAccess)) {
        return LowerRealASTFieldAssign(member, assign, scope, packageScope)
    }
    let ref = match (left as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    let name = ref.ref.identifier.Val()
    if (!scope.Contains(name)) {
        if (let Some(stmt) <- LowerRealASTImplicitThisFieldAssign(name, assign, scope, packageScope)) {
            return Some(stmt)
        }
        return None
    }
    if (name.isEmpty() || !scope.Contains(name) || !scope.CanAssign(name)) {
        return None
    }
    let right = match (assign.rightExpr) {
        case Some(value) => value
        case None => return None
    }
    let rightType = match (RealASTExprValueType(right, scope, packageScope)) {
        case Some(kind) => kind
        case None => return None
    }
    if (let Some(localType) <- scope.TypeKey(name)) {
        if (localType != rightType) {
            return None
        }
    }
    let exprSpec = match (LowerRealASTExpr(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Assign(name, exprSpec), REAL_AST_RETURN_NONE))
}

private func LowerRealASTFieldAssign(member: AstMemberAccess, assign: AstAssignExpr,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<RealASTStmtLowering> {
    if (!member.typeArguments.isEmpty()) {
        return None
    }
    let base = match (member.baseExpr) {
        case Some(value) => value
        case None => return None
    }
    let baseRef = match (base as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    let localName = baseRef.ref.identifier.Val()
    let baseType = match (scope.TypeKey(localName)) {
        case Some(value) => value
        case None => return None
    }
    let structName = match (RealASTStructNameFromTypeKey(baseType)) {
        case Some(value) => value
        case None => return None
    }
    let structInfo = match (packageScope.GetStruct(structName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldName = member.field.GetRawText()
    if (!structInfo.FieldCanWrite(fieldName)) {
        return None
    }
    let fieldType = match (structInfo.FieldType(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldIndex = match (structInfo.FieldIndex(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let right = match (assign.rightExpr) {
        case Some(value) => value
        case None => return None
    }
    let rightType = match (RealASTExprValueType(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (rightType != fieldType) {
        return None
    }
    let exprSpec = match (LowerRealASTExpr(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.StructSetField(localName, fieldIndex + 1, exprSpec),
        REAL_AST_RETURN_NONE))
}

private func LowerRealASTImplicitThisFieldAssign(fieldName: String, assign: AstAssignExpr,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<RealASTStmtLowering> {
    if (scope.thisStructName.isEmpty()) {
        return None
    }
    let structInfo = match (packageScope.GetStruct(scope.thisStructName)) {
        case Some(value) => value
        case None => return None
    }
    if (!structInfo.FieldCanWrite(fieldName)) {
        return None
    }
    let fieldType = match (structInfo.FieldType(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldIndex = match (structInfo.FieldIndex(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let right = match (assign.rightExpr) {
        case Some(value) => value
        case None => return None
    }
    let rightType = match (RealASTExprValueType(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (rightType != fieldType) {
        return None
    }
    let exprSpec = match (LowerRealASTExpr(right, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.StructSetField("this", fieldIndex + 1, exprSpec),
        REAL_AST_RETURN_NONE))
}

private func LowerRealASTReturn(
    ret: AstReturnExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    if (let Some(expr) <- ret.expr) {
        if (let Some(matchExpr) <- (expr as AstMatchExpr)) {
            let matchType = match (RealASTMatchExprValueType(matchExpr, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            let selectorSpec = match (LowerRealASTMatchSelector(matchExpr, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            let cases = match (LowerRealASTMatchCases(matchExpr, scope, packageScope,
                REAL_AST_MATCH_BODY_RETURN)) {
                case Some(value) => value
                case None => return None
            }
            return Some(RealASTStmtAndType(AST2CHIRStmtSpec.Match(selectorSpec, cases), matchType))
        }
        if (let Some(lit) <- (expr as AstLitConstExpr)) {
            if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(AST2CHIRExprSpec.Literal(value)),
                    REAL_AST_RETURN_INT))
            }
            if (let Some(value) <- ParseRealASTBoolLiteral(lit)) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Return(AST2CHIRExprSpec.BoolLit(value)),
                    REAL_AST_RETURN_BOOL))
            }
            if (lit.kind == AstLitConstKind.UNIT) {
                return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ReturnNone(), REAL_AST_RETURN_UNIT))
            }
        }
        let exprType = match (RealASTExprValueType(expr, scope, packageScope)) {
            case Some(kind) => kind
            case None => return None
        }
        let exprSpec = match (LowerRealASTExpr(expr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(RealASTStmtAndType(AST2CHIRStmtSpec.Return(exprSpec), exprType))
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.ReturnNone(), REAL_AST_RETURN_UNIT))
}

private func LowerRealASTIf(
    ifExpr: AstIfExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let condExpr = match (ifExpr.condExpr) {
        case Some(value) => value
        case None => return None
    }
    let condType = match (RealASTExprValueType(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (condType != REAL_AST_TYPE_BOOL) {
        return None
    }
    let condSpec = match (LowerRealASTExpr(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let thenBlock = match (ifExpr.thenBody) {
        case Some(value) => value
        case None => return None
    }
    let thenLowering = match (LowerRealASTBlock(thenBlock, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let elseStmts = ArrayList<AST2CHIRStmtSpec>()
    var elseKind = REAL_AST_RETURN_NONE
    if (let Some(elseExpr) <- ifExpr.elseBody) {
        if (let Some(elseBlock) <- (elseExpr as AstBlock)) {
            let elseLowering = match (LowerRealASTBlock(elseBlock, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            for (stmt in elseLowering.stmts) {
                elseStmts.add(stmt)
            }
            elseKind = elseLowering.returnKind
        } else if (let Some(elseIf) <- (elseExpr as AstIfExpr)) {
            let elseIfLowering = match (LowerRealASTIf(elseIf, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            elseStmts.add(elseIfLowering.stmt)
            elseKind = elseIfLowering.returnKind
        } else {
            return None
        }
    }
    let returnType = if (elseKind != REAL_AST_RETURN_NONE) {
        RealASTTypeKeyFromKind(elseKind)
    } else {
        thenLowering.returnType
    }
    return Some(RealASTStmtAndType(AST2CHIRStmtSpec.If(condSpec, thenLowering.stmts, elseStmts), returnType))
}

private func LowerRealASTWhile(
    whileExpr: AstWhileExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let condExpr = match (whileExpr.condExpr) {
        case Some(value) => value
        case None => return None
    }
    let condType = match (RealASTExprValueType(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (condType != REAL_AST_TYPE_BOOL) {
        return None
    }
    let condSpec = match (LowerRealASTExpr(condExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let bodyBlock = match (whileExpr.body) {
        case Some(value) => value
        case None => return None
    }
    scope.EnterLoop()
    let bodyLowering = match (LowerRealASTBlock(bodyBlock, scope, packageScope)) {
        case Some(value) => value
        case None =>
            scope.ExitLoop()
            return None
    }
    scope.ExitLoop()
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.While(condSpec, bodyLowering.stmts),
        bodyLowering.returnKind))
}

private func LowerRealASTJump(jumpExpr: AstJumpExpr, scope: RealASTLoweringScope): Option<RealASTStmtLowering> {
    if (!scope.InLoop()) {
        return None
    }
    let stmt = if (jumpExpr.isBreak) {
        AST2CHIRStmtSpec.Break()
    } else {
        AST2CHIRStmtSpec.Continue()
    }
    return Some(RealASTStmtAndKind(stmt, REAL_AST_RETURN_NONE))
}

private func LowerRealASTPrint(
    call: AstCallExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<RealASTStmtLowering> {
    let base = match (call.baseFunc) {
        case Some(value) => value
        case None => return None
    }
    let calleeRef = match (base as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.ref.identifier.Val()
    if (calleeName != "println" && calleeName != "print") {
        return None
    }
    if (scope.Contains(calleeName) || call.args.size != 1) {
        return None
    }
    let arg = call.args[0]
    if (!arg.name.Empty() || arg.withInout) {
        return None
    }
    let argExpr = match (arg.expr) {
        case Some(value) => value
        case None => return None
    }
    let newline = calleeName == "println"
    if (let Some(text) <- PlainRealASTStringLiteralValue(argExpr)) {
        return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.PrintStr(text, newline: newline),
            REAL_AST_RETURN_NONE))
    }
    let typeKey = match (RealASTExprValueType(argExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    if (typeKey != REAL_AST_TYPE_INT && typeKey != REAL_AST_TYPE_BOOL && typeKey != REAL_AST_TYPE_STRING) {
        return None
    }
    let exprSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(RealASTStmtAndKind(AST2CHIRStmtSpec.Print(exprSpec, newline: newline), REAL_AST_RETURN_NONE))
}

private func LowerRealASTExpr(
    expr: AstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRExprSpec> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return LowerRealASTExpr(inner, scope, packageScope)
        }
        return None
    }
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
            return Some(AST2CHIRExprSpec.Literal(value))
        }
        if (let Some(value) <- ParseRealASTBoolLiteral(lit)) {
            return Some(AST2CHIRExprSpec.BoolLit(value))
        }
        if (let Some(text) <- PlainRealASTStringLiteralValue(lit)) {
            return Some(AST2CHIRExprSpec.StrLit(text))
        }
        if (lit.kind == AstLitConstKind.STRING && lit.siExpr.isSome()) {
            return LowerRealASTInterpolation(lit, scope, packageScope)
        }
        return None
    }
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        let name = refExpr.ref.identifier.Val()
        if (!name.isEmpty() && scope.Contains(name)) {
            return Some(AST2CHIRExprSpec.Ref(name))
        }
        if (let Some(ctorInfo) <- packageScope.GetEnumCtor(name)) {
            if (ctorInfo.payloadTypes.isEmpty()) {
                return Some(AST2CHIRExprSpec.EnumMake(ctorInfo.tag, ArrayList<AST2CHIRExprSpec>()))
            }
        }
        if (let Some(spec) <- LowerRealASTImplicitThisFieldRead(name, scope, packageScope)) {
            return Some(spec)
        }
        return None
    }
    if (let Some(member) <- (expr as AstMemberAccess)) {
        return LowerRealASTFieldRead(member, scope, packageScope)
    }
    if (let Some(binary) <- (expr as AstBinaryExpr)) {
        if (RealASTExprValueKind(binary, scope, packageScope).isNone()) {
            return None
        }
        let op = match (RealASTBinaryOp(binary.op)) {
            case Some(value) => value
            case None => return None
        }
        let lhs = match (binary.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let rhs = match (binary.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let lhsSpec = match (LowerRealASTExpr(lhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsSpec = match (LowerRealASTExpr(rhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Binary(op, lhsSpec, rhsSpec))
    }
    if (let Some(unary) <- (expr as AstUnaryExpr)) {
        let op = match (RealASTUnaryOp(unary.op)) {
            case Some(value) => value
            case None => return None
        }
        let operand = match (unary.expr) {
            case Some(value) => value
            case None => return None
        }
        let operandSpec = match (LowerRealASTExpr(operand, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Unary(op, operandSpec))
    }
    if (let Some(call) <- (expr as AstCallExpr)) {
        return LowerRealASTCall(call, scope, packageScope)
    }
    return None
}

private func LowerRealASTCall(
    call: AstCallExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRExprSpec> {
    let base = match (call.baseFunc) {
        case Some(value) => value
        case None => return None
    }
    if (let Some(member) <- (base as AstMemberAccess)) {
        return LowerRealASTMethodCall(call, member, scope, packageScope)
    }
    let calleeRef = match (base as AstRefExpr) {
        case Some(value) => value
        case None => return None
    }
    if (!calleeRef.typeArguments.isEmpty()) {
        return None
    }
    let calleeName = calleeRef.ref.identifier.Val()
    if (calleeName.isEmpty() || scope.Contains(calleeName)) {
        return None
    }
    if (packageScope.IsStruct(calleeName)) {
        return LowerRealASTStructConstruction(calleeName, call, scope, packageScope)
    }
    if (let Some(ctorInfo) <- packageScope.GetEnumCtor(calleeName)) {
        return LowerRealASTEnumConstruction(ctorInfo, call, scope, packageScope)
    }
    let info = match (packageScope.GetFunction(calleeName)) {
        case Some(value) => value
        case None => return None
    }
    if (info.returnType == REAL_AST_TYPE_UNIT || info.returnType == REAL_AST_TYPE_NONE) {
        return None
    }
    if (call.args.size != info.paramTypes.size) {
        return None
    }
    let argSpecs = ArrayList<AST2CHIRExprSpec>()
    var idx: Int64 = 0
    while (idx < call.args.size) {
        let arg = call.args[idx]
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return None
        }
        let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (argType != info.paramTypes[idx]) {
            return None
        }
        let argSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        argSpecs.add(argSpec)
        idx++
    }
    return Some(AST2CHIRExprSpec.Call(calleeName, argSpecs))
}

private func LowerRealASTEnumConstruction(ctorInfo: RealASTEnumCtorInfo, call: AstCallExpr,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    if (call.args.size != ctorInfo.payloadTypes.size) {
        return None
    }
    let fields = ArrayList<AST2CHIRExprSpec>()
    var idx: Int64 = 0
    while (idx < call.args.size) {
        let arg = call.args[idx]
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return None
        }
        let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (argType != ctorInfo.payloadTypes[idx]) {
            return None
        }
        let argSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        fields.add(argSpec)
        idx++
    }
    return Some(AST2CHIRExprSpec.EnumMake(ctorInfo.tag, fields))
}

private func LowerRealASTStructConstruction(structName: String, call: AstCallExpr,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    let info = match (packageScope.GetStruct(structName)) {
        case Some(value) => value
        case None => return None
    }
    if (call.args.size != info.initParams.size) {
        return None
    }
    let argMap = HashMap<String, AST2CHIRExprSpec>()
    var idx: Int64 = 0
    while (idx < call.args.size) {
        let arg = call.args[idx]
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return None
        }
        let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (argType != info.initParamTypes[idx]) {
            return None
        }
        let argSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        argMap[info.initParams[idx]] = argSpec
        idx++
    }
    let initByField = HashMap<String, AstExpr>()
    for (assign in info.initAssigns) {
        initByField[assign.fieldName] = assign.rhs
    }
    let fields = ArrayList<AST2CHIRExprSpec>()
    for (fieldName in info.fieldNames) {
        let rhs = match (initByField.get(fieldName)) {
            case Some(value) => value
            case None => return None
        }
        let fieldSpec = match (LowerRealASTInitRhs(rhs, argMap, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        fields.add(fieldSpec)
    }
    return Some(AST2CHIRExprSpec.EnumMake(0, fields))
}

private func LowerRealASTMethodCall(call: AstCallExpr, member: AstMemberAccess,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    if (!member.typeArguments.isEmpty()) {
        return None
    }
    let receiverExpr = match (member.baseExpr) {
        case Some(value) => value
        case None => return None
    }
    let receiverType = match (RealASTExprValueType(receiverExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let structName = match (RealASTStructNameFromTypeKey(receiverType)) {
        case Some(value) => value
        case None => return None
    }
    let structInfo = match (packageScope.GetStruct(structName)) {
        case Some(value) => value
        case None => return None
    }
    let method = match (structInfo.GetMethod(member.field.GetRawText())) {
        case Some(value) => value
        case None => return None
    }
    if (call.args.size != method.funcInfo.paramTypes.size) {
        return None
    }
    let argSpecs = ArrayList<AST2CHIRExprSpec>()
    let receiverSpec = match (LowerRealASTExpr(receiverExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    argSpecs.add(receiverSpec)
    var idx: Int64 = 0
    while (idx < call.args.size) {
        let arg = call.args[idx]
        if (!arg.name.Empty() || arg.withInout) {
            return None
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return None
        }
        let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (argType != method.funcInfo.paramTypes[idx]) {
            return None
        }
        let argSpec = match (LowerRealASTExpr(argExpr, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        argSpecs.add(argSpec)
        idx++
    }
    return Some(AST2CHIRExprSpec.Call(method.loweredName, argSpecs))
}

private func LowerRealASTFieldRead(member: AstMemberAccess, scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    if (!member.typeArguments.isEmpty()) {
        return None
    }
    let base = match (member.baseExpr) {
        case Some(value) => value
        case None => return None
    }
    let baseType = match (RealASTExprValueType(base, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let structName = match (RealASTStructNameFromTypeKey(baseType)) {
        case Some(value) => value
        case None => return None
    }
    let structInfo = match (packageScope.GetStruct(structName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldName = member.field.GetRawText()
    let fieldType = match (structInfo.FieldType(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldIndex = match (structInfo.FieldIndex(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let baseSpec = match (LowerRealASTExpr(base, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    return Some(AST2CHIRExprSpec.StructField(baseSpec, fieldIndex + 1, fieldType))
}

private func LowerRealASTImplicitThisFieldRead(fieldName: String, scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    if (scope.thisStructName.isEmpty()) {
        return None
    }
    let structInfo = match (packageScope.GetStruct(scope.thisStructName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldType = match (structInfo.FieldType(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    let fieldIndex = match (structInfo.FieldIndex(fieldName)) {
        case Some(value) => value
        case None => return None
    }
    return Some(AST2CHIRExprSpec.StructField(AST2CHIRExprSpec.Ref("this"), fieldIndex + 1, fieldType))
}

private func RealASTExprValueKind(
    expr: AstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<Int64> {
    if (let Some(typeKey) <- RealASTExprValueType(expr, scope, packageScope)) {
        return Some(RealASTKindFromTypeKey(typeKey))
    }
    return None
}

private func RealASTExprValueType(
    expr: AstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<String> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return RealASTExprValueType(inner, scope, packageScope)
        }
        return None
    }
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (ParseRealASTIntLiteral(lit).isSome()) {
            return Some(REAL_AST_TYPE_INT)
        }
        if (ParseRealASTBoolLiteral(lit).isSome()) {
            return Some(REAL_AST_TYPE_BOOL)
        }
        if (PlainRealASTStringLiteralValue(expr).isSome()) {
            return Some(REAL_AST_TYPE_STRING)
        }
        if (let Some(kind) <- RealASTInterpolationValueKind(lit, scope, packageScope)) {
            return Some(RealASTTypeKeyFromKind(kind))
        }
        if (lit.kind == AstLitConstKind.UNIT) {
            return Some(REAL_AST_TYPE_UNIT)
        }
        return None
    }
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        let name = refExpr.ref.identifier.Val()
        if (let Some(typeKey) <- scope.TypeKey(name)) {
            return Some(typeKey)
        }
        if (let Some(ctorInfo) <- packageScope.GetEnumCtor(name)) {
            if (ctorInfo.payloadTypes.isEmpty()) {
                return Some(RealASTEnumTypeKey(ctorInfo.ownerName))
            }
        }
        if (!scope.thisStructName.isEmpty()) {
            if (let Some(structInfo) <- packageScope.GetStruct(scope.thisStructName)) {
                return structInfo.FieldType(name)
            }
        }
        return None
    }
    if (let Some(member) <- (expr as AstMemberAccess)) {
        if (!member.typeArguments.isEmpty()) {
            return None
        }
        let base = match (member.baseExpr) {
            case Some(value) => value
            case None => return None
        }
        let baseType = match (RealASTExprValueType(base, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let structName = match (RealASTStructNameFromTypeKey(baseType)) {
            case Some(value) => value
            case None => return None
        }
        let structInfo = match (packageScope.GetStruct(structName)) {
            case Some(value) => value
            case None => return None
        }
        return structInfo.FieldType(member.field.GetRawText())
    }
    if (let Some(unary) <- (expr as AstUnaryExpr)) {
        let operand = match (unary.expr) {
            case Some(value) => value
            case None => return None
        }
        let operandType = match (RealASTExprValueType(operand, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (unary.op == AstTokenKind.SUB && operandType == REAL_AST_TYPE_INT) {
            return Some(REAL_AST_TYPE_INT)
        }
        if (unary.op == AstTokenKind.NOT && operandType == REAL_AST_TYPE_BOOL) {
            return Some(REAL_AST_TYPE_BOOL)
        }
        return None
    }
    if (let Some(binary) <- (expr as AstBinaryExpr)) {
        let lhs = match (binary.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let rhs = match (binary.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let lhsType = match (RealASTExprValueType(lhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsType = match (RealASTExprValueType(rhs, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        if (lhsType == REAL_AST_TYPE_STRING || rhsType == REAL_AST_TYPE_STRING) {
            if (binary.op == AstTokenKind.ADD && lhsType == REAL_AST_TYPE_STRING &&
                rhsType == REAL_AST_TYPE_STRING) {
                return Some(REAL_AST_TYPE_STRING)
            }
            return None
        }
        if (RealASTIsArithmeticOp(binary.op)) {
            return if (lhsType == REAL_AST_TYPE_INT && rhsType == REAL_AST_TYPE_INT) {
                Some(REAL_AST_TYPE_INT)
            } else {
                None
            }
        }
        if (RealASTIsOrderingOp(binary.op)) {
            return if (lhsType == REAL_AST_TYPE_INT && rhsType == REAL_AST_TYPE_INT) {
                Some(REAL_AST_TYPE_BOOL)
            } else {
                None
            }
        }
        if (binary.op == AstTokenKind.EQUAL || binary.op == AstTokenKind.NOTEQ) {
            let comparable = (lhsType == REAL_AST_TYPE_INT && rhsType == REAL_AST_TYPE_INT) ||
                (lhsType == REAL_AST_TYPE_BOOL && rhsType == REAL_AST_TYPE_BOOL)
            return if (comparable) { Some(REAL_AST_TYPE_BOOL) } else { None }
        }
        if (binary.op == AstTokenKind.AND || binary.op == AstTokenKind.OR) {
            return if (lhsType == REAL_AST_TYPE_BOOL && rhsType == REAL_AST_TYPE_BOOL) {
                Some(REAL_AST_TYPE_BOOL)
            } else {
                None
            }
        }
        return None
    }
    if (let Some(matchExpr) <- (expr as AstMatchExpr)) {
        return RealASTMatchExprValueType(matchExpr, scope, packageScope)
    }
    if (let Some(call) <- (expr as AstCallExpr)) {
        let base = match (call.baseFunc) {
            case Some(value) => value
            case None => return None
        }
        if (let Some(member) <- (base as AstMemberAccess)) {
            if (!member.typeArguments.isEmpty()) {
                return None
            }
            let receiverExpr = match (member.baseExpr) {
                case Some(value) => value
                case None => return None
            }
            let receiverType = match (RealASTExprValueType(receiverExpr, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            let structName = match (RealASTStructNameFromTypeKey(receiverType)) {
                case Some(value) => value
                case None => return None
            }
            let structInfo = match (packageScope.GetStruct(structName)) {
                case Some(value) => value
                case None => return None
            }
            let method = match (structInfo.GetMethod(member.field.GetRawText())) {
                case Some(value) => value
                case None => return None
            }
            if (call.args.size != method.funcInfo.paramTypes.size) {
                return None
            }
            var idx: Int64 = 0
            while (idx < call.args.size) {
                let arg = call.args[idx]
                if (!arg.name.Empty() || arg.withInout) {
                    return None
                }
                let argExpr = match (arg.expr) {
                    case Some(value) => value
                    case None => return None
                }
                let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
                if (argType != method.funcInfo.paramTypes[idx]) {
                    return None
                }
                idx++
            }
            return Some(method.funcInfo.returnType)
        }
        let calleeRef = match (base as AstRefExpr) {
            case Some(value) => value
            case None => return None
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return None
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName.isEmpty() || scope.Contains(calleeName)) {
            return None
        }
        if (let Some(ctorInfo) <- packageScope.GetEnumCtor(calleeName)) {
            if (call.args.size != ctorInfo.payloadTypes.size) {
                return None
            }
            var enumArgIndex: Int64 = 0
            while (enumArgIndex < call.args.size) {
                let arg = call.args[enumArgIndex]
                if (!arg.name.Empty() || arg.withInout) {
                    return None
                }
                let argExpr = match (arg.expr) {
                    case Some(value) => value
                    case None => return None
                }
                let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
                if (argType != ctorInfo.payloadTypes[enumArgIndex]) {
                    return None
                }
                enumArgIndex++
            }
            return Some(RealASTEnumTypeKey(ctorInfo.ownerName))
        }
        if (packageScope.IsStruct(calleeName)) {
            let structInfo = match (packageScope.GetStruct(calleeName)) {
                case Some(value) => value
                case None => return None
            }
            if (call.args.size != structInfo.initParamTypes.size) {
                return None
            }
            var idx: Int64 = 0
            while (idx < call.args.size) {
                let arg = call.args[idx]
                if (!arg.name.Empty() || arg.withInout) {
                    return None
                }
                let argExpr = match (arg.expr) {
                    case Some(value) => value
                    case None => return None
                }
                let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
                    case Some(value) => value
                    case None => return None
                }
                if (argType != structInfo.initParamTypes[idx]) {
                    return None
                }
                idx++
            }
            return Some(RealASTStructTypeKey(calleeName))
        }
        let info = match (packageScope.GetFunction(calleeName)) {
            case Some(value) => value
            case None => return None
        }
        if (call.args.size != info.paramTypes.size) {
            return None
        }
        var idx: Int64 = 0
        while (idx < call.args.size) {
            let arg = call.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let argType = match (RealASTExprValueType(argExpr, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            if (argType != info.paramTypes[idx]) {
                return None
            }
            idx++
        }
        return if (info.returnType == REAL_AST_TYPE_UNIT || info.returnType == REAL_AST_TYPE_NONE) {
            None
        } else { Some(info.returnType) }
    }
    return None
}

private func RealASTMatchExprValueType(matchExpr: AstMatchExpr, scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope): Option<String> {
    let enumInfo = match (RealASTMatchEnumInfo(matchExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    var resultType: Option<String> = None
    let seenTags = HashSet<Int64>()
    var hasWildcard = false
    for (matchCase in matchExpr.matchCases) {
        if (matchCase.patternGuard.isSome() || matchCase.patterns.size != 1) {
            return None
        }
        let patternInfo = match (RealASTMatchPatternInfoFor(matchCase.patterns[0], enumInfo)) {
            case Some(value) => value
            case None => return None
        }
        if (patternInfo.isWildcard) {
            hasWildcard = true
        } else {
            seenTags.add(patternInfo.tag)
        }
        let caseBlock = match (matchCase.exprOrDecls) {
            case Some(value) => value
            case None => return None
        }
        let caseExpr = match (RealASTSingleCaseExpr(caseBlock)) {
            case Some(value) => value
            case None => return None
        }
        let snapshot = scope.Save()
        if (!RealASTAddMatchBindings(patternInfo, scope)) {
            scope.Restore(snapshot)
            return None
        }
        let caseType = match (RealASTExprValueType(caseExpr, scope, packageScope)) {
            case Some(value) => value
            case None =>
                scope.Restore(snapshot)
                return None
        }
        scope.Restore(snapshot)
        resultType = match (resultType) {
            case Some(existing) =>
                if (existing != caseType) {
                    return None
                }
                Some(existing)
            case None => Some(caseType)
        }
    }
    if (!hasWildcard && seenTags.size != enumInfo.ctorNames.size) {
        return None
    }
    return resultType
}

private func LowerRealASTMatchSelector(matchExpr: AstMatchExpr, scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    let selector = match (matchExpr.selector) {
        case Some(value) => value
        case None => return None
    }
    if (RealASTMatchEnumInfo(matchExpr, scope, packageScope).isNone()) {
        return None
    }
    return LowerRealASTExpr(selector, scope, packageScope)
}

private func LowerRealASTMatchCases(
    matchExpr: AstMatchExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope,
    mode: Int64,
    resultName!: String = ""
): Option<ArrayList<AST2CHIRMatchCaseSpec>> {
    let enumInfo = match (RealASTMatchEnumInfo(matchExpr, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let out = ArrayList<AST2CHIRMatchCaseSpec>()
    let seenTags = HashSet<Int64>()
    var hasWildcard = false
    for (matchCase in matchExpr.matchCases) {
        if (matchCase.patternGuard.isSome() || matchCase.patterns.size != 1) {
            return None
        }
        let patternInfo = match (RealASTMatchPatternInfoFor(matchCase.patterns[0], enumInfo)) {
            case Some(value) => value
            case None => return None
        }
        if (patternInfo.isWildcard) {
            hasWildcard = true
        } else {
            seenTags.add(patternInfo.tag)
        }
        let caseSpec = AST2CHIRMatchCaseSpec(patternInfo.tag, isWildcard: patternInfo.isWildcard)
        var bindIndex: Int64 = 0
        while (bindIndex < patternInfo.bindNames.size && bindIndex < patternInfo.bindTypes.size) {
            caseSpec.AddBinding(patternInfo.bindNames[bindIndex], patternInfo.bindTypes[bindIndex])
            bindIndex++
        }
        let caseBlock = match (matchCase.exprOrDecls) {
            case Some(value) => value
            case None => return None
        }
        let snapshot = scope.Save()
        if (!RealASTAddMatchBindings(patternInfo, scope)) {
            scope.Restore(snapshot)
            return None
        }
        if (mode == REAL_AST_MATCH_BODY_RETURN || mode == REAL_AST_MATCH_BODY_ASSIGN) {
            let caseExpr = match (RealASTSingleCaseExpr(caseBlock)) {
                case Some(value) => value
                case None =>
                    scope.Restore(snapshot)
                    return None
            }
            let exprSpec = match (LowerRealASTExpr(caseExpr, scope, packageScope)) {
                case Some(value) => value
                case None =>
                    scope.Restore(snapshot)
                    return None
            }
            if (mode == REAL_AST_MATCH_BODY_RETURN) {
                caseSpec.AddBodyStatement(AST2CHIRStmtSpec.Return(exprSpec))
            } else {
                caseSpec.AddBodyStatement(AST2CHIRStmtSpec.Assign(resultName, exprSpec))
            }
        } else {
            let caseLowering = match (LowerRealASTBlock(caseBlock, scope, packageScope)) {
                case Some(value) => value
                case None =>
                    scope.Restore(snapshot)
                    return None
            }
            for (stmt in caseLowering.stmts) {
                caseSpec.AddBodyStatement(stmt)
            }
        }
        scope.Restore(snapshot)
        out.add(caseSpec)
    }
    if (!hasWildcard && seenTags.size != enumInfo.ctorNames.size) {
        return None
    }
    return Some(out)
}

private func RealASTMatchEnumInfo(matchExpr: AstMatchExpr, scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope): Option<RealASTEnumInfo> {
    if (!matchExpr.matchMode || !matchExpr.matchCaseOthers.isEmpty()) {
        return None
    }
    let selector = match (matchExpr.selector) {
        case Some(value) => value
        case None => return None
    }
    let selectorType = match (RealASTExprValueType(selector, scope, packageScope)) {
        case Some(value) => value
        case None => return None
    }
    let enumName = match (RealASTEnumNameFromTypeKey(selectorType)) {
        case Some(value) => value
        case None => return None
    }
    return packageScope.GetEnum(enumName)
}

private func RealASTMatchPatternInfoFor(pattern: AstPattern,
    enumInfo: RealASTEnumInfo): Option<RealASTMatchPatternInfo> {
    if ((pattern as AstWildcardPattern).isSome()) {
        return Some(RealASTMatchPatternInfo(true, -1))
    }
    if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
        let ctorInfo = match (enumInfo.GetCtor(varOrEnum.identifier.Val())) {
            case Some(value) => value
            case None => return None
        }
        if (!ctorInfo.payloadTypes.isEmpty()) {
            return None
        }
        return Some(RealASTMatchPatternInfo(false, ctorInfo.tag))
    }
    if (let Some(enumPattern) <- (pattern as AstEnumPattern)) {
        let ctorInfo = match (enumInfo.GetCtor(enumPattern.GetIdentifier())) {
            case Some(value) => value
            case None => return None
        }
        if (enumPattern.patterns.size != ctorInfo.payloadTypes.size) {
            return None
        }
        let out = RealASTMatchPatternInfo(false, ctorInfo.tag)
        var idx: Int64 = 0
        while (idx < enumPattern.patterns.size) {
            if (!RealASTPayloadPatternInfo(enumPattern.patterns[idx], ctorInfo.payloadTypes[idx], out)) {
                return None
            }
            idx++
        }
        return Some(out)
    }
    return None
}

private func RealASTPayloadPatternInfo(pattern: AstPattern, typeKey: String,
    out: RealASTMatchPatternInfo): Bool {
    if ((pattern as AstWildcardPattern).isSome()) {
        return true
    }
    if (let Some(varOrEnum) <- (pattern as AstVarOrEnumPattern)) {
        return out.AddBinding(varOrEnum.identifier.Val(), typeKey)
    }
    if (let Some(varPattern) <- (pattern as AstVarPattern)) {
        if (let Some(decl) <- varPattern.varDecl) {
            return out.AddBinding(decl.identifier.Val(), typeKey)
        }
    }
    return false
}

private func RealASTAddMatchBindings(patternInfo: RealASTMatchPatternInfo,
    scope: RealASTLoweringScope): Bool {
    var idx: Int64 = 0
    while (idx < patternInfo.bindNames.size && idx < patternInfo.bindTypes.size) {
        if (!scope.Add(patternInfo.bindNames[idx], false, patternInfo.bindTypes[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func RealASTSingleCaseExpr(block: AstBlock): Option<AstExpr> {
    if (block.body.size != 1) {
        return None
    }
    return block.body[0] as AstExpr
}

private func RealASTIsArithmeticOp(op: AstTokenKind): Bool {
    return op == AstTokenKind.ADD || op == AstTokenKind.SUB || op == AstTokenKind.MUL ||
        op == AstTokenKind.DIV || op == AstTokenKind.MOD
}

private func RealASTIsOrderingOp(op: AstTokenKind): Bool {
    return op == AstTokenKind.LT || op == AstTokenKind.LE || op == AstTokenKind.GT || op == AstTokenKind.GE
}

private func RealASTBinaryOp(op: AstTokenKind): Option<ExprKind> {
    return match (op) {
        case AstTokenKind.ADD => Some(ExprKind.ADD)
        case AstTokenKind.SUB => Some(ExprKind.SUB)
        case AstTokenKind.MUL => Some(ExprKind.MUL)
        case AstTokenKind.DIV => Some(ExprKind.DIV)
        case AstTokenKind.MOD => Some(ExprKind.MOD)
        case AstTokenKind.LT => Some(ExprKind.LT)
        case AstTokenKind.LE => Some(ExprKind.LE)
        case AstTokenKind.GT => Some(ExprKind.GT)
        case AstTokenKind.GE => Some(ExprKind.GE)
        case AstTokenKind.EQUAL => Some(ExprKind.EQUAL)
        case AstTokenKind.NOTEQ => Some(ExprKind.NOTEQUAL)
        case AstTokenKind.AND => Some(ExprKind.AND)
        case AstTokenKind.OR => Some(ExprKind.OR)
        case _ => None
    }
}

private func RealASTUnaryOp(op: AstTokenKind): Option<ExprKind> {
    return match (op) {
        case AstTokenKind.SUB => Some(ExprKind.NEG)
        case AstTokenKind.NOT => Some(ExprKind.NOT)
        case _ => None
    }
}

private func RealASTReturnType(
    context: CHIRContext,
    body: AstFuncBody,
    lowered: RealASTBodyLowering,
    packageScope: RealASTPackageLoweringScope
): Option<Type> {
    if (let Some(retType) <- body.retType) {
        return match (RealASTReturnTypeKey(retType, packageScope)) {
            case Some(typeKey) => RealASTCHIRTypeForKey(context, typeKey)
            case None => None
        }
    }
    if (lowered.returnType == REAL_AST_TYPE_INT || lowered.returnType == REAL_AST_TYPE_BOOL ||
        lowered.returnType == REAL_AST_TYPE_STRING || RealASTIsStructTypeKey(lowered.returnType) ||
        RealASTIsEnumTypeKey(lowered.returnType)) {
        return None
    }
    return Some(context.GetUnitTy())
}

private func RealASTParamType(context: CHIRContext, ty: AstType,
    packageScope: RealASTPackageLoweringScope): Option<Type> {
    return match (RealASTValueTypeKey(ty, packageScope: Some(packageScope))) {
        case Some(typeKey) => RealASTCHIRTypeForKey(context, typeKey)
        case None => None
    }
}

private func RealASTValueTypeKind(ty: AstType): Option<Int64> {
    if (let Some(typeKey) <- RealASTValueTypeKey(ty, packageScope: None)) {
        return Some(RealASTKindFromTypeKey(typeKey))
    }
    return None
}

private func RealASTLocalTypeKey(ty: AstType, packageScope: RealASTPackageLoweringScope): Option<String> {
    return RealASTValueTypeKey(ty, packageScope: Some(packageScope))
}

private func RealASTReturnTypeKey(ty: AstType, packageScope: RealASTPackageLoweringScope): Option<String> {
    if (IsRealASTUnitType(ty)) {
        return Some(REAL_AST_TYPE_UNIT)
    }
    return RealASTValueTypeKey(ty, packageScope: Some(packageScope))
}

private func RealASTValueTypeKey(ty: AstType, packageScope!: Option<RealASTPackageLoweringScope> = None): Option<String> {
    if (IsRealASTInt64Type(ty)) {
        return Some(REAL_AST_TYPE_INT)
    }
    if (IsRealASTBoolType(ty)) {
        return Some(REAL_AST_TYPE_BOOL)
    }
    if (IsRealASTStringType(ty)) {
        return Some(REAL_AST_TYPE_STRING)
    }
    let name = ty.ToString().trimAscii()
    if (let Some(scope) <- packageScope) {
        if (scope.IsStruct(name)) {
            return Some(RealASTStructTypeKey(name))
        }
        if (scope.IsEnum(name)) {
            return Some(RealASTEnumTypeKey(name))
        }
    }
    return None
}

private func RealASTPrimitiveFieldTypeKey(ty: AstType): Option<String> {
    if (IsRealASTInt64Type(ty)) {
        return Some(REAL_AST_TYPE_INT)
    }
    if (IsRealASTBoolType(ty)) {
        return Some(REAL_AST_TYPE_BOOL)
    }
    if (IsRealASTStringType(ty)) {
        return Some(REAL_AST_TYPE_STRING)
    }
    return None
}

private func RealASTCHIRTypeForKey(context: CHIRContext, typeKey: String): Option<Type> {
    if (typeKey == REAL_AST_TYPE_INT || RealASTIsStructTypeKey(typeKey) || RealASTIsEnumTypeKey(typeKey)) {
        return Some(context.GetInt64Ty())
    }
    if (typeKey == REAL_AST_TYPE_BOOL) {
        return Some(context.GetBoolTy())
    }
    if (typeKey == REAL_AST_TYPE_UNIT) {
        return Some(context.GetUnitTy())
    }
    if (typeKey == REAL_AST_TYPE_STRING) {
        return Some(context.GetCStringTy())
    }
    return None
}

private func RealASTTypeKeyFromKind(kind: Int64): String {
    if (kind == REAL_AST_RETURN_INT) {
        return REAL_AST_TYPE_INT
    }
    if (kind == REAL_AST_RETURN_BOOL) {
        return REAL_AST_TYPE_BOOL
    }
    if (kind == REAL_AST_RETURN_UNIT) {
        return REAL_AST_TYPE_UNIT
    }
    if (kind == REAL_AST_RETURN_STRING) {
        return REAL_AST_TYPE_STRING
    }
    return REAL_AST_TYPE_NONE
}

private func RealASTKindFromTypeKey(typeKey: String): Int64 {
    if (typeKey == REAL_AST_TYPE_INT || RealASTIsStructTypeKey(typeKey) || RealASTIsEnumTypeKey(typeKey)) {
        return REAL_AST_RETURN_INT
    }
    if (typeKey == REAL_AST_TYPE_BOOL) {
        return REAL_AST_RETURN_BOOL
    }
    if (typeKey == REAL_AST_TYPE_UNIT) {
        return REAL_AST_RETURN_UNIT
    }
    if (typeKey == REAL_AST_TYPE_STRING) {
        return REAL_AST_RETURN_STRING
    }
    return REAL_AST_RETURN_NONE
}

private func RealASTStructTypeKey(name: String): String {
    return REAL_AST_STRUCT_PREFIX + name
}

private func RealASTIsStructTypeKey(typeKey: String): Bool {
    return typeKey.startsWith(REAL_AST_STRUCT_PREFIX)
}

private func RealASTStructNameFromTypeKey(typeKey: String): Option<String> {
    if (!RealASTIsStructTypeKey(typeKey)) {
        return None
    }
    return Some(typeKey[REAL_AST_STRUCT_PREFIX.size..typeKey.size])
}

private func RealASTEnumTypeKey(name: String): String {
    return REAL_AST_ENUM_PREFIX + name
}

private func RealASTIsEnumTypeKey(typeKey: String): Bool {
    return typeKey.startsWith(REAL_AST_ENUM_PREFIX)
}

private func RealASTEnumNameFromTypeKey(typeKey: String): Option<String> {
    if (!RealASTIsEnumTypeKey(typeKey)) {
        return None
    }
    return Some(typeKey[REAL_AST_ENUM_PREFIX.size..typeKey.size])
}

private func RealASTFieldNameFromThisTarget(expr: AstExpr): Option<String> {
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        if (!refExpr.typeArguments.isEmpty()) {
            return None
        }
        return Some(refExpr.ref.identifier.Val())
    }
    if (let Some(member) <- (expr as AstMemberAccess)) {
        if (!member.typeArguments.isEmpty()) {
            return None
        }
        let base = match (member.baseExpr) {
            case Some(value) => value
            case None => return None
        }
        let baseRef = match (base as AstRefExpr) {
            case Some(value) => value
            case None => return None
        }
        if (baseRef.ref.identifier.Val() != "this") {
            return None
        }
        return Some(member.field.GetRawText())
    }
    return None
}

private func LowerRealASTInitRhs(expr: AstExpr, argMap: HashMap<String, AST2CHIRExprSpec>,
    scope: RealASTLoweringScope, packageScope: RealASTPackageLoweringScope): Option<AST2CHIRExprSpec> {
    if (let Some(parenExpr) <- (expr as AstParenExpr)) {
        if (let Some(inner) <- parenExpr.expr) {
            return LowerRealASTInitRhs(inner, argMap, scope, packageScope)
        }
        return None
    }
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (let Some(value) <- ParseRealASTIntLiteral(lit)) {
            return Some(AST2CHIRExprSpec.Literal(value))
        }
        if (let Some(value) <- ParseRealASTBoolLiteral(lit)) {
            return Some(AST2CHIRExprSpec.BoolLit(value))
        }
        if (let Some(text) <- PlainRealASTStringLiteralValue(lit)) {
            return Some(AST2CHIRExprSpec.StrLit(text))
        }
        return None
    }
    if (let Some(refExpr) <- (expr as AstRefExpr)) {
        let name = refExpr.ref.identifier.Val()
        return argMap.get(name)
    }
    if (let Some(unary) <- (expr as AstUnaryExpr)) {
        let op = match (RealASTUnaryOp(unary.op)) {
            case Some(value) => value
            case None => return None
        }
        let operandExpr = match (unary.expr) {
            case Some(value) => value
            case None => return None
        }
        let operandSpec = match (LowerRealASTInitRhs(operandExpr, argMap, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Unary(op, operandSpec))
    }
    if (let Some(binary) <- (expr as AstBinaryExpr)) {
        let op = match (RealASTBinaryOp(binary.op)) {
            case Some(value) => value
            case None => return None
        }
        let lhs = match (binary.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let rhs = match (binary.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let lhsSpec = match (LowerRealASTInitRhs(lhs, argMap, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        let rhsSpec = match (LowerRealASTInitRhs(rhs, argMap, scope, packageScope)) {
            case Some(value) => value
            case None => return None
        }
        return Some(AST2CHIRExprSpec.Binary(op, lhsSpec, rhsSpec))
    }
    return None
}

private func RealASTStructMethodName(structType: String, methodName: String): String {
    return "$struct$" + structType + "$" + methodName
}

private func IsRealASTInt64Type(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Int64" || name == "Int"
}

private func IsRealASTBoolType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Bool"
}

private func IsRealASTUnitType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "Unit" || name == "()"
}

private func IsRealASTStringType(ty: AstType): Bool {
    let name = ty.ToString().trimAscii()
    return name == "String" || name == "CString"
}

private func ParseRealASTIntLiteral(lit: AstLitConstExpr): Option<Int64> {
    if (lit.kind != AstLitConstKind.INTEGER) {
        return None
    }
    let text = StripIntegerSuffix(lit.stringValue.replace("_", ""))
    try {
        return Some(Int64.parse(text))
    } catch (e: Exception) {
        return None
    }
}

private func ParseRealASTBoolLiteral(lit: AstLitConstExpr): Option<Bool> {
    if (lit.kind != AstLitConstKind.BOOL) {
        return None
    }
    let text = lit.stringValue.trimAscii()
    if (text == "true") {
        return Some(true)
    }
    if (text == "false") {
        return Some(false)
    }
    return None
}

private func PlainRealASTStringLiteralValue(expr: AstExpr): Option<String> {
    if (let Some(lit) <- (expr as AstLitConstExpr)) {
        if (lit.kind != AstLitConstKind.STRING || lit.siExpr.isSome()) {
            return None
        }
        let text = lit.stringValue
        var idx: Int64 = 0
        while (idx < text.size) {
            if (text[idx] == b'\\') {
                return None
            }
            idx++
        }
        return Some(text)
    }
    return None
}

private func LowerRealASTInterpolation(
    lit: AstLitConstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<AST2CHIRExprSpec> {
    let si = match (lit.siExpr) {
        case Some(value) => value
        case None => return None
    }
    if (si.strParts.size != si.strPartExprs.size || si.strParts.isEmpty()) {
        return None
    }
    var acc: Option<AST2CHIRExprSpec> = None
    var idx: Int64 = 0
    while (idx < si.strParts.size) {
        let part = si.strParts[idx]
        let partExpr = si.strPartExprs[idx]
        let pieceSpec = if (part.strKind == AstStringPartKind.STR) {
            match (PlainRealASTInterpolationText(part.value)) {
                case Some(text) => AST2CHIRExprSpec.StrLit(text)
                case None => return None
            }
        } else {
            let inner = match (RealASTInterpolationInnerExpr(partExpr)) {
                case Some(value) => value
                case None => return None
            }
            let innerKind = match (RealASTExprValueKind(inner, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            let innerSpec = match (LowerRealASTExpr(inner, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            if (innerKind == REAL_AST_RETURN_STRING) {
                innerSpec
            } else if (innerKind == REAL_AST_RETURN_INT || innerKind == REAL_AST_RETURN_BOOL) {
                AST2CHIRExprSpec.ToStringConv(innerSpec)
            } else {
                return None
            }
        }
        acc = match (acc) {
            case Some(prev) => Some(AST2CHIRExprSpec.Binary(ExprKind.ADD, prev, pieceSpec))
            case None => Some(pieceSpec)
        }
        idx++
    }
    return acc
}

private func RealASTInterpolationValueKind(
    lit: AstLitConstExpr,
    scope: RealASTLoweringScope,
    packageScope: RealASTPackageLoweringScope
): Option<Int64> {
    if (lit.kind != AstLitConstKind.STRING) {
        return None
    }
    let si = match (lit.siExpr) {
        case Some(value) => value
        case None => return None
    }
    if (si.strParts.size != si.strPartExprs.size || si.strParts.isEmpty()) {
        return None
    }
    var idx: Int64 = 0
    while (idx < si.strParts.size) {
        let part = si.strParts[idx]
        let partExpr = si.strPartExprs[idx]
        if (part.strKind == AstStringPartKind.STR) {
            if (PlainRealASTInterpolationText(part.value).isNone()) {
                return None
            }
        } else {
            let inner = match (RealASTInterpolationInnerExpr(partExpr)) {
                case Some(value) => value
                case None => return None
            }
            let innerKind = match (RealASTExprValueKind(inner, scope, packageScope)) {
                case Some(value) => value
                case None => return None
            }
            if (innerKind != REAL_AST_RETURN_INT && innerKind != REAL_AST_RETURN_BOOL &&
                innerKind != REAL_AST_RETURN_STRING) {
                return None
            }
        }
        idx++
    }
    return Some(REAL_AST_RETURN_STRING)
}

private func RealASTInterpolationInnerExpr(partExpr: AstExpr): Option<AstExpr> {
    let interp = match (partExpr as AstInterpolationExpr) {
        case Some(value) => value
        case None => return None
    }
    let block = match (interp.block) {
        case Some(value) => value
        case None => return None
    }
    if (block.body.size != 1) {
        return None
    }
    return block.body[0] as AstExpr
}

private func PlainRealASTInterpolationText(text: String): Option<String> {
    var idx: Int64 = 0
    while (idx < text.size) {
        if (text[idx] == b'\\') {
            return None
        }
        idx++
    }
    return Some(text)
}

private func StripIntegerSuffix(value: String): String {
    if (value.endsWith("i64") || value.endsWith("u64") ||
        value.endsWith("i32") || value.endsWith("u32") ||
        value.endsWith("i16") || value.endsWith("u16")) {
        return value[0..value.size - 3]
    }
    if (value.endsWith("i8") || value.endsWith("u8")) {
        return value[0..value.size - 2]
    }
    return value
}

private func RealASTDisplayName(decl: AstDecl): String {
    if ((decl as AstMainDecl).isSome()) {
        return "main"
    }
    if (!decl.identifier.Empty()) {
        return decl.identifier.Val()
    }
    return RealASTStableMangledName("", decl)
}

private func RealASTStableMangledName(packageName: String, decl: AstDecl): String {
    if (!decl.mangledName.isEmpty()) {
        return decl.mangledName
    }
    let identifier = if (decl.identifier.Empty()) {
        "decl_" + decl.begin.line.toString() + "_" + decl.begin.column.toString()
    } else {
        decl.identifier.Val()
    }
    return "_C" + (packageName + "." + identifier).replace(".", "_").replace("::", "_")
}
