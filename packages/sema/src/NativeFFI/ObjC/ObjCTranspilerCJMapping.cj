package cjcj::sema.NativeFFI.ObjC

import std.collection.*
import cjcj::ast.*
import cjcj::basic.Warningln
import cjcj::sema.TypeManager
import cjcj::sema.NativeFFI.{CreateType, GenericConfigInfo, GetActualTypeKind, GetCangjieLibName,
    GetForeignNameAnnotation, GetGenericActualType, IsGenericParam, IsVisibalFunc}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, FileUtil, InternalError,
    OCOBJECT_NAME, OBJECT_NAME}

private let INTERFACE_KEYWORD: String = "@interface"
private let IMPORT_KEYWORD: String = "#import"
private let PROPERTY_KEYWORD: String = "@property"
private let END_KEYWORD: String = "@end"
private let IMPL_KEYWORD: String = "@implementation"
private let RETURN_KEYWORD: String = "return"
private let SUPER_KEYWORD: String = "super"
private let CLASS_KEYWORD: String = "class"
private let CLASS_FWD_KEYWORD: String = "@class"
private let PROTOCOL_KEYWORD: String = "@protocol"
private let SETTER_KEYWORD: String = "setter="
private let GETTER_KEYWORD: String = "getter="

private let FOUNDATION_IMPORT: String = "<Foundation/Foundation.h>"
private let STDDEF_IMPORT: String = "<stddef.h>"
private let STDLIB_IMPORT: String = "<stdlib.h>"

private let READWRITE_MODIFIER: String = "readwrite"
private let READONLY_MODIFIER: String = "readonly"
private let STATIC_FUNC_MODIFIER: String = "+"
private let INSTANCE_MODIFIER: String = "-"
private let EXTERN_MODIFIER: String = "extern"
private let FINAL_MODIFIER: String = "__attribute__((objc_subclassing_restricted))"

private let VOID_TYPE_CJ_MAPPING: String = "void"
private let BOOL_TYPE: String = "bool"
private let CONST_CHAR_POINTER_TYPE: String = "const char*"
private let VOID_POINTER_TYPE_CJ_MAPPING: String = "void*"
private let ID_TYPE_CJ_MAPPING: String = "id"
private let UNSUPPORTED_TYPE_CJ_MAPPING: String = "UNSUPPORTED_TYPE"
private let INT64_T_CJ_MAPPING: String = "int64_t"

private let SELF_WEAKLINK_NAME: String = "$registryId"
private let INITED_FROM_OBJC_NAME: String = "$initedFromObjC"
private let SELF_NAME_CJ_MAPPING: String = "self"
private let SETTER_PARAM_NAME_CJ_MAPPING: String = "value"
private let REGISTRY_ID_PARAM_NAME: String = "registryId"
private let TMP_REG_ID: String = "regId"

private let INITIALIZE_FUNC_NAME: String = "initialize"
private let INIT_FUNC_NAME: String = "init"
private let RETAIN_FUNC_NAME: String = "retain"
private let DELETE_FUNC_NAME: String = "deleteCJObject"
private let DEALLOC_FUNC_NAME: String = "dealloc"
private let INIT_CJ_RUNTIME_NAME: String = "initCJRuntime"
private let INIT_WITH_REGISTRY_ID_NAME: String = "initWithRegistryId"
private let INIT_WITH_REGISTRY_ID_SIGNATURE: String = "- (id)initWithRegistryId:(int64_t)registryId"
private let REINIT_WITH_REGISTRY_ID_SIGNATURE: String = "- (id)reinitWithRegistryId:(int64_t)registryId"
private let RELEASE_SIGNATURE: String = "- (oneway void)release"
private let EXIT_FUNC_NAME: String = "exit"
private let CAST_TO_VOID_PTR_CJ_MAPPING: String = "(__bridge void*)"
private let CAST_TO_VOID_PTR_RETAINED_CJ_MAPPING: String = "(__bridge_retained void*)"
private let CAST_TO_VOID_PTR_UNSAFE_CJ_MAPPING: String = "(void*)"

private let EQ_OP: String = "="
private let EQ_CHECK_OP: String = "=="
private let FALSE_KW: String = "false"
private let NIL_KW: String = "nil"
private let FAIL_CALL_UNINIT_CTOR: String = "[self doesNotRecognizeSelector:_cmd];"
private let FAIL_CALL_CANGJIE_BEFORE_INIT: String =
    "[NSException raise: @\"Use before Cangjie counterpart is initialized\" format: " +
    "@\"selector `%@` is overriden in Cangjie and cannot be used before Cangjie counterpart " +
    "is initialized\", NSStringFromSelector(_cmd)];"
private let REGISTRY_ID_UNINIT_VALUE: String = "-1"
private let INDENT_SIZE: Int64 = 4
private let DEFAULT_OUTPUT_DIR_WARNING_CJ_MAPPING: String =
    "default value objc-gen of Objective-C generated sources directory will be changed in next Cangjie SDK release"
private let DEFAULT_OUTPUT_DIR_CJ_MAPPING: String = "objc-gen"

// C++ ObjCTranspilerCJMapping.cpp:82-87 variadic stream helper. Cangjie has no parameter packs;
// callers convert the same streamable operands to strings before passing this ordered array.
private func Join(args: Array<String>): String {
    let result = StringBuilder()
    for (arg in args) {
        result.append(arg)
    }
    return result.toString()
}

// C++ ObjCTranspilerCJMapping.cpp:99-106.
public func ToDecl(fType: ObjCFunctionType): String {
    if (let ObjCFunctionType.STATIC <- fType) {
        return STATIC_FUNC_MODIFIER
    }
    return INSTANCE_MODIFIER
}

// C++ ObjCTranspilerCJMapping.h:30-128 and ObjCTranspilerCJMapping.cpp:108-1503.
public class ObjCTranspilerCJMapping {
    private var resPreamble: String = ""
    private var res: String = ""
    private var resSource: String = ""
    private let typedefs = HashSet<String>()
    private let outputFilePath: String
    private let cjLibOutputPath: String
    private var currentBlockIndent: Int64 = 0
    private let decl: Decl
    private let ctx: InteropContext
    private let interopType: InteropType
    private var buffer = StringBuilder()
    private let genericConfig: Option<GenericConfigInfo>
    private let isGenericGlueCode: Bool

