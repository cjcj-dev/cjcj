package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions

public class RealSemaDiagnostic {
    public let position: Position
    public let message: String

    public init(position: Position, message: String) {
        this.position = position
        this.message = message
    }
}

private class RealPipelineLocalInfo {
    let ty: Ty
    let mutable: Bool

    init(ty: Ty, mutable: Bool) {
        this.ty = ty
        this.mutable = mutable
    }
}

private class RealPipelineStructInfo {
    let name: String
    let decl: StructDecl
    let ty: Ty
    let fieldTypes: HashMap<String, Ty> = HashMap<String, Ty>()
    let fieldMutable: HashMap<String, Bool> = HashMap<String, Bool>()
    let fieldIndex: HashMap<String, Int64> = HashMap<String, Int64>()
    let fieldNames: ArrayList<String> = ArrayList<String>()
    let initParamTypes: ArrayList<Ty> = ArrayList<Ty>()
    let initParamNames: ArrayList<String> = ArrayList<String>()
    let methods: HashMap<String, FuncTy> = HashMap<String, FuncTy>()
    let methodDecls: HashMap<String, FuncDecl> = HashMap<String, FuncDecl>()
    var initDecl: Option<FuncDecl> = None

    init(name: String, decl: StructDecl, ty: Ty) {
        this.name = name
        this.decl = decl
        this.ty = ty
    }

    func AddField(name: String, ty: Ty, mutable: Bool): Bool {
        if (name.isEmpty() || fieldTypes.contains(name)) {
            return false
        }
        fieldIndex[name] = fieldNames.size
        fieldNames.add(name)
        fieldTypes[name] = ty
        fieldMutable[name] = mutable
        return true
    }

    func FieldType(name: String): Option<Ty> {
        return fieldTypes.get(name)
    }

    func FieldCanWrite(name: String): Bool {
        return fieldMutable.get(name) ?? false
    }

    func AddMethod(name: String, decl: FuncDecl, ty: FuncTy): Bool {
        if (name.isEmpty() || methods.contains(name)) {
            return false
        }
        methods[name] = ty
        methodDecls[name] = decl
        return true
    }
}

private class RealPipelineScopeSnapshot {
    let locals: HashMap<String, RealPipelineLocalInfo> = HashMap<String, RealPipelineLocalInfo>()
    let loopDepth: Int64
    let thisStructName: String

    init(scope: RealPipelineScope) {
        for ((name, local) in scope.locals) {
            locals[name] = local
        }
        loopDepth = scope.loopDepth
        thisStructName = scope.thisStructName
    }
}

private class RealPipelineScope {
    let locals: HashMap<String, RealPipelineLocalInfo> = HashMap<String, RealPipelineLocalInfo>()
    var loopDepth: Int64 = 0
    var thisStructName: String = ""

    func Add(name: String, ty: Ty, mutable: Bool): Bool {
        if (locals.contains(name)) {
            return false
        }
        locals[name] = RealPipelineLocalInfo(ty, mutable)
        return true
    }

    func Get(name: String): Option<RealPipelineLocalInfo> {
        return locals.get(name)
    }

    func Contains(name: String): Bool {
        return locals.contains(name)
    }

    func Save(): RealPipelineScopeSnapshot {
        return RealPipelineScopeSnapshot(this)
    }

