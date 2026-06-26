package cangjie_compiler::chir

import std.collection.*

public class ClassDef <: CustomTypeDef {
    private var classType: Option<ClassType> = None
    private var superClassDef: Option<ClassDef> = None
    private var superClassTy: Option<ClassType> = None
    private let implementedInterfaceDefs: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private var annotationTargets: Option<ArrayList<GlobalVar>> = None

    public init(packageName: String, identifier: String) {
        super(packageName, identifier, identifier, CustomDefKind.TYPE_CLASS)
    }

    public init(packageName: String, identifier: String, srcCodeIdentifier: String) {
        super(packageName, identifier, srcCodeIdentifier, CustomDefKind.TYPE_CLASS)
    }

    public override func GetType(): Option<CustomType> {
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

    public func SetSuperClassDef(def: ClassDef): Unit {
        superClassDef = def
        let emptyArgs = ArrayList<Type>()
        superClassTy = ClassType(def, emptyArgs)
    }

    public func GetSuperClassDef(): Option<ClassDef> {
        return superClassDef
    }

    public func SetSuperClassTy(ty: ClassType): Unit {
        superClassTy = ty
        superClassDef = ty.GetClassDef()
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

    public func AddImplementedInterfaceDef(def: ClassDef): Unit {
        if (!ContainsLocalClassDef(implementedInterfaceDefs, def)) {
            implementedInterfaceDefs.add(def)
        }
        let emptyArgs = ArrayList<Type>()
        AddImplementedInterfaceTy(ClassType(def, emptyArgs))
    }

    public override func GetImplementedInterfaceDefs(): ArrayList<ClassDef> {
        let out = super.GetImplementedInterfaceDefs()
        for (def in implementedInterfaceDefs) {
            if (!ContainsLocalClassDef(out, def)) {
                out.add(def)
            }
        }
        return out
    }

    public override func ToString(indent: Int64): String {
        return IndentToString(indent) + "class " + GetFullName()
    }
}

private func ContainsLocalClassDef(values: ArrayList<ClassDef>, classDef: ClassDef): Bool {
    for (value in values) {
        if (value.nodeId == classDef.nodeId) {
            return true
        }
    }
    return false
}