    // C++ ObjCTranspilerCJMapping.cpp:108-121.
    public init(ctx: InteropContext, declArg: Decl, outputFilePath: String,
        cjLibOutputPath: String, interopType: InteropType) {
        this.ctx = ctx
        this.decl = declArg
        this.outputFilePath = if (outputFilePath.isEmpty()) { DEFAULT_OUTPUT_DIR_CJ_MAPPING } else { outputFilePath }
        this.cjLibOutputPath = cjLibOutputPath
        this.interopType = interopType
        this.genericConfig = None
        this.isGenericGlueCode = false
        if (outputFilePath.isEmpty()) {
            Warningln(DEFAULT_OUTPUT_DIR_WARNING_CJ_MAPPING)
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:123-139.
    public init(ctx: InteropContext, declArg: Decl, outputFilePath: String,
        cjLibOutputPath: String, interopType: InteropType, genericConfig: GenericConfigInfo,
        isGenericGlueCode: Bool) {
        this.ctx = ctx
        this.decl = declArg
        this.outputFilePath = if (outputFilePath.isEmpty()) { DEFAULT_OUTPUT_DIR_CJ_MAPPING } else { outputFilePath }
        this.cjLibOutputPath = cjLibOutputPath
        this.interopType = interopType
        this.genericConfig = Some(genericConfig)
        this.isGenericGlueCode = isGenericGlueCode
        if (outputFilePath.isEmpty()) {
            Warningln(DEFAULT_OUTPUT_DIR_WARNING_CJ_MAPPING)
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:173-207.
    public func Generate(): Unit {
        if (let InteropType.CJ_Mapping_Interface <- interopType) {
            GenerateProtocolDecl()
            return
        }
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return
        }
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        GenerateImports(objCDeclName)
        GenerateForwardDeclarations()
        GenerateExternalDeclarations4CJMapping()
        GenerateExternalDeclarations()
        GenerateInterfaceDecl()
        AddConstructors()
        GenerateInitializer(objCDeclName)
        AddProperties()
        AddMethods()
        GenerateDeleteObject()
        GenerateDealloc()
        AddWithIndent(END_KEYWORD, target: GenerationTarget.BOTH)
        InsertTypedefsToPreamble()
        InsertPreambleInHeaderFront()
        WriteToFile()
    }

    // C++ ObjCTranspilerCJMapping.cpp:210-220.
    private func IsNotThisActualTyFunc(declPtr: Decl): Bool {
        if (let Some(config) <- genericConfig) {
            if (!declPtr.identifier.Val().contains(config.declInstName)) {
                return true
            }
        }
        return false
    }

    // C++ ObjCTranspilerCJMapping.cpp:223-227.
    private func OpenBlock(): Unit {
        resSource += " {"
        currentBlockIndent += INDENT_SIZE
    }

    // C++ ObjCTranspilerCJMapping.cpp:228-233.
    private func CloseBlock(newLineBefore!: Bool = false, newLineAfter!: Bool = false): Unit {
        currentBlockIndent -= INDENT_SIZE
        if (newLineBefore) {
            resSource += "\n"
        }
        for (_ in 0..currentBlockIndent) {
            resSource += " "
        }
        resSource += "}"
        if (newLineAfter) {
            resSource += "\n"
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:234-255.
    private func AddWithIndent(s: String, target!: GenerationTarget = GenerationTarget.HEADER,
        bOp!: OptionalBlockOp = OptionalBlockOp.NONE): Unit {
        if ((let GenerationTarget.HEADER <- target) || (let GenerationTarget.BOTH <- target)) {
            res += s
            if (let OptionalBlockOp.OPEN <- bOp) {
                res += ";"
            }
            res += "\n"
        }
        if ((let GenerationTarget.SOURCE <- target) || (let GenerationTarget.BOTH <- target)) {
            for (_ in 0..currentBlockIndent) {
                resSource += " "
            }
            resSource += s
            if (let OptionalBlockOp.OPEN <- bOp) {
                OpenBlock()
            }
            if (let OptionalBlockOp.CLOSE <- bOp) {
                CloseBlock(newLineBefore: true)
            }
            resSource += "\n"
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:257-260.
    private func AddToPreamble(s: String): Unit {
        resPreamble += s + "\n"
    }

    // C++ ObjCTranspilerCJMapping.cpp:267-270.
    private func GenerateReturn(statement: String): String {
        return RETURN_KEYWORD + " " + statement + ";"
    }

    // C++ ObjCTranspilerCJMapping.cpp:276-279.
    private func GenerateAssignment(lhs: String, rhs: String): String {
        return lhs + " = " + rhs
    }

    // C++ ObjCTranspilerCJMapping.cpp:285-289.
    private func GenerateIfStatement(lhs: String, rhs: String, op: String): String {
        return "if (" + lhs + " " + op + " " + rhs + ")"
    }

    // C++ ObjCTranspilerCJMapping.cpp:296-299.
    private func GenerateObjCCall(lhs: String, rhs: String): String {
        return "[" + lhs + " " + rhs + "]"
    }

    // C++ ObjCTranspilerCJMapping.cpp:305-320.
    private func GenerateCCall(funcName: String, args!: Array<String> = []): String {
        var result = funcName + "("
        for (idx in 0..args.size) {
            result += args[idx]
            if (idx + 1 < args.size) {
                result += ", "
            }
        }
        result += ")"
        return result
    }

    // C++ ObjCTranspilerCJMapping.cpp:322-329.
    private func WrapperCallByInitForCJMappingReturn(retTy: Ty, nativeCall: String): String {
        let retName = if (isGenericGlueCode) { genericConfig.getOrThrow().declInstName } else { retTy.name }
        return "[[" + retName + " alloc]" + INIT_WITH_REGISTRY_ID_NAME + ": " + nativeCall + "]"
    }

    // C++ ObjCTranspilerCJMapping.cpp:335-360.
    private func GenerateDefaultFunctionImplementation(name: String, retTy: Ty,
        args!: ArgsList = ArgsList(), `type`!: ObjCFunctionType = ObjCFunctionType.INSTANCE): String {
        var result = if (retTy.IsUnit()) { "" } else { RETURN_KEYWORD }
        result += " "
        var nativeCall = ""
        if ((TypeMapper.IsObjCObjectType(retTy) || TypeMapper.IsObjCBlock(retTy)) &&
            !TypeMapper.IsObjCCJMapping(retTy)) {
            nativeCall += "(__bridge_transfer " + MapCJTypeToObjCType(retTy) + ")"
        }
        nativeCall += name + "("
        for (idx in 0..args.size) {
            nativeCall += args[idx][1]
            if (idx + 1 < args.size) {
                nativeCall += ", "
            }
        }
        nativeCall += ")"
        result += if (TypeMapper.IsObjCCJMapping(retTy)) {
            WrapperCallByInitForCJMappingReturn(retTy, nativeCall)
        } else {
            nativeCall
        }
        result += ";"
        return result
    }

    // C++ ObjCTranspilerCJMapping.cpp:366-375.
    private func GenerateFunctionDeclaration(`type`: ObjCFunctionType, returnType: String,
        name: String): String {
        return ToDecl(`type`) + " (" + returnType + ")" + name
    }

    // C++ ObjCTranspilerCJMapping.cpp:382-420.
    private func GeneratePropertyDeclaration(staticType: ObjCFunctionType, mode: String,
        `type`: String, name: String, getterName: String, setterName: String): String {
        if (name.isEmpty() || `type`.isEmpty()) {
            return ""
        }
        var result = PROPERTY_KEYWORD + " ("
        if (let ObjCFunctionType.STATIC <- staticType) {
            result += CLASS_KEYWORD + ", "
        }
        if (!mode.isEmpty()) {
            result += mode
        }
        if (name != SELF_WEAKLINK_NAME) {
            result += ", " + GETTER_KEYWORD + getterName
            if (mode == READWRITE_MODIFIER) {
                result += ", " + SETTER_KEYWORD + setterName
            }
        }
        result += ") " + `type` + " " + name + ";"
        return result
    }

    // C++ ObjCTranspilerCJMapping.cpp:426-429.
    private func GenerateImport(name: String): String {
        return IMPORT_KEYWORD + " " + name
    }

    // C++ ObjCTranspilerCJMapping.cpp:431-442.
    private func GenerateImports(objCDeclName: String): Unit {
        AddToPreamble(GenerateImport(FOUNDATION_IMPORT))
        AddToPreamble(GenerateImport(STDDEF_IMPORT))
        AddWithIndent(GenerateImport("\"" + objCDeclName + ".h\""), target: GenerationTarget.SOURCE)
        AddWithIndent(GenerateImport(STDLIB_IMPORT), target: GenerationTarget.SOURCE)
    }

    // C++ ObjCTranspilerCJMapping.cpp:444-489.
    private func GenerateForwardDeclarations(): Unit {
        let dependencies = HashSet<Decl>()
        var walker: (Ty) -> Unit = {_: Ty => }
        walker = {ty: Ty =>
            if (TypeMapper.IsObjCObjectType(ty)) {
                if (!TypeMapper.IsObjCId(ty) && !ty.IsCoreOptionType()) {
                    dependencies.add(Ty.GetDeclOfTy(Some(ty)).getOrThrow())
                }
            }
            for (typeArg in ty.typeArgs) {
                walker(typeArg)
            }
        }
        for (member in decl.GetMemberDecls()) {
            walker(member.GetTy().getOrThrow())
        }
        dependencies.remove(decl)
        for (dependency in dependencies) {
            let keyword = match (dependency.astKind) {
                case ASTKind.STRUCT_DECL | ASTKind.ENUM_DECL | ASTKind.CLASS_DECL => CLASS_FWD_KEYWORD
                case ASTKind.INTERFACE_DECL => PROTOCOL_KEYWORD
                case _ =>
                    CJC_ABORT()
                    ""
            }
            AddWithIndent(GenerateImport("\"" + dependency.identifier.Val() + ".h\""),
                target: GenerationTarget.SOURCE)
            AddWithIndent(keyword + " " + dependency.identifier.Val(), target: GenerationTarget.HEADER,
                bOp: OptionalBlockOp.OPEN)
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:491-527.
    private func GenerateExternalDeclarations(): Unit {
        AddWithIndent(GenerateExternalFunctionDeclaration(INIT_CJ_RUNTIME_NAME, BOOL_TYPE,
            CONST_CHAR_POINTER_TYPE), target: GenerationTarget.SOURCE)
        for (declPtr in ctx.genDecls) {
            if (IsNotThisActualTyFunc(declPtr)) {
                continue
            }
            if (declPtr.curFile != decl.curFile || !declPtr.TestAttr(Attribute.C) ||
                declPtr.TestAttr(Attribute.FOREIGN)) {
                continue
            }
            if (declPtr.astKind == ASTKind.FUNC_DECL) {
                let funcDecl = (declPtr as FuncDecl).getOrThrow()
                let funcTy = (funcDecl.GetTy().getOrThrow() as FuncTy).getOrThrow()
                let retTy = funcTy.retTy
                let retType = if (TypeMapper.IsObjCObjectType(retTy) || TypeMapper.IsObjCBlock(retTy)) {
                    VOID_POINTER_TYPE_CJ_MAPPING
                } else {
                    MapCJTypeToObjCType(retTy)
                }
                var argTypes = ""
                for (arg in funcDecl.funcBody.getOrThrow().paramLists[0].params) {
                    argTypes += MapCJTypeToObjCType(arg.GetTy().getOrThrow()) + ","
                }
                if (argTypes.endsWith(",")) {
                    argTypes = argTypes[0..argTypes.size - 1]
                }
                AddWithIndent(GenerateExternalFunctionDeclaration(funcDecl.identifier.Val(), retType, argTypes),
                    target: GenerationTarget.SOURCE)
            }
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:533-550.
    private func GenerateExternalFunctionDeclaration(funcName: String, retType: String,
        argTypes: String): String {
        var objCDeclName = funcName
        if (genericConfig.isSome()) {
            objCDeclName = objCDeclName.replace("$", "")
        }
        return EXTERN_MODIFIER + " " + retType + " " + objCDeclName + "(" + argTypes + ");"
    }

    // C++ ObjCTranspilerCJMapping.cpp:556-614.
    private func GenerateInterfaceDecl(): Unit {
        let classDecl = decl as ClassDecl
        let superClassPtr = if (let Some(value) <- classDecl) { value.GetSuperClassDecl() } else { None }
        let isClassInheritedFromClass = if (let Some(superClass) <- superClassPtr) {
            superClass.identifier.Val() != OBJECT_NAME
        } else {
            false
        }
        if (isClassInheritedFromClass) {
            AddToPreamble(GenerateImport("\"" + superClassPtr.getOrThrow().identifier.Val() + ".h\""))
        }
        if (let InteropType.CJ_Mapping <- interopType) {
            if (TypeMapper.IsOneWayMapping(decl) && !decl.IsOpen()) {
                AddWithIndent(FINAL_MODIFIER, target: GenerationTarget.HEADER)
            }
        }
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        var resultH = INTERFACE_KEYWORD + " " + objCDeclName + " : "
        resultH += if (isClassInheritedFromClass) {
            superClassPtr.getOrThrow().identifier.Val()
        } else {
            OCOBJECT_NAME
        }
        let interfacesVec = ArrayList<InterfaceTy>()
        if (let Some(concreteClassDecl) <- classDecl) {
            for (interfaceTy in concreteClassDecl.GetSuperInterfaceTys()) {
                if (!TypeMapper.IsObjCId(interfaceTy)) {
                    interfacesVec.add(interfaceTy)
                }
            }
        }
        if (!interfacesVec.isEmpty()) {
            for (interfaceTy in interfacesVec) {
                AddToPreamble(GenerateImport("\"" +
                    interfaceTy.decl.getOrThrow().identifier.GetRawText() + ".h\""))
            }
            resultH += JoinVec<InterfaceTy>(interfacesVec,
                {interfaceTy: InterfaceTy => interfaceTy.decl.getOrThrow().identifier.GetRawText()},
                sep: ", ", pre: " <", suf: "> ")
        }
        AddWithIndent(resultH, target: GenerationTarget.HEADER)
        AddWithIndent(IMPL_KEYWORD + " " + objCDeclName, target: GenerationTarget.SOURCE)
    }

    // C++ ObjCTranspilerCJMapping.cpp:620-677. UB-006 mirrors the paired mapper arm.
    private func GenerateFuncParamLists(paramLists: ArrayList<FuncParamList>,
        selectorComponents: ArrayList<String>, format!: FunctionListFormat = FunctionListFormat.DECLARATION,
        `type`!: ObjCFunctionType = ObjCFunctionType.INSTANCE,
        hasForeignNameAnno!: Bool = true): String {
        var componentIndex: Int64 = 1
        var genParams = if (let FunctionListFormat.DECLARATION <- format) { "" } else { "(" }
        if (paramLists.isEmpty()) {
            return ""
        }
        let params = paramLists[0].params
        for (idx in 0..params.size) {
            let cur = params[idx]
            match (format) {
                case FunctionListFormat.DECLARATION =>
                    if (idx != 0) {
                        let name = if (hasForeignNameAnno) {
                            let value = selectorComponents[componentIndex]
                            componentIndex++
                            value
                        } else {
                            ""
                        }
                        genParams += name + ":"
                    } else {
                        genParams += ":"
                    }
                    genParams += "(" + MapCJTypeToObjCType(Some(cur)) + ")" + cur.identifier.Val()
                    if (idx + 1 < params.size) {
                        genParams += " "
                    }
                case FunctionListFormat.STATIC_REF =>
                    InternalError("STATIC_REF param-list generation is defective upstream " +
                        "(ObjCParamMapper.cpp:72-77 / ObjCTranspilerCJMapping.cpp:594-649); " +
                        "arm believed dead — reaching it is a contract violation")
                case FunctionListFormat.CANGJIE_DECL =>
                    genParams += cur.identifier.Val() + ": " + Ty.ToString(cur.typeNode.getOrThrow().GetTy())
                    if (idx + 1 < params.size) {
                        genParams += ", "
                    }
            }
        }
        if (let FunctionListFormat.STATIC_REF <- format) {
            if (params.isEmpty()) {
                if (let ObjCFunctionType.STATIC <- `type`) {
                } else {
                    genParams += VOID_POINTER_TYPE_CJ_MAPPING
                }
            }
            genParams += ")"
        } else if (let FunctionListFormat.CANGJIE_DECL <- format) {
            if (params.isEmpty()) {
                if (let ObjCFunctionType.STATIC <- `type`) {
                } else {
                    genParams += VOID_POINTER_TYPE_CJ_MAPPING
                }
            }
            genParams += ")"
        }
        return genParams
    }

    // C++ ObjCTranspilerCJMapping.cpp:679-682.
    private func GenerateSetterParamLists(`type`: String): String {
        return "(" + `type` + ")" + SETTER_PARAM_NAME_CJ_MAPPING
    }

    // C++ ObjCTranspilerCJMapping.cpp:684-687.
    private func SkipSetterForValueTypeDecl(declArg: Decl): Bool {
        if (let InteropType.CJ_Mapping <- interopType) {
            return declArg.GetTy().getOrThrow() is StructTy
        }
        return false
    }

    // C++ ObjCTranspilerCJMapping.cpp:693-788.
    private func AddProperties(): Unit {
        let registryIdType = CreateType(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
        AddWithIndent(GeneratePropertyDeclaration(ObjCFunctionType.INSTANCE, READWRITE_MODIFIER,
            INT64_T_CJ_MAPPING, SELF_WEAKLINK_NAME, SELF_WEAKLINK_NAME,
            NameGenerator.MakeSetterName(SELF_WEAKLINK_NAME)))
        for (declPtr in decl.GetMemberDecls()) {
            CJC_NULLPTR_CHECK(Some(declPtr))
            if (declPtr.astKind != ASTKind.VAR_DECL && declPtr.astKind != ASTKind.PROP_DECL) {
                continue
            }
            if (!declPtr.TestAttr(Attribute.PUBLIC)) {
                continue
            }
            if (ctx.factory.IsGeneratedNativeHandleField(declPtr)) {
                continue
            }
            if (let InteropType.CJ_Mapping <- interopType) {
                if (!TypeMapper.IsObjCCJMappingMember(declPtr)) {
                    continue
                }
            }
            let varDecl = (declPtr as VarDecl).getOrThrow()
            let staticType = if (varDecl.TestAttr(Attribute.STATIC)) {
                ObjCFunctionType.STATIC
            } else {
                ObjCFunctionType.INSTANCE
            }
            let mappedType = if (isGenericGlueCode && varDecl.GetTy().getOrThrow().IsGeneric()) {
                let config = genericConfig.getOrThrow()
                MapCJTypeToObjCType(TypeManager.GetPrimitiveTy(
                    GetActualTypeKind(GetGenericActualType(config, varDecl.GetTy().getOrThrow().name))))
            } else {
                MapCJTypeToObjCType(varDecl.GetTy().getOrThrow())
            }
            let genSetter = varDecl.isVar && !SkipSetterForValueTypeDecl(decl)
            let modeModifier = if (genSetter) { READWRITE_MODIFIER } else { READONLY_MODIFIER }
            let name = ctx.nameGenerator.GetObjCDeclName(varDecl)
            let getterName = ctx.nameGenerator.GetObjCGetterName(varDecl)
            let setterName = ctx.nameGenerator.GetObjCSetterName(varDecl)
            AddWithIndent(GeneratePropertyDeclaration(staticType, modeModifier, mappedType,
                name, getterName, setterName))

            var getterResult = GenerateFunctionDeclaration(staticType, mappedType, getterName)
            let argList = ArgsList()
            if (let ObjCFunctionType.INSTANCE <- staticType) {
                argList.add((INT64_T_CJ_MAPPING, SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME))
            }
            AddWithIndent(getterResult, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
            if (let ObjCFunctionType.INSTANCE <- staticType) {
                AddCallCangjieBeforeInitGuard()
            }
            var isInnerGenericProp = false
            if (let Some(config) <- genericConfig) {
                if (!varDecl.GetTy().getOrThrow().HasGeneric()) {
                    isInnerGenericProp = config.funcNames.contains(name)
                }
            }
            let implementationName = if (let Some(config) <- genericConfig) {
                ctx.nameGenerator.GetFieldGetterWrapperName(varDecl,
                    genericActualName: Some(config.declInstName), isInnerGeneric: isInnerGenericProp)
            } else {
                ctx.nameGenerator.GetFieldGetterWrapperName(varDecl)
            }
            AddWithIndent(GenerateDefaultFunctionImplementation(implementationName,
                varDecl.GetTy().getOrThrow(), args: argList, `type`: staticType),
                target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
            if (!genSetter) {
                continue
            }
            let setterArgsList = ArgsList()
            if (let ObjCFunctionType.INSTANCE <- staticType) {
                setterArgsList.add((INT64_T_CJ_MAPPING, SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME))
            }
            setterArgsList.add((mappedType,
                GenerateArgumentCast(varDecl.GetTy().getOrThrow(), SETTER_PARAM_NAME_CJ_MAPPING)))
            var setterResult = GenerateFunctionDeclaration(staticType, VOID_TYPE_CJ_MAPPING, setterName)
            setterResult += GenerateSetterParamLists(mappedType)
            AddWithIndent(setterResult, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
            if (let ObjCFunctionType.INSTANCE <- staticType) {
                AddCallCangjieBeforeInitGuard()
            }
            AddWithIndent(GenerateDefaultFunctionImplementation(
                ctx.nameGenerator.GetFieldSetterWrapperName(varDecl),
                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), args: setterArgsList, `type`: staticType),
                target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
        }
        AddProperties4CJMapping()
    }

    // C++ ObjCTranspilerCJMapping.cpp:790-821.
    private func AddCtorsForCjMappingEnum(enumDecl: EnumDecl): Unit {
        let enumName = if (isGenericGlueCode) { genericConfig.getOrThrow().declInstName } else {
            enumDecl.identifier.Val()
        }
        for (ctor in enumDecl.constructors) {
            var result = GenerateFunctionDeclaration(ObjCFunctionType.STATIC, enumName + "*", ctor.identifier.Val())
            var argList: Array<String> = []
            let nativeFuncName = if (let Some(config) <- genericConfig) {
                ctx.nameGenerator.GenerateInitCjObjectName(ctor,
                    genericActualName: Some(config.declInstName))
            } else {
                ctx.nameGenerator.GenerateInitCjObjectName(ctor)
            }
            if (let Some(funcDecl) <- (ctor as FuncDecl)) {
                let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(funcDecl)
                result += GenerateFuncParamLists(funcDecl.funcBody.getOrThrow().paramLists, selectorComponents,
                    format: FunctionListFormat.DECLARATION, `type`: ObjCFunctionType.STATIC,
                    hasForeignNameAnno: GetForeignNameAnnotation(funcDecl).isSome())
                argList = ConvertParamsListToCallableParamsString(funcDecl.funcBody.getOrThrow().paramLists, false)
            }
            AddWithIndent(result, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
            AddWithIndent(GenerateAssignment(INT64_T_CJ_MAPPING + " " + TMP_REG_ID,
                GenerateCCall(nativeFuncName, args: argList)) + ";", target: GenerationTarget.SOURCE)
            AddWithIndent(GenerateReturn(WrapperCallByInitForCJMappingReturn(
                enumDecl.GetTy().getOrThrow(), TMP_REG_ID)), target: GenerationTarget.SOURCE,
                bOp: OptionalBlockOp.CLOSE)
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:827-860.
    private func GenerateInitializer(objCDeclName: String): Unit {
        AddWithIndent(GenerateFunctionDeclaration(ObjCFunctionType.STATIC, VOID_TYPE_CJ_MAPPING,
            INITIALIZE_FUNC_NAME), target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
        AddWithIndent(GenerateIfStatement(SELF_NAME_CJ_MAPPING,
            GenerateObjCCall(objCDeclName, CLASS_KEYWORD), EQ_CHECK_OP),
            target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.OPEN)
        var cjLibName = GetCangjieLibName(cjLibOutputPath, decl.fullPackageName, trimmed: false)
        if (!cjLibName.startsWith("lib")) {
            cjLibName = "lib" + cjLibName
        }
        if (let Some(extIdx) <- cjLibName.lastIndexOf(".")) {
            if (cjLibName[extIdx..] != ctx.sharedLibraryExtension) {
                cjLibName += ctx.sharedLibraryExtension
            }
        } else {
            cjLibName += ctx.sharedLibraryExtension
        }
        cjLibName = "\"" + cjLibName + "\""
        AddWithIndent(GenerateIfStatement(GenerateCCall(INIT_CJ_RUNTIME_NAME, args: [cjLibName]),
            FALSE_KW, EQ_CHECK_OP), target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.OPEN)
        AddWithIndent(GenerateCCall(EXIT_FUNC_NAME, args: ["1"]) + ";", target: GenerationTarget.SOURCE)
        CloseBlock(newLineAfter: true)
        CloseBlock(newLineAfter: true)
        CloseBlock(newLineAfter: true)
    }

    // C++ ObjCTranspilerCJMapping.cpp:862-934.
    private func AddConstructors(): Unit {
        let generatedCtors = ArrayList<ArrayList<String>>()
        for (declPtr in decl.GetMemberDecls()) {
            if (!declPtr.TestAttr(Attribute.PUBLIC) || ctx.factory.IsGeneratedMember(declPtr) ||
                !declPtr.TestAttr(Attribute.CONSTRUCTOR) || declPtr.astKind != ASTKind.FUNC_DECL) {
                continue
            }
            let funcDecl = (declPtr as FuncDecl).getOrThrow()
            if (funcDecl.funcBody.isNone()) {
                continue
            }
            if (let InteropType.CJ_Mapping <- interopType) {
                if (!TypeMapper.IsObjCCJMappingMember(declPtr)) {
                    continue
                }
            }
            let ctor = if (let InteropType.ObjC_Mirror <- interopType) {
                ctx.factory.GetGeneratedImplCtor(decl, funcDecl).getOrThrow()
            } else {
                funcDecl
            }
            let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(funcDecl)
            CJC_ASSERT(!selectorComponents.isEmpty())
            let cjWrapperName = if (let Some(config) <- genericConfig) {
                ctx.nameGenerator.GenerateInitCjObjectName(ctor,
                    genericActualName: Some(config.declInstName))
            } else {
                ctx.nameGenerator.GenerateInitCjObjectName(ctor)
            }
            var result = GenerateFunctionDeclaration(ObjCFunctionType.INSTANCE,
                ID_TYPE_CJ_MAPPING, selectorComponents[0])
            let funcBody = funcDecl.funcBody.getOrThrow()
            result += GenerateFuncParamLists(funcBody.paramLists, selectorComponents,
                format: FunctionListFormat.DECLARATION, `type`: ObjCFunctionType.INSTANCE,
                hasForeignNameAnno: GetForeignNameAnnotation(funcDecl).isSome())
            AddWithIndent(result, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
            if (let InteropType.ObjC_Mirror <- interopType) {
                AddWithIndent(GenerateAssignment(SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME,
                    REGISTRY_ID_UNINIT_VALUE) + ";", target: GenerationTarget.SOURCE)
                var rhs = "(__bridge_transfer " + MapCJTypeToObjCType(decl.GetTy().getOrThrow()) + ")"
                rhs += GenerateCCall(cjWrapperName,
                    args: ConvertParamsListToCallableParamsString(funcBody.paramLists, true))
                AddWithIndent(GenerateAssignment(SELF_NAME_CJ_MAPPING, rhs) + ";",
                    target: GenerationTarget.SOURCE)
            } else {
                AddWithIndent(GenerateIfStatement(SELF_NAME_CJ_MAPPING,
                    GenerateObjCCall(SUPER_KEYWORD, INIT_FUNC_NAME), EQ_OP),
                    target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.OPEN)
                AddWithIndent(GenerateAssignment(SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME,
                    GenerateCCall(cjWrapperName,
                        args: ConvertParamsListToCallableParamsString(funcBody.paramLists, false))) + ";",
                    target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
            }
            AddWithIndent(GenerateReturn(SELF_NAME_CJ_MAPPING), target: GenerationTarget.SOURCE,
                bOp: OptionalBlockOp.CLOSE)
            if (let InteropType.ObjC_Mirror <- interopType) {
                generatedCtors.add(selectorComponents)
            }
        }
        if (let InteropType.ObjC_Mirror <- interopType) {
            if (let Some(classDecl) <- (decl as ClassDecl)) {
                for (ctor in ctx.factory.GetAllParentCtors(classDecl)) {
                    if (!ctor.TestAttr(Attribute.PUBLIC) && ctor.outerDecl != Some(decl)) {
                        continue
                    }
                    if (ctx.factory.IsGeneratedMember(ctor)) {
                        continue
                    }
                    let funcBody = ctor.funcBody.getOrThrow()
                    if (funcBody.paramLists[0].params.size > 1 &&
                        NameGenerator.GetUserDefinedObjCName(ctor).isNone()) {
                        continue
                    }
                    let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(ctor)
                    if (generatedCtors.contains(selectorComponents)) {
                        continue
                    }
                    var result = GenerateFunctionDeclaration(ObjCFunctionType.INSTANCE,
                        ID_TYPE_CJ_MAPPING, selectorComponents[0])
                    result += GenerateFuncParamLists(funcBody.paramLists, selectorComponents,
                        format: FunctionListFormat.DECLARATION, `type`: ObjCFunctionType.INSTANCE,
                        hasForeignNameAnno: GetForeignNameAnnotation(ctor).isSome())
                    AddWithIndent(result, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
                    AddWithIndent(FAIL_CALL_UNINIT_CTOR, target: GenerationTarget.SOURCE)
                    AddWithIndent(GenerateReturn(NIL_KW), target: GenerationTarget.SOURCE,
                        bOp: OptionalBlockOp.CLOSE)
                    generatedCtors.add(selectorComponents)
                }
            }
        }
        AddConstructors4CJMapping()
    }

    // C++ ObjCTranspilerCJMapping.cpp:936-950.
    private func GenerateDeleteObject(): Unit {
        if (GenerateDeleteObject4CJMapping()) {
            return
        }
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (HasImplSuperClass(classDecl)) {
                return
            }
        }
        AddWithIndent(GenerateFunctionDeclaration(ObjCFunctionType.INSTANCE,
            VOID_TYPE_CJ_MAPPING, DELETE_FUNC_NAME), target: GenerationTarget.BOTH,
            bOp: OptionalBlockOp.OPEN)
        let deleteObjName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GenerateDeleteCjObjectName(decl,
                genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GenerateDeleteCjObjectName(decl)
        }
        let args = ArgsList()
        args.add((INT64_T_CJ_MAPPING, SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME))
        AddWithIndent(GenerateDefaultFunctionImplementation(deleteObjName,
            TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT), args: args),
            target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
    }

    // C++ ObjCTranspilerCJMapping.cpp:952-963.
    private func GenerateDealloc(): Unit {
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (HasImplSuperClass(classDecl)) {
                return
            }
        }
        AddWithIndent(GenerateFunctionDeclaration(ObjCFunctionType.INSTANCE,
            VOID_TYPE_CJ_MAPPING, DEALLOC_FUNC_NAME), target: GenerationTarget.BOTH,
            bOp: OptionalBlockOp.OPEN)
        AddWithIndent(GenerateObjCCall(SELF_NAME_CJ_MAPPING, DELETE_FUNC_NAME) + ";",
            target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
    }

    // C++ ObjCTranspilerCJMapping.cpp:969-1013.
    private func AddMethods(): Unit {
        for (declPtr in decl.GetMemberDecls()) {
            if (ctx.factory.IsGeneratedMember(declPtr) || !declPtr.TestAttr(Attribute.PUBLIC)) {
                continue
            }
            if (let InteropType.CJ_Mapping <- interopType) {
                if (!TypeMapper.IsObjCCJMappingMember(declPtr) || declPtr.IsOpen()) {
                    continue
                }
            }
            if (declPtr.astKind == ASTKind.FUNC_DECL &&
                !declPtr.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.FINALIZER)) {
                let funcDecl = (declPtr as FuncDecl).getOrThrow()
                if (let Some(config) <- genericConfig) {
                    if (!IsVisibalFunc(funcDecl, decl, config)) {
                        continue
                    }
                }
                if (let Some(funcBody) <- funcDecl.funcBody) {
                    if (let Some(retTypeNode) <- funcBody.retType) {
                        let staticType = if (funcDecl.TestAttr(Attribute.STATIC)) {
                            ObjCFunctionType.STATIC
                        } else {
                            ObjCFunctionType.INSTANCE
                        }
                        let retTy = retTypeNode.GetTy().getOrThrow()
                        let retType = MapCJTypeToObjCType(Some(retTypeNode))
                        let selectorComponents = ctx.nameGenerator.GetObjCDeclSelectorComponents(funcDecl)
                        var result = GenerateFunctionDeclaration(staticType, retType, selectorComponents[0])
                        result += GenerateFuncParamLists(funcBody.paramLists, selectorComponents,
                            format: FunctionListFormat.DECLARATION, `type`: staticType,
                            hasForeignNameAnno: GetForeignNameAnnotation(funcDecl).isSome())
                        AddWithIndent(result, target: GenerationTarget.BOTH, bOp: OptionalBlockOp.OPEN)
                        if (let ObjCFunctionType.INSTANCE <- staticType) {
                            AddCallCangjieBeforeInitGuard()
                        }
                        let methodName = if (let Some(config) <- genericConfig) {
                            ctx.nameGenerator.GenerateMethodWrapperName(funcDecl,
                                genericActualName: Some(config.declInstName))
                        } else {
                            ctx.nameGenerator.GenerateMethodWrapperName(funcDecl)
                        }
                        AddWithIndent(GenerateDefaultFunctionImplementation(methodName, retTy,
                            args: ConvertParamsListToArgsList(funcBody.paramLists,
                                (let ObjCFunctionType.INSTANCE <- staticType)), `type`: staticType),
                            target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.CLOSE)
                    }
                }
            }
        }
        GenerateMethods4CJMapping()
    }

    // C++ ObjCTranspilerCJMapping.cpp:1015-1036.
    private func ConvertParamsListToArgsList(paramLists: ArrayList<FuncParamList>,
        withRegistryId: Bool): ArgsList {
        let result = ArgsList()
        if (withRegistryId) {
            result.add((INT64_T_CJ_MAPPING, SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME))
        }
        if (!paramLists.isEmpty()) {
            for (cur in paramLists[0].params) {
                var name = cur.identifier.Val()
                name = GenerateArgumentCast(cur.GetTy().getOrThrow(), name)
                result.add((MapCJTypeToObjCType(Some(cur)), name))
            }
        }
        return result
    }

    // C++ ObjCTranspilerCJMapping.cpp:1038-1053.
    private func ConvertParamsListToCallableParamsString(paramLists: ArrayList<FuncParamList>,
        withSelf: Bool): Array<String> {
        let result = ArrayList<String>()
        if (withSelf) {
            result.add(CAST_TO_VOID_PTR_CJ_MAPPING + SELF_NAME_CJ_MAPPING)
        }
        if (!paramLists.isEmpty()) {
            for (cur in paramLists[0].params) {
                result.add(GenerateArgumentCast(cur.GetTy().getOrThrow(), cur.identifier.Val()))
            }
        }
        return result.toArray()
    }

    // C++ ObjCTranspilerCJMapping.cpp:1055-1080.
    private func WriteToFile(): Unit {
        WriteToHeader()
        WriteToSource()
    }

    private func WriteToHeader(): Unit {
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        FileUtil.WriteToFile(FileUtil.JoinPath(outputFilePath, objCDeclName + ".h"), res)
    }

    private func WriteToSource(): Unit {
        let objCDeclName = if (let Some(config) <- genericConfig) {
            ctx.nameGenerator.GetObjCDeclName(decl, genericActualName: Some(config.declInstName))
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        FileUtil.WriteToFile(FileUtil.JoinPath(outputFilePath, objCDeclName + ".m"), resSource)
    }

    // C++ ObjCTranspilerCJMapping.cpp:1082-1093.
    private func InsertPreambleInHeaderFront(): Unit {
        res = resPreamble + res
    }

    private func InsertTypedefsToPreamble(): Unit {
        for (typedef in typedefs) {
            AddToPreamble(typedef + ";")
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:1095-1143.
    private func MapCJTypeToObjCType(ty: Ty): String {
        let objctype = TypeMapper.Cj2ObjCForObjC(ty)
        if (!objctype.decl.isEmpty()) {
            typedefs.add(objctype.decl)
        }
        return objctype.usage
    }

    private func MapCJTypeToObjCType(typeNode: Option<Type>): String {
        if (let None <- typeNode) {
            return UNSUPPORTED_TYPE_CJ_MAPPING
        }
        let ty = typeNode.getOrThrow().GetTy().getOrThrow()
        if (let Some(config) <- genericConfig) {
            if (IsGenericParam(ty, decl, config)) {
                return MapCJTypeToObjCType(TypeManager.GetPrimitiveTy(
                    GetActualTypeKind(GetGenericActualType(config, ty.name))))
            }
        }
        return MapCJTypeToObjCType(ty)
    }

    private func MapCJTypeToObjCType(param: Option<FuncParam>): String {
        if (let None <- param) {
            return UNSUPPORTED_TYPE_CJ_MAPPING
        }
        let funcParam = param.getOrThrow()
        let ty = funcParam.typeNode.getOrThrow().GetTy().getOrThrow()
        if (let Some(config) <- genericConfig) {
            if (IsGenericParam(ty, decl, config)) {
                return MapCJTypeToObjCType(TypeManager.GetPrimitiveTy(
                    GetActualTypeKind(GetGenericActualType(config, ty.name))))
            }
        }
        return MapCJTypeToObjCType(ty)
    }

    // C++ ObjCTranspilerCJMapping.cpp:1145-1163.
    private func GenerateArgumentCast(retTy: Ty, value: String): String {
        if (TypeMapper.IsObjCCJMapping(retTy)) {
            return value + "." + SELF_WEAKLINK_NAME
        }
        let actualTy = if (retTy.IsCoreOptionType()) { retTy.typeArgs[0] } else { retTy }
        if (TypeMapper.IsObjCImpl(actualTy)) {
            return CAST_TO_VOID_PTR_CJ_MAPPING + value
        }
        if (TypeMapper.IsObjCMirror(actualTy) || TypeMapper.IsObjCBlock(actualTy) ||
            TypeMapper.IsObjCCJMappingInterface(actualTy)) {
            return CAST_TO_VOID_PTR_RETAINED_CJ_MAPPING + value
        }
        if (TypeMapper.IsObjCPointer(actualTy)) {
            return CAST_TO_VOID_PTR_UNSAFE_CJ_MAPPING + value
        }
        return value
    }

    // C++ ObjCTranspilerCJMapping.cpp:1165-1183.
    private func GenerateProtocolDecl(): Unit {
        let objCDeclName = if (let Some(config) <- genericConfig) {
            config.declInstName
        } else {
            ctx.nameGenerator.GetObjCDeclName(decl)
        }
        AddWithIndent(GenerateImport(FOUNDATION_IMPORT), target: GenerationTarget.HEADER)
        AddWithIndent(GenerateImport(STDDEF_IMPORT), target: GenerationTarget.HEADER)
        AddWithIndent(PROTOCOL_KEYWORD + " " + objCDeclName, target: GenerationTarget.HEADER)
        AddMethods()
        AddWithIndent(END_KEYWORD, target: GenerationTarget.HEADER)
        WriteToHeader()
    }

    // C++ ObjCTranspilerCJMapping.cpp:1191-1205.
    private func GenerateExternalDeclarations4CJMapping(): Unit {
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return
        }
        if (ctx.fwdClassMap.isEmpty()) {
            return
        }
        resSource += """

typedef struct objc_method* Method;
extern IMP method_getImplementation(Method);
extern Method class_getInstanceMethod(Class, SEL);
extern id objc_getClass(const char *);
"""
    }

    // C++ ObjCTranspilerCJMapping.cpp:1210-1234.
    private func AddConstructors4CJMapping(): Unit {
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return
        }
        AddInitWithRegistryId()
        if (let Some(enumDecl) <- (decl as EnumDecl)) {
            AddCtorsForCjMappingEnum(enumDecl)
        }
        if (!decl.IsOpen()) {
            return
        }
        let fwd = ctx.fwdClassMap.get(decl).getOrThrow()
        for (declPtr in fwd.GetMemberDeclPtrs()) {
            if (declPtr.TestAttr(Attribute.CONSTRUCTOR)) {
                AddConstructor4CJMapping((declPtr as FuncDecl).getOrThrow())
            }
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:1239-1261.
    private func GenerateMethods4CJMapping(): Unit {
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return
        }
        if (!decl.IsOpen()) {
            return
        }
        AddReinitWithRegistryId()
        AddRelease()
        let fwd = ctx.fwdClassMap.get(decl).getOrThrow()
        let overrides = ArrayList<FuncDecl>()
        for (declPtr in fwd.GetMemberDeclPtrs()) {
            if (declPtr.TestAttr(Attribute.OVERRIDE)) {
                let funcDecl = (declPtr as FuncDecl).getOrThrow()
                overrides.add(funcDecl)
                GenerateMethod4CJMapping(funcDecl)
            }
        }
        AddCalcMask(overrides)
    }

    // C++ ObjCTranspilerCJMapping.cpp:1274-1301.
    private func GenerateMethod4CJMapping(fn: FuncDecl): Unit {
        let fnTy = (fn.GetTy().getOrThrow() as FuncTy).getOrThrow()
        let originalOpenFn = ctx.fwdOverrideTable.get(fn).getOrThrow()
        let params = ArrayList<FuncParam>()
        let callArgs = ArrayList<String>()
        callArgs.add("self.$registryId")
        for (param in fn.funcBody.getOrThrow().paramLists[0].params) {
            params.add(param)
        }
        let sig = "-(" + MapCJTypeToObjCType(fnTy.retTy) + ")" + fn.identifier.Val() +
            JoinVec<FuncParam>(params, {param: FuncParam =>
                let paramName = param.identifier.Val()
                callArgs.add(paramName)
                ":(" + MapCJTypeToObjCType(param.GetTy().getOrThrow()) + ")" + paramName
            }, sep: " ", pre: "", suf: "", force: false)
        res += sig + ";\n"
        let argStr = JoinVec<String>(callArgs, {arg: String => arg}, sep: ", ", pre: "(", suf: ");")
        let ifThen: () -> Unit = { =>
            WriteSeq(["return " + ctx.nameGenerator.GenerateMethodWrapperName(fn) + argStr])
        }
        let ifElse: () -> Unit = { =>
            WriteSeq(["return " + ctx.nameGenerator.GenerateMethodWrapperName(originalOpenFn) + argStr])
        }
        WriteFunc(sig, { => WriteIf("self.$initedFromObjC", ifThen, other: Some(ifElse)) })
    }

    // C++ ObjCTranspilerCJMapping.cpp:1313-1344.
    private func AddConstructor4CJMapping(ctor: FuncDecl): Unit {
        let params = ArrayList<FuncParam>()
        let callArgs = ArrayList<String>()
        callArgs.add(CAST_TO_VOID_PTR_CJ_MAPPING + "self")
        callArgs.add("[self calcOverrideMask]")
        let fwdParams = ctor.funcBody.getOrThrow().paramLists[0].params
        for (idx in 2..fwdParams.size) {
            params.add(fwdParams[idx])
        }
        let initSig = "-(id)init" + JoinVec<FuncParam>(params, {param: FuncParam =>
            let paramName = param.identifier.Val()
            callArgs.add(paramName)
            ":(" + MapCJTypeToObjCType(param.GetTy().getOrThrow()) + ")" + paramName
        }, sep: " ", pre: "", suf: "", force: false)
        res += initSig + ";\n"
        let callStr = ctx.nameGenerator.GenerateInitCjObjectName(ctor) +
            JoinVec<String>(callArgs, {arg: String => arg}, sep: ", ", pre: "(", suf: ");")
        let ifThen: () -> Unit = { =>
            WriteSeq([SELF_NAME_CJ_MAPPING + "." + INITED_FROM_OBJC_NAME + " = true;",
                SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME + " = " + callStr,
                "[" + SELF_NAME_CJ_MAPPING + " " + RETAIN_FUNC_NAME + "];"])
        }
        WriteFunc(initSig, { =>
            WriteIf("self = [super init]", ifThen)
            WriteSeq(["return " + SELF_NAME_CJ_MAPPING + ";"])
        })
    }

    // C++ ObjCTranspilerCJMapping.cpp:1349-1358.
    private func AddProperties4CJMapping(): Unit {
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return
        }
        if (!decl.IsOpen()) {
            return
        }
        res += PROPERTY_KEYWORD + " (" + READWRITE_MODIFIER + ") " + BOOL_TYPE + " " +
            INITED_FROM_OBJC_NAME + ";\n"
    }

    // C++ ObjCTranspilerCJMapping.cpp:1363-1378.
    private func AddInitWithRegistryId(): Unit {
        AddWithIndent(INIT_WITH_REGISTRY_ID_SIGNATURE, target: GenerationTarget.BOTH,
            bOp: OptionalBlockOp.OPEN)
        AddWithIndent(GenerateIfStatement(SELF_NAME_CJ_MAPPING,
            GenerateObjCCall(SUPER_KEYWORD, INIT_FUNC_NAME), EQ_OP),
            target: GenerationTarget.SOURCE, bOp: OptionalBlockOp.OPEN)
        if (decl.IsOpen()) {
            AddWithIndent(GenerateAssignment(SELF_NAME_CJ_MAPPING + "." + INITED_FROM_OBJC_NAME,
                "false") + ";", target: GenerationTarget.SOURCE)
        }
        AddWithIndent(GenerateAssignment(SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME,
            REGISTRY_ID_PARAM_NAME) + ";", target: GenerationTarget.SOURCE,
            bOp: OptionalBlockOp.CLOSE)
        AddWithIndent(GenerateReturn(SELF_NAME_CJ_MAPPING), target: GenerationTarget.SOURCE,
            bOp: OptionalBlockOp.CLOSE)
    }

    // C++ ObjCTranspilerCJMapping.cpp:1383-1392.
    private func AddReinitWithRegistryId(): Unit {
        res += REINIT_WITH_REGISTRY_ID_SIGNATURE + ";\n"
        WriteFunc(REINIT_WITH_REGISTRY_ID_SIGNATURE, { =>
            WriteSeq([SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME + " = " +
                REGISTRY_ID_PARAM_NAME + ";", "[" + SELF_NAME_CJ_MAPPING + " " + RETAIN_FUNC_NAME + "];",
                "return " + SELF_NAME_CJ_MAPPING + ";"])
        })
    }

    // C++ ObjCTranspilerCJMapping.cpp:1397-1411.
    private func GenerateDeleteObject4CJMapping(): Bool {
        if (let InteropType.CJ_Mapping <- interopType) {
        } else {
            return false
        }
        if (!decl.IsOpen()) {
            return false
        }
        WriteFunc("- (void)deleteCJObject", { =>
            WriteIf("!self.$initedFromObjC", { =>
                WriteSeq([ctx.nameGenerator.GenerateDeleteCjObjectName(decl) + "(self.$registryId);"])
            })
        })
        return true
    }

    // C++ ObjCTranspilerCJMapping.cpp:1416-1445.
    private func AddRelease(): Unit {
        let fwd = ctx.fwdClassMap.get(decl).getOrThrow()
        res += RELEASE_SIGNATURE + ";\n"
        let ifThen: () -> Unit = { =>
            let lockFuncName = ctx.nameGenerator.GenerateLockCjObjectName(fwd)
            WriteSeq(["int64_t idToDelete = self.$registryId;", lockFuncName + "(idToDelete);"])
            WriteIf("1 == CFGetRetainCount((__bridge CFTypeRef)self)", { =>
                let deleteFuncName = ctx.nameGenerator.GenerateDeleteCjObjectName(fwd)
                WriteSeq(["self.$registryId = -1;", deleteFuncName + "(idToDelete);"])
            }, other: Some({ =>
                let unlockFuncName = ctx.nameGenerator.GenerateUnlockCjObjectName(fwd)
                WriteSeq([unlockFuncName + "(idToDelete);"])
            }))
        }
        WriteFunc(RELEASE_SIGNATURE, { =>
            WriteSeq(["[super release];"])
            WriteIf("self.$initedFromObjC && 1 == CFGetRetainCount((__bridge CFTypeRef)self)", ifThen)
        })
    }

    // C++ ObjCTranspilerCJMapping.cpp:1450-1486.
    private func AddCalcMask(overrides: ArrayList<FuncDecl>): Unit {
        resSource += """

static uint64_t calcMask(Class baseCls, Class selfCls, SEL* methods, int len) {
    int max = len;
    if (max > 64) {
        max = 64;
    }
    uint64_t mask = 0;
    for (int i = 0; i < max; i++) {
        SEL m = methods[i];
        bool override = method_getImplementation(class_getInstanceMethod(baseCls, m)) !=
            method_getImplementation(class_getInstanceMethod(selfCls, m));
        if (override) {
            mask |= (UINT64_C(1) << i);
        }
    }
    return mask;
}

"""
        WriteFunc("- (uint64_t)calcOverrideMask", { =>
            WriteSeq(["Class baseCls = objc_getClass(\"" + ctx.nameGenerator.GetObjCDeclName(decl) + "\");",
                "Class selfCls = [self class];",
                JoinVec<FuncDecl>(overrides, {fn: FuncDecl =>
                    CJC_ASSERT(fn.funcBody.isSome())
                    var colons = ""
                    for (_ in 0..fn.funcBody.getOrThrow().paramLists[0].params.size) {
                        colons += ":"
                    }
                    "@selector(" + fn.identifier.Val() + colons + ")"
                }, sep: ", ", pre: "SEL methods[] = {", suf: "};"),
                "return calcMask(baseCls, selfCls, methods, " + overrides.size.toString() + ");"])
        })
    }

    // C++ ObjCTranspilerCJMapping.cpp:1488-1503.
    private func WriteFunc(signature: String, body: () -> Unit): Unit {
        for (_ in 0..currentBlockIndent) {
            buffer.append(" ")
        }
        buffer.append(signature)
        WriteBlock(body, suf: "\n\n", flush: true)
    }

    private func WriteFor(header: String, loop: () -> Unit): Unit {
        for (_ in 0..currentBlockIndent) {
            buffer.append(" ")
        }
        buffer.append("for (" + header + ")")
        WriteBlock(loop)
        buffer.append("\n")
    }

    private func WriteIf(cond: String, `then`: () -> Unit,
        other!: Option<() -> Unit> = None): Unit {
        for (_ in 0..currentBlockIndent) {
            buffer.append(" ")
        }
        buffer.append("if (" + cond + ")")
        WriteBlock(`then`)
        if (let Some(otherBlock) <- other) {
            WriteBlock(otherBlock, pre: " else")
        }
        buffer.append("\n")
    }

    private func WriteBlock(action: () -> Unit, pre!: String = "", suf!: String = "",
        flush!: Bool = false): Unit {
        buffer.append(pre + " {\n")
        currentBlockIndent += INDENT_SIZE
        action()
        currentBlockIndent -= INDENT_SIZE
        for (_ in 0..currentBlockIndent) {
            buffer.append(" ")
        }
        buffer.append("}" + suf)
        if (flush) {
            resSource += buffer.toString()
            buffer = StringBuilder()
        }
    }

    private func WriteSeq(statements: Array<String>): Unit {
        for (statement in statements) {
            for (_ in 0..currentBlockIndent) {
                buffer.append(" ")
            }
            buffer.append(statement + "\n")
        }
    }

    // C++ ObjCTranspilerCJMapping.cpp:1505-1516.
    private func AddCallCangjieBeforeInitGuard(): Unit {
        if (let InteropType.ObjC_Mirror <- interopType) {
        } else {
            return
        }
        AddWithIndent(GenerateIfStatement(SELF_NAME_CJ_MAPPING + "." + SELF_WEAKLINK_NAME,
            REGISTRY_ID_UNINIT_VALUE, EQ_CHECK_OP), target: GenerationTarget.SOURCE,
            bOp: OptionalBlockOp.OPEN)
        AddWithIndent(FAIL_CALL_CANGJIE_BEFORE_INIT, target: GenerationTarget.SOURCE,
            bOp: OptionalBlockOp.CLOSE)
    }
}
