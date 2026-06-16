package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public class GenericInstantiationContextFrame {
    public var decl: Option<Decl> = None
    public var triggerNode: Option<Node> = None
    public var typeMapping: TypeSubst = TypeSubst()

    public init() {}

    public init(decl: Option<Decl>, typeMapping: TypeSubst, triggerNode!: Option<Node> = None) {
        this.decl = decl
        this.typeMapping = typeMapping
        this.triggerNode = triggerNode
    }
}

public class GenericInstantiationContext {
    private var typeManager: TypeManager
    private let frames: ArrayList<GenericInstantiationContextFrame> = ArrayList<GenericInstantiationContextFrame>()

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
    }

    public func Push(frame: GenericInstantiationContextFrame): Unit {
        frames.add(frame)
    }

    public func Push(decl: Decl, typeArgs: ArrayList<Ty>, triggerNode!: Option<Node> = None): Unit {
        let mapping = GenerateTypeMapping(decl, typeArgs)
        Push(GenericInstantiationContextFrame(Some(decl), mapping, triggerNode: triggerNode))
    }

    public func PushMapping(decl: Option<Decl>, typeMapping: TypeSubst, triggerNode!: Option<Node> = None): Unit {
        Push(GenericInstantiationContextFrame(decl, typeMapping.Clone(), triggerNode: triggerNode))
    }

    public func Pop(): Option<GenericInstantiationContextFrame> {
        if (frames.isEmpty()) {
            return None
        }
        let frame = frames[frames.size - 1]
        frames.remove(at: frames.size - 1)
        return frame
    }

    public func Clear(): Unit {
        frames.clear()
    }

    public func Depth(): Int64 {
        return frames.size
    }

    public func CurrentFrame(): Option<GenericInstantiationContextFrame> {
        if (frames.isEmpty()) {
            return None
        }
        return frames[frames.size - 1]
    }

    public func CurrentDecl(): Option<Decl> {
        if (let Some(frame) <- CurrentFrame()) {
            return frame.decl
        }
        return None
    }

    public func CurrentTriggerNode(): Option<Node> {
        if (let Some(frame) <- CurrentFrame()) {
            return frame.triggerNode
        }
        return None
    }

    public func CurrentTypeMapping(): TypeSubst {
        if (let Some(frame) <- CurrentFrame()) {
            return frame.typeMapping.Clone()
        }
        return TypeSubst()
    }

    public func Apply(ty: Ty): Ty {
        return typeManager.GetInstantiatedTy(ty, CurrentTypeMapping())
    }

    public func Apply(node: Node): Unit {
        if (let Some(ty) <- node.GetTy()) {
            node.SetTy(Apply(ty))
        }
    }

    public func ConstructGenericInfo(decl: Decl, instTys: ArrayList<Ty>): GenericInfo {
        return GenericInfo(Some(decl), GenerateTypeMapping(decl, instTys))
    }
}
