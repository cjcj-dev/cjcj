package cjcj::chir

import std.collection.*

public class ClassDef <: CustomTypeDef {
    private var classType: Option<ClassType> = None
    private var isClass: Bool = false
    private var superClassTy: Option<ClassType> = None
    private var annotationTargets: Option<ArrayList<GlobalVar>> = None

    public init(packageName: String, identifier: String, isClass!: Bool = true) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_CLASS)
        this.isClass = isClass
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String, isClass!: Bool = true) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_CLASS)
        this.isClass = isClass
    }

    public override func GetType(): Option<Type> {
        if (let Some(ty) <- classType) {
            return ty
        }
        return None
    }

    public override func SetType(ty: CustomType): Unit {
        if (let Some(classTy) <- (ty as ClassType)) {
            classType = classTy
            return
        }
        throw IllegalArgumentException("ClassDef requires ClassType")
    }

    public func IsAbstract(): Bool {
        return TestAttr(Attribute.ABSTRACT)
    }

    public override func IsInterface(): Bool {
        return !isClass
    }

    public override func IsClass(): Bool {
        return isClass
    }

    public func IsAnnotation(): Bool {
        if (let Some(_) <- annotationTargets) {
            return true
        }
        return false
    }

    public func SetAnnotationTargets(targets: ArrayList<GlobalVar>): Unit {
        let copied = ArrayList<GlobalVar>()
        for (target in targets) {
            copied.add(target)
        }
        annotationTargets = copied
    }

    public func GetAnnotationTargets(): ArrayList<GlobalVar> {
        let out = ArrayList<GlobalVar>()
        if (let Some(targets) <- annotationTargets) {
            for (target in targets) {
                out.add(target)
            }
        }
        return out
    }

    public func GetSuperClassDef(): Option<ClassDef> {
        if (let Some(ty) <- superClassTy) {
            return ty.GetClassDef()
        }
        return None
    }

    public func HasSuperClass(): Bool {
        return GetSuperClassDef().isSome()
    }

    public func SetSuperClassTy(ty: ClassType): Unit {
        superClassTy = ty
    }

    public func GetSuperClassTy(): Option<ClassType> {
        return superClassTy
    }

    public func GetFinalizer(): Option<Function> {
        for (method in GetMethods()) {
            if (method.GetFuncKind() == FuncKind.FINALIZER) {
                return method
            }
        }
        return None
    }

    protected override func AddExtraComment(): String {
        if (!IsAnnotation()) {
            return ""
        }
        var targetStr = ""
        if (let Some(targets) <- annotationTargets) {
            if (targets.isEmpty()) {
                targetStr = "[ALL]"
            } else {
                let targetValues = ArrayList<Value>()
                for (target in targets) {
                    targetValues.add(target)
                }
                targetStr = ValueIdVecToString("[", targetValues, "]")
            }
        }
        return "AnnoTargets: " + targetStr
    }

}