    func Restore(snapshot: RealPipelineScopeSnapshot): Unit {
        locals.clear()
        for ((name, local) in snapshot.locals) {
            locals[name] = local
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

public class TypeChecker {
    private var ci: Option<CompilerInstance> = None
    private var tm: TypeManager = TypeManager()
    private let realPipelineDiagnostics: ArrayList<RealSemaDiagnostic> = ArrayList<RealSemaDiagnostic>()
    private let realPipelineTypedFunctions: ArrayList<String> = ArrayList<String>()
    private let realPipelineDeclaredFunctions: HashSet<String> = HashSet<String>()
    private let realPipelineUnsupportedFunctions: HashSet<String> = HashSet<String>()
    private let realPipelineFunctionDecls: HashMap<String, FuncDecl> = HashMap<String, FuncDecl>()
    private let realPipelineFunctionTypes: HashMap<String, FuncTy> = HashMap<String, FuncTy>()
    private let realPipelineStructs: HashMap<String, RealPipelineStructInfo> = HashMap<String, RealPipelineStructInfo>()
    private var realPipelineUnsupported: Bool = false

    public init(ci: Option<CompilerInstance>) {
        this.ci = ci
        if (let Some(instance) <- ci) {
            tm = instance.typeManager
        }
    }

    public func TypeCheckForPackages(pkgs: ArrayList<Package>): Unit {
        realPipelineDiagnostics.clear()
        realPipelineTypedFunctions.clear()
        realPipelineStructs.clear()
        realPipelineUnsupported = false
        for (pkg in pkgs) {
            preparePackageTypes(pkg)
            prepareRealPipelineStructTable(pkg)
            prepareRealPipelineFunctionTable(pkg)
            checkRealPipelinePackage(pkg)
        }
    }

    public func GetRealPipelineDiagnostics(): ArrayList<RealSemaDiagnostic> {
        let out = ArrayList<RealSemaDiagnostic>()
        for (diag in realPipelineDiagnostics) {
            out.add(diag)
        }
        return out
    }

    public func GetRealPipelineTypedFunctions(): ArrayList<String> {
        let out = ArrayList<String>()
        for (summary in realPipelineTypedFunctions) {
            out.add(summary)
        }
        return out
    }

    public func HasRealPipelineErrors(): Bool {
        return !realPipelineDiagnostics.isEmpty()
    }

    public func HasRealPipelineUnsupported(): Bool {
        return realPipelineUnsupported
    }

    public func SetOverflowStrategy(pkgs: ArrayList<Package>): Unit {
        var optionStrategy = OverflowStrategy.THROWING
        if (let Some(instance) <- ci) {
            optionStrategy = instance.globalOptions.overflowStrategy
        }
        SetIntegerOverflowStrategy(pkgs, optionStrategy)
    }

    public func CheckInlineFunctions(pkgs: ArrayList<Package>): Unit {
        if (let Some(instance) <- ci) {
            CheckInlineFunctionsForPackages(pkgs, instance.globalOptions)
        }
    }

    public func CheckUnusedImportSpec(pkg: Package): ArrayList<UnusedImportFinding> {
        return CollectUnusedImports(pkg)
    }

    public func CheckAllDeclAttributes(pkg: Package): ArrayList<DeclAttributeIssue> {
        var options = OptionGlobalOptions()
        if (let Some(instance) <- ci) {
            options = instance.globalOptions
        }
        return CheckDeclAttributesForPackage(pkg, opts: options)
    }

    public func PerformDesugarAfterInstantiation(ctx: ASTContext, pkg: Package): Unit {
        if (pkg.files.isEmpty()) {
            return
        }
        PerformRecursiveTypesElimination(ctx.packageDecls, tm)
        MarkExtendBox(tm, pkg)
    }

    public func PerformDesugarAfterSema(pkgs: ArrayList<Package>): Unit {
        let tyVarScope = BeginTyVarScope(tm)
        for (pkg in pkgs) {
            MarkExtendBox(tm, pkg)
        }
        EndTyVarScope(tyVarScope)
    }

    public func SynReferenceSeparately(ctx: ASTContext, scopeName: String, expr: Expr, hasLocalDecl: Bool): Candidate {
        let _ = scopeName
        let _ = hasLocalDecl
        let candidate = Candidate()
        if (let Some(ty) <- expr.GetTy()) {
            candidate.tys.add(ty)
            candidate.hasDecl = false
            return candidate
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let names = Names(refExpr.ref.identifier.Val(), ctx.currentScopeName)
            for (decl in ctx.GetDeclsByName(names)) {
                candidate.decls.add(decl)
            }
            candidate.hasDecl = !candidate.decls.isEmpty()
        }
        return candidate
    }

    public func RemoveTargetNotMeetExtendConstraint(baseTy: Ty, targets: ArrayList<Decl>): Unit {
        var idx: Int64 = 0
        while (idx < targets.size) {
            if (let Some(parentDecl) <- targets[idx].outerDecl) {
                if (let Some(extendDecl) <- (parentDecl as ExtendDecl)) {
                    if (!tm.CheckExtendWithConstraint(baseTy, extendDecl)) {
                        targets.remove(at: idx)
                        continue
                    }
                }
            }
            idx++
        }
    }

    private func preparePackageTypes(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                synthesizeDeclType(decl)
            }
        }
    }

    private func prepareRealPipelineStructTable(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(structDecl) <- (decl as StructDecl)) {
                    if (!prepareRealPipelineStruct(structDecl)) {
                        markRealPipelineUnsupported()
                    }
                }
            }
        }
    }

    private func prepareRealPipelineStruct(structDecl: StructDecl): Bool {
        let name = structDecl.identifier.Val()
        if (name.isEmpty() || structDecl.generic.isSome() || !structDecl.inheritedTypes.isEmpty()) {
            return false
        }
        let body = match (structDecl.body) {
            case Some(value) => value
            case None => return false
        }
        let structTy = tm.GetStructTy(structDecl, Array<Ty>())
        structDecl.SetTy(structTy)
        let info = RealPipelineStructInfo(name, structDecl, structTy)
        var initCount: Int64 = 0
        let methods = ArrayList<FuncDecl>()
        for (member in body.decls) {
            if (let Some(fieldDecl) <- (member as VarDecl)) {
                if (fieldDecl.isConst || fieldDecl.initializer.isSome()) {
                    return false
                }
                let typeNode = match (fieldDecl.typeNode) {
                    case Some(value) => value
                    case None => return false
                }
                let fieldTy = match (resolveRealPipelineStoredFieldType(typeNode)) {
                    case Some(value) => value
                    case None => return false
                }
                fieldDecl.SetTy(fieldTy)
                typeNode.SetTy(fieldTy)
                if (!info.AddField(fieldDecl.identifier.Val(), fieldTy, fieldDecl.isVar)) {
                    return false
                }
                continue
            }
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (funcDecl.funcBody.isNone()) {
                    return false
                }
                if (funcDecl.TestAttr(Attribute.CONSTRUCTOR) || funcDecl.identifier.Val() == "init") {
                    initCount++
                    if (initCount != 1) {
                        return false
                    }
                    info.initDecl = Some(funcDecl)
                    if (!prepareRealPipelineStructInitSignature(info, funcDecl)) {
                        return false
                    }
                } else {
                    methods.add(funcDecl)
                }
                continue
            }
            return false
        }
        if (initCount != 1 || info.fieldNames.isEmpty()) {
            return false
        }
        realPipelineStructs[name] = info
        for (method in methods) {
            let body = match (method.funcBody) {
                case Some(value) => value
                case None => return false
            }
            body.funcDecl = Some(method)
            let funcTy = match (prepareRealPipelineFuncSignature(method, body)) {
                case Some(value) => value
                case None => return false
            }
            if (!info.AddMethod(method.identifier.Val(), method, funcTy)) {
                return false
            }
        }
        return true
    }

    private func prepareRealPipelineStructInitSignature(info: RealPipelineStructInfo,
        funcDecl: FuncDecl): Bool {
        let body = match (funcDecl.funcBody) {
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
            let paramTy = match (resolveRealPipelineLocalType(typeNode)) {
                case Some(value) => value
                case None => return false
            }
            if (!isRealPipelineValueTy(paramTy)) {
                return false
            }
            param.SetTy(paramTy)
            typeNode.SetTy(paramTy)
            info.initParamNames.add(param.identifier.Val())
            info.initParamTypes.add(paramTy)
        }
        body.SetTy(tm.GetFunctionTy(info.initParamTypes.toArray(), TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)))
        funcDecl.SetTy(body.GetTy().getOrThrow())
        return true
    }

    private func prepareRealPipelineFunctionTable(pkg: Package): Unit {
        realPipelineDeclaredFunctions.clear()
        realPipelineUnsupportedFunctions.clear()
        realPipelineFunctionDecls.clear()
        realPipelineFunctionTypes.clear()
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    let name = funcDecl.identifier.Val()
                    if (name.isEmpty()) {
                        markRealPipelineUnsupported()
                        continue
                    }
                    if (realPipelineDeclaredFunctions.contains(name)) {
                        realPipelineUnsupportedFunctions.add(name)
                        realPipelineFunctionDecls.remove(name)
                        realPipelineFunctionTypes.remove(name)
                        markRealPipelineUnsupported()
                    } else {
                        realPipelineDeclaredFunctions.add(name)
                    }
                }
            }
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                if (let Some(funcDecl) <- (decl as FuncDecl)) {
                    let name = funcDecl.identifier.Val()
                    if (name.isEmpty() || realPipelineUnsupportedFunctions.contains(name)) {
                        continue
                    }
                    let body = match (funcDecl.funcBody) {
                        case Some(value) => value
                        case None =>
                            realPipelineUnsupportedFunctions.add(name)
                            markRealPipelineUnsupported()
                            continue
                    }
                    body.funcDecl = Some(funcDecl)
                    let funcTy = match (prepareRealPipelineFuncSignature(decl, body)) {
                        case Some(value) => value
                        case None =>
                            realPipelineUnsupportedFunctions.add(name)
                            markRealPipelineUnsupported()
                            continue
                    }
                    realPipelineFunctionDecls[name] = funcDecl
                    realPipelineFunctionTypes[name] = funcTy
                }
            }
        }
    }

    private func synthesizeDeclType(decl: Decl): Unit {
        if (!Ty.IsTyCorrect(decl.GetTy())) {
            if (let Some(varDecl) <- (decl as VarDeclAbstract)) {
                if (let Some(typeNode) <- varDecl.typeNode) {
                    if (let Some(ty) <- typeNode.GetTy()) {
                        decl.SetTy(ty)
                    }
                }
            } else if (let Some(funcDecl) <- (decl as FuncDecl)) {
                if (let Some(body) <- funcDecl.funcBody) {
                    let params = ArrayList<Ty>()
                    if (!body.paramLists.isEmpty()) {
                        for (param in body.paramLists[0].params) {
                            if (let Some(ty) <- param.GetTy()) {
                                params.add(ty)
                            } else {
                                params.add(TypeManager.GetInvalidTy())
                            }
                        }
                    }
                    var retTy: Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                    if (let Some(retType) <- body.retType) {
                        if (let Some(ty) <- retType.GetTy()) {
                            retTy = ty
                        }
                    }
                    decl.SetTy(tm.GetFunctionTy(params.toArray(), retTy))
                }
            }
        }
        for (member in decl.GetMemberDecls()) {
            synthesizeDeclType(member)
        }
    }

    private func checkRealPipelinePackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (decl in file.decls) {
                checkRealPipelineDecl(decl)
            }
        }
    }

    private func checkRealPipelineDecl(decl: Decl): Unit {
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            if (let Some(body) <- mainDecl.funcBody) {
                checkRealPipelineFuncLike(decl, body, "main")
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                body.funcDecl = Some(funcDecl)
                checkRealPipelineFuncLike(decl, body, funcDecl.identifier.Val())
            } else {
                markRealPipelineUnsupported()
            }
            return
        }
        if (let Some(structDecl) <- (decl as StructDecl)) {
            checkRealPipelineStructDecl(structDecl)
            return
        }
        markRealPipelineUnsupported()
        for (member in decl.GetMemberDecls()) {
            checkRealPipelineDecl(member)
        }
    }

    private func checkRealPipelineStructDecl(structDecl: StructDecl): Unit {
        let info = match (realPipelineStructs.get(structDecl.identifier.Val())) {
            case Some(value) => value
            case None =>
                markRealPipelineUnsupported()
                return
        }
        if (let Some(initDecl) <- info.initDecl) {
            if (!checkRealPipelineStructInit(info, initDecl)) {
                markRealPipelineUnsupported()
                return
            }
        } else {
            markRealPipelineUnsupported()
            return
        }
        for ((methodName, methodTy) in info.methods) {
            let methodDecl = match (info.methodDecls.get(methodName)) {
                case Some(value) => value
                case None =>
                    markRealPipelineUnsupported()
                    return
            }
            let body = match (methodDecl.funcBody) {
                case Some(value) => value
                case None =>
                    markRealPipelineUnsupported()
                    return
            }
            let supportedBody = checkRealPipelineBody(body, methodTy.retTy, receiverStructName: info.name)
            if (supportedBody) {
                realPipelineTypedFunctions.add(info.name + "." + methodName + ": " + methodTy.String())
            }
        }
    }

    private func checkRealPipelineStructInit(info: RealPipelineStructInfo, initDecl: FuncDecl): Bool {
        let body = match (initDecl.funcBody) {
            case Some(value) => value
            case None => return false
        }
        let block = match (body.body) {
            case Some(value) => value
            case None => return false
        }
        let scope = RealPipelineScope()
        scope.thisStructName = info.name
        let _ = scope.Add("this", info.ty, false)
        if (body.paramLists.size != 1) {
            return false
        }
        for (param in body.paramLists[0].params) {
            let paramTy = match (param.GetTy()) {
                case Some(value) => value
                case None => return false
            }
            if (!scope.Add(param.identifier.Val(), paramTy, false)) {
                emitRealPipelineTypeError(param.begin, "duplicate local binding '" + param.identifier.Val() + "'")
                return true
            }
        }
        let assigned = HashSet<String>()
        for (node in block.body) {
            let assign = match (node as AssignExpr) {
                case Some(value) => value
                case None => return false
            }
            if (assign.op != TokenKind.ASSIGN) {
                return false
            }
            let left = match (assign.leftValue) {
                case Some(value) => value
                case None => return false
            }
            let fieldName = match (realPipelineFieldNameFromThisTarget(left)) {
                case Some(value) => value
                case None => return false
            }
            let fieldTy = match (info.FieldType(fieldName)) {
                case Some(value) => value
                case None => return false
            }
            if (assigned.contains(fieldName)) {
                emitRealPipelineTypeError(left.begin, "field '" + fieldName + "' initialized more than once")
                assign.SetTy(TypeManager.GetInvalidTy())
                return true
            }
            let right = match (assign.rightExpr) {
                case Some(value) => value
                case None => return false
            }
            let rightTy = match (typeRealPipelineExpr(right, scope, Some(fieldTy))) {
                case Some(value) => value
                case None => return false
            }
            if (!isRealPipelineAssignable(fieldTy, rightTy)) {
                emitRealPipelineTypeError(right.begin,
                    rightTy.String() + " initializer is not assignable to field '" + fieldName +
                    "' of type " + fieldTy.String())
                assign.SetTy(TypeManager.GetInvalidTy())
                return true
            }
            assigned.add(fieldName)
            assign.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        }
        if (assigned.size != info.fieldNames.size) {
            emitRealPipelineTypeError(block.begin, "struct init must initialize every supported field")
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        block.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return true
    }

    private func checkRealPipelineFuncLike(decl: Decl, body: FuncBody, displayName: String,
        receiverStructName!: String = ""): Unit {
        let funcTy = match (prepareRealPipelineFuncSignature(decl, body)) {
            case Some(value) => value
            case None => return
        }
        let retTy = funcTy.retTy
        let supportedBody = checkRealPipelineBody(body, retTy, receiverStructName: receiverStructName)
        if (supportedBody) {
            realPipelineTypedFunctions.add(displayName + ": " + funcTy.String())
        }
    }

    private func prepareRealPipelineFuncSignature(decl: Decl, body: FuncBody): Option<FuncTy> {
        if (body.generic.isSome() || body.paramLists.size != 1) {
            markRealPipelineUnsupported()
            return None
        }
        let params = ArrayList<Ty>()
        for (param in body.paramLists[0].params) {
            if (let Some(paramType) <- param.typeNode) {
                if (let Some(paramTy) <- resolveRealPipelineLocalType(paramType)) {
                    if (!isRealPipelineValueTy(paramTy)) {
                        param.SetTy(TypeManager.GetInvalidTy())
                        params.add(TypeManager.GetInvalidTy())
                        markRealPipelineUnsupported()
                        return None
                    }
                    param.SetTy(paramTy)
                    params.add(paramTy)
                } else {
                    param.SetTy(TypeManager.GetInvalidTy())
                    params.add(TypeManager.GetInvalidTy())
                    markRealPipelineUnsupported()
                    return None
                }
            } else {
                markRealPipelineUnsupported()
                return None
            }
        }
        let retTy = match (resolveRealPipelineReturnTy(body)) {
            case Some(value) => value
            case None => return None
        }
        let funcTy = tm.GetFunctionTy(params.toArray(), retTy)
        body.SetTy(funcTy)
        decl.SetTy(funcTy)
        return Some(funcTy)
    }

    private func resolveRealPipelineReturnTy(body: FuncBody): Option<Ty> {
        if (let Some(retType) <- body.retType) {
            if (let Some(retTy) <- resolveRealPipelineLocalType(retType)) {
                if (!isRealPipelineReturnTy(retTy)) {
                    markRealPipelineUnsupported()
                    return None
                }
                return Some(retTy)
            }
            retType.SetTy(TypeManager.GetInvalidTy())
            markRealPipelineUnsupported()
            return None
        }
        if (realPipelineBodyHasValueReturn(body)) {
            markRealPipelineUnsupported()
            return None
        }
        return Some(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
    }

    private func resolveRealPipelinePrimitiveType(typeNode: Type): Option<Ty> {
        if (let Some(existing) <- typeNode.GetTy()) {
            if (!existing.HasInvalidTy() && existing.kind != TypeKind.TYPE_INITIAL) {
                return Some(existing)
            }
        }
        if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            if (primitiveType.kind == TypeKind.TYPE_INVALID) {
                return None
            }
            let kind = if (primitiveType.kind == TypeKind.TYPE_IDEAL_INT) {
                TypeKind.TYPE_INT64
            } else {
                primitiveType.kind
            }
            let ty = TypeManager.GetPrimitiveTy(kind)
            primitiveType.SetTy(ty)
            return Some(ty)
        }
        if (let Some(parenType) <- (typeNode as ParenType)) {
            if (let Some(innerType) <- parenType.innerType) {
                if (let Some(ty) <- resolveRealPipelinePrimitiveType(innerType)) {
                    parenType.SetTy(ty)
                    return Some(ty)
                }
            }
        }
        return None
    }

    private func checkRealPipelineBody(body: FuncBody, retTy: Ty, receiverStructName!: String = ""): Bool {
        let block = match (body.body) {
            case Some(value) => value
            case None =>
                markRealPipelineUnsupported()
                return false
        }
        if (block.body.isEmpty()) {
            if (retTy.kind == TypeKind.TYPE_UNIT) {
                block.SetTy(retTy)
                return true
            }
            emitRealPipelineTypeError(block.begin, "missing return value for declared return type " + retTy.String())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let scope = RealPipelineScope()
        if (!receiverStructName.isEmpty()) {
            let info = match (realPipelineStructs.get(receiverStructName)) {
                case Some(value) => value
                case None =>
                    markRealPipelineUnsupported()
                    return false
            }
            scope.thisStructName = receiverStructName
            let _ = scope.Add("this", info.ty, false)
        }
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                let paramTy = match (param.GetTy()) {
                    case Some(value) => value
                    case None =>
                        markRealPipelineUnsupported()
                        return false
                }
                if (!scope.Add(param.identifier.Val(), paramTy, false)) {
                    emitRealPipelineTypeError(param.begin, "duplicate local binding '" + param.identifier.Val() + "'")
                    param.SetTy(TypeManager.GetInvalidTy())
                    return true
                }
            }
        }
        let bodyStatus = checkRealPipelineBlock(block, body, retTy, scope, scoped: false)
        if (!bodyStatus[0]) {
            markRealPipelineUnsupported()
            return false
        }
        let mustReturn = bodyStatus[1]
        if (!mustReturn && retTy.kind != TypeKind.TYPE_UNIT) {
            emitRealPipelineTypeError(block.begin, "missing return value for declared return type " + retTy.String())
            block.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        if (mustReturn) {
            block.SetTy(TypeManager.GetNothingTy())
        } else {
            block.SetTy(retTy)
        }
        return true
    }

    private func checkRealPipelineBlock(
        block: Block,
        body: FuncBody,
        retTy: Ty,
        scope: RealPipelineScope,
        scoped!: Bool = true
    ): Array<Bool> {
        let snapshot: Option<RealPipelineScopeSnapshot> = if (scoped) { Some(scope.Save()) } else { None }
        var mustReturn = false
        for (node in block.body) {
            let stmtStatus = checkRealPipelineStmt(node, body, retTy, scope)
            if (!stmtStatus[0]) {
                if (let Some(value) <- snapshot) {
                    scope.Restore(value)
                }
                return [false, false]
            }
            if (stmtStatus[1]) {
                mustReturn = true
            }
        }
        if (let Some(value) <- snapshot) {
            scope.Restore(value)
        }
        block.SetTy(if (mustReturn) { TypeManager.GetNothingTy() } else { retTy })
        return [true, mustReturn]
    }

    private func checkRealPipelineStmt(
        node: Node,
        body: FuncBody,
        retTy: Ty,
        scope: RealPipelineScope
    ): Array<Bool> {
        if (let Some(varDecl) <- (node as VarDecl)) {
            return [checkRealPipelineVarDecl(varDecl, scope), false]
        }
        if (let Some(assignExpr) <- (node as AssignExpr)) {
            return [checkRealPipelineAssign(assignExpr, scope), false]
        }
        if (let Some(ret) <- (node as ReturnExpr)) {
            ret.refFuncBody = Some(body)
            return [checkRealPipelineReturn(ret, retTy, scope), true]
        }
        if (let Some(ifExpr) <- (node as IfExpr)) {
            return checkRealPipelineIf(ifExpr, body, retTy, scope)
        }
        if (let Some(whileExpr) <- (node as WhileExpr)) {
            return checkRealPipelineWhile(whileExpr, body, retTy, scope)
        }
        if (let Some(jumpExpr) <- (node as JumpExpr)) {
            return [checkRealPipelineJump(jumpExpr, scope), false]
        }
        if (let Some(callExpr) <- (node as CallExpr)) {
            if (checkRealPipelinePrintStmt(callExpr, scope)) {
                return [true, false]
            }
            return [checkRealPipelineExprStmt(callExpr, scope), false]
        }
        return [false, false]
    }

    private func checkRealPipelineExprStmt(expr: Expr, scope: RealPipelineScope): Bool {
        return typeRealPipelineExpr(expr, scope, None).isSome()
    }

    private func checkRealPipelineIf(
        ifExpr: IfExpr,
        body: FuncBody,
        retTy: Ty,
        scope: RealPipelineScope
    ): Array<Bool> {
        let cond = match (ifExpr.condExpr) {
            case Some(value) => value
            case None => return [false, false]
        }
        let condStatus = checkRealPipelineBoolCondition(cond, scope, "if")
        if (!condStatus[0]) {
            return [false, false]
        }
        if (!condStatus[1]) {
            return [true, false]
        }
        let thenBlock = match (ifExpr.thenBody) {
            case Some(value) => value
            case None => return [false, false]
        }
        let thenStatus = checkRealPipelineBlock(thenBlock, body, retTy, scope)
        if (!thenStatus[0]) {
            return [false, false]
        }
        var elseMustReturn = false
        if (let Some(elseExpr) <- ifExpr.elseBody) {
            if (let Some(elseBlock) <- (elseExpr as Block)) {
                let elseStatus = checkRealPipelineBlock(elseBlock, body, retTy, scope)
                if (!elseStatus[0]) {
                    return [false, false]
                }
                elseMustReturn = elseStatus[1]
            } else if (let Some(elseIf) <- (elseExpr as IfExpr)) {
                let elseStatus = checkRealPipelineIf(elseIf, body, retTy, scope)
                if (!elseStatus[0]) {
                    return [false, false]
                }
                elseMustReturn = elseStatus[1]
            } else {
                return [false, false]
            }
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        ifExpr.SetTy(if (thenStatus[1] && elseMustReturn) { TypeManager.GetNothingTy() } else { unitTy })
        return [true, thenStatus[1] && elseMustReturn]
    }

    private func checkRealPipelineWhile(
        whileExpr: WhileExpr,
        body: FuncBody,
        retTy: Ty,
        scope: RealPipelineScope
    ): Array<Bool> {
        let cond = match (whileExpr.condExpr) {
            case Some(value) => value
            case None => return [false, false]
        }
        let condStatus = checkRealPipelineBoolCondition(cond, scope, "while")
        if (!condStatus[0]) {
            return [false, false]
        }
        if (!condStatus[1]) {
            return [true, false]
        }
        let whileBody = match (whileExpr.body) {
            case Some(value) => value
            case None => return [false, false]
        }
        scope.EnterLoop()
        let bodyStatus = checkRealPipelineBlock(whileBody, body, retTy, scope)
        scope.ExitLoop()
        if (!bodyStatus[0]) {
            return [false, false]
        }
        whileExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return [true, false]
    }

    private func checkRealPipelineJump(jumpExpr: JumpExpr, scope: RealPipelineScope): Bool {
        if (!scope.InLoop()) {
            return false
        }
        jumpExpr.SetTy(TypeManager.GetNothingTy())
        return true
    }

    private func checkRealPipelineBoolCondition(expr: Expr, scope: RealPipelineScope, context: String): Array<Bool> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let condTy = match (typeRealPipelineExpr(expr, scope, Some(boolTy))) {
            case Some(value) => value
            case None => return [false, false]
        }
        if (!isRealPipelineBoolTy(condTy)) {
            emitRealPipelineTypeError(expr.begin,
                context + " condition must be Bool, got " + condTy.String())
            expr.SetTy(TypeManager.GetInvalidTy())
            return [true, false]
        }
        return [true, true]
    }

    private func checkRealPipelineVarDecl(varDecl: VarDecl, scope: RealPipelineScope): Bool {
        if (varDecl.isConst) {
            return false
        }
        let name = varDecl.identifier.Val()
        if (name.isEmpty()) {
            return false
        }
        if (scope.Contains(name)) {
            emitRealPipelineTypeError(varDecl.begin, "duplicate local binding '" + name + "'")
            varDecl.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let declaredTy: Option<Ty> = match (varDecl.typeNode) {
            case Some(typeNode) =>
                match (resolveRealPipelineLocalType(typeNode)) {
                    case Some(ty) =>
                        if (!isRealPipelineLocalTy(ty)) {
                            return false
                        }
                        Some(ty)
                    case None => return false
                }
            case None => None
        }
        let initializer = match (varDecl.initializer) {
            case Some(value) => value
            case None => return false
        }
        let initTy = match (typeRealPipelineExpr(initializer, scope, declaredTy)) {
            case Some(value) => value
            case None => return false
        }
        let localTy = match (declaredTy) {
            case Some(value) => value
            case None => initTy
        }
        varDecl.SetTy(localTy)
        if (let Some(typeNode) <- varDecl.typeNode) {
            typeNode.SetTy(localTy)
        }
        if (let Some(targetTy) <- declaredTy) {
            if (!isRealPipelineAssignable(targetTy, initTy)) {
                emitRealPipelineTypeError(initializer.begin,
                    initTy.String() + " initializer is not assignable to " + targetTy.String() + " local '" + name + "'")
                varDecl.SetTy(TypeManager.GetInvalidTy())
            }
        }
        let _ = scope.Add(name, localTy, varDecl.isVar)
        return true
    }

    private func checkRealPipelinePrintStmt(callExpr: CallExpr, scope: RealPipelineScope): Bool {
        let base = match (callExpr.baseFunc) {
            case Some(value) => value
            case None => return false
        }
        let calleeRef = match (base as RefExpr) {
            case Some(value) => value
            case None => return false
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return false
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName != "println" && calleeName != "print") {
            return false
        }
        if (scope.Contains(calleeName)) {
            return false
        }
        if (callExpr.args.size != 1) {
            emitRealPipelineTypeError(callExpr.begin, calleeName + " expects exactly one argument")
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let arg = callExpr.args[0]
        if (!arg.name.Empty() || arg.withInout) {
            return false
        }
        let argExpr = match (arg.expr) {
            case Some(value) => value
            case None => return false
        }
        let argTy = match (typeRealPipelineExpr(argExpr, scope, None)) {
            case Some(value) => value
            case None => return false
        }
        if (!isRealPipelinePrintableTy(argTy)) {
            emitRealPipelineTypeError(argExpr.begin,
                calleeName + " argument must be Int64, Bool, or String, got " + argTy.String())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        calleeRef.SetTy(unitTy)
        callExpr.SetTy(unitTy)
        return true
    }

    private func checkRealPipelineAssign(assignExpr: AssignExpr, scope: RealPipelineScope): Bool {
        if (assignExpr.op != TokenKind.ASSIGN) {
            return false
        }
        let left = match (assignExpr.leftValue) {
            case Some(value) => value
            case None => return false
        }
        if (let Some(member) <- (left as MemberAccess)) {
            return checkRealPipelineFieldAssign(assignExpr, member, scope)
        }
        let refExpr = match (left as RefExpr) {
            case Some(value) => value
            case None => return false
        }
        let name = refExpr.ref.identifier.Val()
        let local = match (scope.Get(name)) {
            case Some(value) => value
            case None =>
                if (let Some(result) <- checkRealPipelineImplicitFieldAssign(assignExpr, name, scope)) {
                    return result
                }
                emitRealPipelineTypeError(refExpr.begin, "undeclared local '" + name + "'")
                assignExpr.SetTy(TypeManager.GetInvalidTy())
                return true
        }
        if (!local.mutable) {
            emitRealPipelineTypeError(refExpr.begin, "cannot assign to immutable local '" + name + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let right = match (assignExpr.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(local.ty))) {
            case Some(value) => value
            case None => return false
        }
        if (!isRealPipelineAssignable(local.ty, rightTy)) {
            emitRealPipelineTypeError(right.begin,
                rightTy.String() + " assignment is not assignable to " + local.ty.String() + " local '" + name + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        assignExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return true
    }

    private func checkRealPipelineFieldAssign(assignExpr: AssignExpr, member: MemberAccess,
        scope: RealPipelineScope): Bool {
        if (!member.typeArguments.isEmpty()) {
            return false
        }
        let base = match (member.baseExpr) {
            case Some(value) => value
            case None => return false
        }
        let baseTy = match (typeRealPipelineExpr(base, scope, None)) {
            case Some(value) => value
            case None => return false
        }
        let info = match (realPipelineStructInfoForTy(baseTy)) {
            case Some(value) => value
            case None => return false
        }
        let fieldName = member.field.GetRawText()
        let fieldTy = match (info.FieldType(fieldName)) {
            case Some(value) => value
            case None =>
                emitRealPipelineTypeError(member.GetFieldPos(),
                    "unknown field '" + fieldName + "' on " + baseTy.String())
                assignExpr.SetTy(TypeManager.GetInvalidTy())
                return true
        }
        if (!info.FieldCanWrite(fieldName)) {
            emitRealPipelineTypeError(member.GetFieldPos(), "cannot assign to immutable field '" + fieldName + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        let right = match (assignExpr.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(fieldTy))) {
            case Some(value) => value
            case None => return false
        }
        if (!isRealPipelineAssignable(fieldTy, rightTy)) {
            emitRealPipelineTypeError(right.begin,
                rightTy.String() + " assignment is not assignable to field '" + fieldName +
                "' of type " + fieldTy.String())
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        assignExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return true
    }

    private func checkRealPipelineImplicitFieldAssign(assignExpr: AssignExpr, name: String,
        scope: RealPipelineScope): Option<Bool> {
        if (scope.thisStructName.isEmpty()) {
            return None
        }
        let info = match (realPipelineStructs.get(scope.thisStructName)) {
            case Some(value) => value
            case None => return None
        }
        let fieldTy = match (info.FieldType(name)) {
            case Some(value) => value
            case None => return None
        }
        if (!info.FieldCanWrite(name)) {
            emitRealPipelineTypeError(assignExpr.begin, "cannot assign to immutable field '" + name + "'")
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(true)
        }
        let right = match (assignExpr.rightExpr) {
            case Some(value) => value
            case None => return Some(false)
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(fieldTy))) {
            case Some(value) => value
            case None => return Some(false)
        }
        if (!isRealPipelineAssignable(fieldTy, rightTy)) {
            emitRealPipelineTypeError(right.begin,
                rightTy.String() + " assignment is not assignable to field '" + name +
                "' of type " + fieldTy.String())
            assignExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(true)
        }
        assignExpr.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT))
        return Some(true)
    }

    private func checkRealPipelineReturn(ret: ReturnExpr, retTy: Ty, scope: RealPipelineScope): Bool {
        if (let Some(expr) <- ret.expr) {
            let exprTy = match (typeRealPipelineExpr(expr, scope, Some(retTy))) {
                case Some(value) => value
                case None => return false
            }
            if (!isRealPipelineAssignable(retTy, exprTy)) {
                emitRealPipelineTypeError(expr.begin,
                    exprTy.String() + " expression is not assignable to " + retTy.String() + " return type")
                ret.SetTy(TypeManager.GetInvalidTy())
                return true
            }
            ret.SetTy(TypeManager.GetNothingTy())
            return true
        }
        if (retTy.kind != TypeKind.TYPE_UNIT) {
            emitRealPipelineTypeError(ret.begin, "return without value is not assignable to " + retTy.String())
            ret.SetTy(TypeManager.GetInvalidTy())
            return true
        }
        ret.SetTy(TypeManager.GetNothingTy())
        return true
    }

    private func typeRealPipelineExpr(expr: Expr, scope: RealPipelineScope, targetTy: Option<Ty>): Option<Ty> {
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            let inner = match (parenExpr.expr) {
                case Some(value) => value
                case None => return None
            }
            let innerTy = match (typeRealPipelineExpr(inner, scope, targetTy)) {
                case Some(value) => value
                case None => return None
            }
            parenExpr.SetTy(innerTy)
            return Some(innerTy)
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return typeRealPipelineLiteralExpr(lit, scope, targetTy)
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            let name = refExpr.ref.identifier.Val()
            let local = match (scope.Get(name)) {
                case Some(value) => value
                case None =>
                    if (let Some(fieldTy) <- realPipelineImplicitFieldType(name, scope)) {
                        refExpr.SetTy(fieldTy)
                        return Some(fieldTy)
                    }
                    emitRealPipelineTypeError(refExpr.begin, "undeclared local '" + name + "'")
                    refExpr.SetTy(TypeManager.GetInvalidTy())
                    return Some(TypeManager.GetInvalidTy())
            }
            refExpr.SetTy(local.ty)
            return Some(local.ty)
        }
        if (let Some(memberAccess) <- (expr as MemberAccess)) {
            return typeRealPipelineMemberAccessExpr(memberAccess, scope)
        }
        if (let Some(unaryExpr) <- (expr as UnaryExpr)) {
            return typeRealPipelineUnaryExpr(unaryExpr, scope)
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            return typeRealPipelineBinaryExpr(binaryExpr, scope)
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            return typeRealPipelineCallExpr(callExpr, scope)
        }
        return None
    }

    private func typeRealPipelineLiteralExpr(
        lit: LitConstExpr,
        scope: RealPipelineScope,
        targetTy: Option<Ty>
    ): Option<Ty> {
        var litTy: Ty = TypeManager.GetInvalidTy()
        if (lit.kind == LitConstKind.INTEGER) {
            litTy = match (targetTy) {
                case Some(ty) =>
                    if (ty.kind == TypeKind.TYPE_INT64) { ty } else { TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64) }
                case None => TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            }
        } else if (lit.kind == LitConstKind.BOOL) {
            litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        } else if (lit.kind == LitConstKind.UNIT) {
            litTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        } else if (lit.kind == LitConstKind.STRING) {
            if (lit.siExpr.isSome()) {
                return typeRealPipelineInterpolationLiteralExpr(lit, scope)
            } else {
                if (!isRealPipelinePlainStringLiteral(lit)) {
                    return None
                }
                litTy = TypeManager.GetCStringTy()
            }
        } else {
            return None
        }
        lit.SetTy(litTy)
        return Some(litTy)
    }

    private func typeRealPipelineUnaryExpr(unaryExpr: UnaryExpr, scope: RealPipelineScope): Option<Ty> {
        let operand = match (unaryExpr.expr) {
            case Some(value) => value
            case None => return None
        }
        if (unaryExpr.op == TokenKind.SUB) {
            let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            let operandTy = match (typeRealPipelineExpr(operand, scope, Some(intTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineInt64Ty(operandTy)) {
                emitRealPipelineTypeError(operand.begin, "unary '-' requires Int64 operand, got " + operandTy.String())
                unaryExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            unaryExpr.SetTy(intTy)
            return Some(intTy)
        }
        if (unaryExpr.op == TokenKind.NOT) {
            let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
            let operandTy = match (typeRealPipelineExpr(operand, scope, Some(boolTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineBoolTy(operandTy)) {
                emitRealPipelineTypeError(operand.begin, "unary '!' requires Bool operand, got " + operandTy.String())
                unaryExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            unaryExpr.SetTy(boolTy)
            return Some(boolTy)
        }
        return None
    }

    private func typeRealPipelineBinaryExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        if (binaryExpr.op == TokenKind.ADD && realPipelineBinaryWouldUseString(binaryExpr, scope)) {
            return typeRealPipelineStringConcatExpr(binaryExpr, scope)
        }
        if (realPipelineBinaryWouldUseString(binaryExpr, scope)) {
            return None
        }
        if (isRealPipelineArithmeticOp(binaryExpr.op)) {
            return typeRealPipelineIntBinaryExpr(binaryExpr, scope, resultIsBool: false)
        }
        if (isRealPipelineOrderingOp(binaryExpr.op)) {
            return typeRealPipelineIntBinaryExpr(binaryExpr, scope, resultIsBool: true)
        }
        if (binaryExpr.op == TokenKind.EQUAL || binaryExpr.op == TokenKind.NOTEQ) {
            return typeRealPipelineEqualityExpr(binaryExpr, scope)
        }
        if (binaryExpr.op == TokenKind.AND || binaryExpr.op == TokenKind.OR) {
            return typeRealPipelineBoolBinaryExpr(binaryExpr, scope)
        }
        return None
    }

    private func typeRealPipelineMemberAccessExpr(memberAccess: MemberAccess,
        scope: RealPipelineScope): Option<Ty> {
        if (!memberAccess.typeArguments.isEmpty()) {
            return None
        }
        let base = match (memberAccess.baseExpr) {
            case Some(value) => value
            case None => return None
        }
        let baseTy = match (typeRealPipelineExpr(base, scope, None)) {
            case Some(value) => value
            case None => return None
        }
        let info = match (realPipelineStructInfoForTy(baseTy)) {
            case Some(value) => value
            case None => return None
        }
        let fieldName = memberAccess.field.GetRawText()
        let fieldTy = match (info.FieldType(fieldName)) {
            case Some(value) => value
            case None =>
                emitRealPipelineTypeError(memberAccess.GetFieldPos(),
                    "unknown field '" + fieldName + "' on " + baseTy.String())
                memberAccess.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
        }
        memberAccess.SetTy(fieldTy)
        return Some(fieldTy)
    }

    private func typeRealPipelineCallExpr(callExpr: CallExpr, scope: RealPipelineScope): Option<Ty> {
        let base = match (callExpr.baseFunc) {
            case Some(value) => value
            case None => return None
        }
        if (let Some(memberAccess) <- (base as MemberAccess)) {
            return typeRealPipelineMethodCallExpr(callExpr, memberAccess, scope)
        }
        let calleeRef = match (base as RefExpr) {
            case Some(value) => value
            case None => return None
        }
        if (!calleeRef.typeArguments.isEmpty()) {
            return None
        }
        let calleeName = calleeRef.ref.identifier.Val()
        if (calleeName == "println" || calleeName == "print") {
            return None
        }
        if (calleeName.isEmpty() || scope.Contains(calleeName)) {
            return None
        }
        if (let Some(structInfo) <- realPipelineStructs.get(calleeName)) {
            return typeRealPipelineStructConstruction(callExpr, calleeRef, structInfo, scope)
        }
        if (!realPipelineDeclaredFunctions.contains(calleeName)) {
            if (realPipelineUnsupported) {
                return None
            }
            emitRealPipelineTypeError(callExpr.begin, "unknown top-level function '" + calleeName + "'")
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        if (realPipelineUnsupportedFunctions.contains(calleeName)) {
            return None
        }
        let funcTy = match (realPipelineFunctionTypes.get(calleeName)) {
            case Some(value) => value
            case None => return None
        }
        if (callExpr.args.size != funcTy.paramTys.size) {
            emitRealPipelineTypeError(callExpr.begin,
                "function '" + calleeName + "' expects " + funcTy.paramTys.size.toString() +
                " argument(s), got " + callExpr.args.size.toString())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        var idx: Int64 = 0
        while (idx < callExpr.args.size) {
            let arg = callExpr.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let paramTy = funcTy.paramTys[idx]
            if (!isRealPipelineValueTy(paramTy)) {
                return None
            }
            let argTy = match (typeRealPipelineExpr(argExpr, scope, Some(paramTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineAssignable(paramTy, argTy)) {
                emitRealPipelineTypeError(argExpr.begin,
                    argTy.String() + " argument is not assignable to " + paramTy.String() +
                    " parameter " + idx.toString() + " of function '" + calleeName + "'")
                callExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            idx++
        }
        if (let Some(funcDecl) <- realPipelineFunctionDecls.get(calleeName)) {
            calleeRef.ref.target = Some(funcDecl)
            callExpr.resolvedFunction = Some(funcDecl)
            callExpr.callKind = CallKind.CALL_DECLARED_FUNCTION
        }
        calleeRef.SetTy(funcTy)
        callExpr.SetTy(funcTy.retTy)
        return Some(funcTy.retTy)
    }

    private func typeRealPipelineStructConstruction(callExpr: CallExpr, calleeRef: RefExpr,
        structInfo: RealPipelineStructInfo, scope: RealPipelineScope): Option<Ty> {
        if (callExpr.args.size != structInfo.initParamTypes.size) {
            emitRealPipelineTypeError(callExpr.begin,
                "constructor '" + structInfo.name + "' expects " + structInfo.initParamTypes.size.toString() +
                " argument(s), got " + callExpr.args.size.toString())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        var idx: Int64 = 0
        while (idx < callExpr.args.size) {
            let arg = callExpr.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let paramTy = structInfo.initParamTypes[idx]
            let argTy = match (typeRealPipelineExpr(argExpr, scope, Some(paramTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineAssignable(paramTy, argTy)) {
                emitRealPipelineTypeError(argExpr.begin,
                    argTy.String() + " argument is not assignable to " + paramTy.String() +
                    " constructor parameter " + idx.toString() + " of struct '" + structInfo.name + "'")
                callExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            idx++
        }
        calleeRef.ref.target = Some(structInfo.decl)
        calleeRef.SetTy(structInfo.ty)
        callExpr.SetTy(structInfo.ty)
        return Some(structInfo.ty)
    }

    private func typeRealPipelineMethodCallExpr(callExpr: CallExpr, memberAccess: MemberAccess,
        scope: RealPipelineScope): Option<Ty> {
        if (!memberAccess.typeArguments.isEmpty()) {
            return None
        }
        let receiverExpr = match (memberAccess.baseExpr) {
            case Some(value) => value
            case None => return None
        }
        let receiverTy = match (typeRealPipelineExpr(receiverExpr, scope, None)) {
            case Some(value) => value
            case None => return None
        }
        let structInfo = match (realPipelineStructInfoForTy(receiverTy)) {
            case Some(value) => value
            case None => return None
        }
        let methodName = memberAccess.field.GetRawText()
        let methodTy = match (structInfo.methods.get(methodName)) {
            case Some(value) => value
            case None =>
                emitRealPipelineTypeError(memberAccess.GetFieldPos(),
                    "unknown method '" + methodName + "' on " + receiverTy.String())
                callExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
        }
        if (callExpr.args.size != methodTy.paramTys.size) {
            emitRealPipelineTypeError(callExpr.begin,
                "method '" + methodName + "' expects " + methodTy.paramTys.size.toString() +
                " argument(s), got " + callExpr.args.size.toString())
            callExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        var idx: Int64 = 0
        while (idx < callExpr.args.size) {
            let arg = callExpr.args[idx]
            if (!arg.name.Empty() || arg.withInout) {
                return None
            }
            let argExpr = match (arg.expr) {
                case Some(value) => value
                case None => return None
            }
            let paramTy = methodTy.paramTys[idx]
            let argTy = match (typeRealPipelineExpr(argExpr, scope, Some(paramTy))) {
                case Some(value) => value
                case None => return None
            }
            if (!isRealPipelineAssignable(paramTy, argTy)) {
                emitRealPipelineTypeError(argExpr.begin,
                    argTy.String() + " argument is not assignable to " + paramTy.String() +
                    " parameter " + idx.toString() + " of method '" + methodName + "'")
                callExpr.SetTy(TypeManager.GetInvalidTy())
                return Some(TypeManager.GetInvalidTy())
            }
            idx++
        }
        if (let Some(methodDecl) <- structInfo.methodDecls.get(methodName)) {
            memberAccess.target = Some(methodDecl)
            memberAccess.targets.add(methodDecl)
            callExpr.resolvedFunction = Some(methodDecl)
        }
        memberAccess.SetTy(methodTy)
        callExpr.SetTy(methodTy.retTy)
        return Some(methodTy.retTy)
    }

    private func typeRealPipelineStringConcatExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        let stringTy = TypeManager.GetCStringTy()
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, Some(stringTy))) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(stringTy))) {
            case Some(value) => value
            case None => return None
        }
        if (!isRealPipelineStringTy(leftTy) || !isRealPipelineStringTy(rightTy)) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '+' requires String operands when concatenating String values")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        binaryExpr.SetTy(stringTy)
        return Some(stringTy)
    }

    private func typeRealPipelineIntBinaryExpr(
        binaryExpr: BinaryExpr,
        scope: RealPipelineScope,
        resultIsBool!: Bool
    ): Option<Ty> {
        let intTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, Some(intTy))) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(intTy))) {
            case Some(value) => value
            case None => return None
        }
        if (!isRealPipelineInt64Ty(leftTy) || !isRealPipelineInt64Ty(rightTy)) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires Int64 operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        let resultTy = if (resultIsBool) { boolTy } else { intTy }
        binaryExpr.SetTy(resultTy)
        return Some(resultTy)
    }

    private func typeRealPipelineEqualityExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, None)) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(leftTy))) {
            case Some(value) => value
            case None => return None
        }
        let comparable = (isRealPipelineInt64Ty(leftTy) && isRealPipelineInt64Ty(rightTy)) ||
            (isRealPipelineBoolTy(leftTy) && isRealPipelineBoolTy(rightTy))
        if (!comparable) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires matching Int64 or Bool operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        binaryExpr.SetTy(boolTy)
        return Some(boolTy)
    }

    private func typeRealPipelineBoolBinaryExpr(binaryExpr: BinaryExpr, scope: RealPipelineScope): Option<Ty> {
        let boolTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return None
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return None
        }
        let leftTy = match (typeRealPipelineExpr(left, scope, Some(boolTy))) {
            case Some(value) => value
            case None => return None
        }
        let rightTy = match (typeRealPipelineExpr(right, scope, Some(boolTy))) {
            case Some(value) => value
            case None => return None
        }
        if (!isRealPipelineBoolTy(leftTy) || !isRealPipelineBoolTy(rightTy)) {
            emitRealPipelineTypeError(binaryExpr.begin,
                "operator '" + TokenKindText(binaryExpr.op) + "' requires Bool operands")
            binaryExpr.SetTy(TypeManager.GetInvalidTy())
            return Some(TypeManager.GetInvalidTy())
        }
        binaryExpr.SetTy(boolTy)
        return Some(boolTy)
    }

    private func isRealPipelineArithmeticOp(op: TokenKind): Bool {
        return op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL ||
            op == TokenKind.DIV || op == TokenKind.MOD
    }

    private func isRealPipelineOrderingOp(op: TokenKind): Bool {
        return op == TokenKind.LT || op == TokenKind.LE || op == TokenKind.GT || op == TokenKind.GE
    }

    private func isRealPipelineValueTy(ty: Ty): Bool {
        return isRealPipelineInt64Ty(ty) || isRealPipelineBoolTy(ty) || isRealPipelineStringTy(ty) ||
            isRealPipelineStructTy(ty)
    }

    private func isRealPipelineLocalTy(ty: Ty): Bool {
        return isRealPipelineValueTy(ty) || isRealPipelineStringTy(ty)
    }

    private func isRealPipelinePrintableTy(ty: Ty): Bool {
        return isRealPipelineLocalTy(ty)
    }

    private func isRealPipelineReturnTy(ty: Ty): Bool {
        return isRealPipelineValueTy(ty) || ty.kind == TypeKind.TYPE_UNIT
    }

    private func isRealPipelineInt64Ty(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_INT64
    }

    private func isRealPipelineBoolTy(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_BOOLEAN
    }

    private func isRealPipelineStringTy(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_CSTRING
    }

    private func isRealPipelineStructTy(ty: Ty): Bool {
        return !ty.HasInvalidTy() && ty.kind == TypeKind.TYPE_STRUCT
    }

    private func isRealPipelineAssignable(targetTy: Ty, exprTy: Ty): Bool {
        if (exprTy.HasInvalidTy() || targetTy.HasInvalidTy()) {
            return false
        }
        if (isRealPipelineStructTy(targetTy) || isRealPipelineStructTy(exprTy)) {
            return isRealPipelineStructTy(targetTy) && isRealPipelineStructTy(exprTy) &&
                targetTy.String() == exprTy.String()
        }
        if (targetTy.kind == exprTy.kind) {
            return true
        }
        return tm.CheckTypeCompatibility(targetTy, exprTy) != TypeCompatibility.INCOMPATIBLE
    }

    private func realPipelineBodyHasValueReturn(body: FuncBody): Bool {
        if (let Some(block) <- body.body) {
            return realPipelineBlockHasValueReturn(block)
        }
        return false
    }

    private func realPipelineBlockHasValueReturn(block: Block): Bool {
        for (node in block.body) {
            if (realPipelineNodeHasValueReturn(node)) {
                return true
            }
        }
        return false
    }

    private func realPipelineNodeHasValueReturn(node: Node): Bool {
        if (let Some(ret) <- (node as ReturnExpr)) {
            return ret.expr.isSome()
        }
        if (let Some(ifExpr) <- (node as IfExpr)) {
            if (let Some(thenBlock) <- ifExpr.thenBody) {
                if (realPipelineBlockHasValueReturn(thenBlock)) {
                    return true
                }
            }
            if (let Some(elseExpr) <- ifExpr.elseBody) {
                if (let Some(elseBlock) <- (elseExpr as Block)) {
                    return realPipelineBlockHasValueReturn(elseBlock)
                }
                if (realPipelineNodeHasValueReturn(elseExpr)) {
                    return true
                }
            }
        }
        if (let Some(whileExpr) <- (node as WhileExpr)) {
            if (let Some(bodyBlock) <- whileExpr.body) {
                return realPipelineBlockHasValueReturn(bodyBlock)
            }
        }
        return false
    }

    private func resolveRealPipelineLocalType(typeNode: Type): Option<Ty> {
        if (let Some(ty) <- resolveRealPipelinePrimitiveType(typeNode)) {
            return Some(ty)
        }
        let text = typeNode.ToString().trimAscii()
        if (text == "String" || text == "CString") {
            let ty = TypeManager.GetCStringTy()
            typeNode.SetTy(ty)
            return Some(ty)
        }
        if (let Some(info) <- realPipelineStructs.get(text)) {
            typeNode.SetTy(info.ty)
            return Some(info.ty)
        }
        return None
    }

    private func resolveRealPipelineStoredFieldType(typeNode: Type): Option<Ty> {
        if (let Some(ty) <- resolveRealPipelinePrimitiveType(typeNode)) {
            if (isRealPipelineInt64Ty(ty) || isRealPipelineBoolTy(ty)) {
                return Some(ty)
            }
            return None
        }
        let text = typeNode.ToString().trimAscii()
        if (text == "String" || text == "CString") {
            let ty = TypeManager.GetCStringTy()
            typeNode.SetTy(ty)
            return Some(ty)
        }
        return None
    }

    private func realPipelineStructInfoForTy(ty: Ty): Option<RealPipelineStructInfo> {
        if (!isRealPipelineStructTy(ty)) {
            return None
        }
        for ((_, info) in realPipelineStructs) {
            if (info.ty.String() == ty.String()) {
                return Some(info)
            }
        }
        return None
    }

    private func realPipelineImplicitFieldType(name: String, scope: RealPipelineScope): Option<Ty> {
        if (scope.thisStructName.isEmpty() || scope.Contains(name)) {
            return None
        }
        let info = match (realPipelineStructs.get(scope.thisStructName)) {
            case Some(value) => value
            case None => return None
        }
        return info.FieldType(name)
    }

    private func realPipelineFieldNameFromThisTarget(expr: Expr): Option<String> {
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (!refExpr.typeArguments.isEmpty()) {
                return None
            }
            return Some(refExpr.ref.identifier.Val())
        }
        if (let Some(member) <- (expr as MemberAccess)) {
            if (!member.typeArguments.isEmpty()) {
                return None
            }
            let base = match (member.baseExpr) {
                case Some(value) => value
                case None => return None
            }
            let baseRef = match (base as RefExpr) {
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

    private func isRealPipelinePlainStringLiteral(lit: LitConstExpr): Bool {
        if (lit.kind != LitConstKind.STRING || lit.siExpr.isSome()) {
            return false
        }
        let text = lit.stringValue
        var idx: Int64 = 0
        while (idx < text.size) {
            if (text[idx] == b'\\') {
                return false
            }
            idx++
        }
        return true
    }

    private func typeRealPipelineInterpolationLiteralExpr(lit: LitConstExpr, scope: RealPipelineScope): Option<Ty> {
        let stringTy = TypeManager.GetCStringTy()
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
            if (part.strKind == StringPartKind.STR) {
                if (!isRealPipelinePlainInterpolationText(part.value)) {
                    return None
                }
                partExpr.SetTy(stringTy)
            } else {
                let inner = match (realPipelineInterpolationInnerExpr(partExpr)) {
                    case Some(value) => value
                    case None => return None
                }
                let innerTy = match (typeRealPipelineExpr(inner, scope, None)) {
                    case Some(value) => value
                    case None => return None
                }
                if (!isRealPipelinePrintableTy(innerTy)) {
                    emitRealPipelineTypeError(inner.begin,
                        "string interpolation supports Int64, Bool, or String expressions, got " +
                        innerTy.String())
                    lit.SetTy(TypeManager.GetInvalidTy())
                    return Some(TypeManager.GetInvalidTy())
                }
                partExpr.SetTy(stringTy)
            }
            idx++
        }
        si.SetTy(stringTy)
        lit.SetTy(stringTy)
        return Some(stringTy)
    }

    private func realPipelineInterpolationInnerExpr(partExpr: Expr): Option<Expr> {
        let interp = match (partExpr as InterpolationExpr) {
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
        return block.body[0] as Expr
    }

    private func isRealPipelinePlainInterpolationText(text: String): Bool {
        var idx: Int64 = 0
        while (idx < text.size) {
            if (text[idx] == b'\\') {
                return false
            }
            idx++
        }
        return true
    }

    private func realPipelineBinaryWouldUseString(binaryExpr: BinaryExpr, scope: RealPipelineScope): Bool {
        let left = match (binaryExpr.leftExpr) {
            case Some(value) => value
            case None => return false
        }
        let right = match (binaryExpr.rightExpr) {
            case Some(value) => value
            case None => return false
        }
        return realPipelineExprCouldBeString(left, scope) || realPipelineExprCouldBeString(right, scope)
    }

    private func realPipelineExprCouldBeString(expr: Expr, scope: RealPipelineScope): Bool {
        if (let Some(parenExpr) <- (expr as ParenExpr)) {
            if (let Some(inner) <- parenExpr.expr) {
                return realPipelineExprCouldBeString(inner, scope)
            }
            return false
        }
        if (let Some(lit) <- (expr as LitConstExpr)) {
            return lit.kind == LitConstKind.STRING
        }
        if (let Some(refExpr) <- (expr as RefExpr)) {
            if (let Some(local) <- scope.Get(refExpr.ref.identifier.Val())) {
                return isRealPipelineStringTy(local.ty)
            }
            return false
        }
        if (let Some(binaryExpr) <- (expr as BinaryExpr)) {
            if (binaryExpr.op == TokenKind.ADD) {
                return realPipelineBinaryWouldUseString(binaryExpr, scope)
            }
        }
        if (let Some(callExpr) <- (expr as CallExpr)) {
            let base = match (callExpr.baseFunc) {
                case Some(value) => value
                case None => return false
            }
            let calleeRef = match (base as RefExpr) {
                case Some(value) => value
                case None => return false
            }
            let calleeName = calleeRef.ref.identifier.Val()
            if (let Some(funcTy) <- realPipelineFunctionTypes.get(calleeName)) {
                return isRealPipelineStringTy(funcTy.retTy)
            }
        }
        return false
    }

    private func markRealPipelineUnsupported(): Unit {
        realPipelineUnsupported = true
    }

    private func emitRealPipelineTypeError(position: Position, message: String): Unit {
        realPipelineDiagnostics.add(RealSemaDiagnostic(position, message))
    }
}
