package cjcj::sema.NativeFFI.ObjC

import std.collection.ArrayList

// C++ src/Sema/NativeFFI/ObjC/Utils/Handler.h:21-27.
public enum InteropType {
    | NA
    | ObjC_Mirror
    | CJ_Mapping
    | CJ_Mapping_Interface
    | Fwd_Class
}

extend InteropType <: Equatable<InteropType> {
    public operator func ==(right: InteropType): Bool {
        return match ((this, right)) {
            case (InteropType.NA, InteropType.NA) => true
            case (InteropType.ObjC_Mirror, InteropType.ObjC_Mirror) => true
            case (InteropType.CJ_Mapping, InteropType.CJ_Mapping) => true
            case (InteropType.CJ_Mapping_Interface, InteropType.CJ_Mapping_Interface) => true
            case (InteropType.Fwd_Class, InteropType.Fwd_Class) => true
            case _ => false
        }
    }

    public operator func !=(right: InteropType): Bool {
        return !(this == right)
    }
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Handler.h:33-48.
// C++ uses CRTP to dispatch Handle to DerivedT::HandleImpl. Cangjie has no generic parameter packs;
// CPP_TO_CJ_TRANSLATION.md requires the protocol default below and the ordered handler table beneath it.
public interface Handler<ContextT> {
    public func Handle(ctx: ContextT): Unit {
        HandleImpl(ctx)
    }

    func HandleImpl(ctx: ContextT): Unit
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Handler.h:50-80.
public class ChainedHandlers<ContextT> {
    private let handlers: ArrayList<(ContextT) -> Unit>

    // Mirrors the first one-element tuple constructed by HandlerFactory::Start.
    public init(handler: Handler<ContextT>) {
        handlers = ArrayList<(ContextT) -> Unit>()
        handlers.add({ctx: ContextT => handler.Handle(ctx)})
    }

    private init(handlers: ArrayList<(ContextT) -> Unit>) {
        this.handlers = handlers
    }

    // C++ Handler.h:60-65 moves the existing tuple and appends NextHandlerT. Copying the ordered
    // closure table preserves that value-returning Use contract without mutating the source chain.
    public func Use(nextHandler: Handler<ContextT>): ChainedHandlers<ContextT> {
        let nextHandlers = ArrayList<(ContextT) -> Unit>()
        for (handler in handlers) {
            nextHandlers.add(handler)
        }
        nextHandlers.add({ctx: ContextT => nextHandler.Handle(ctx)})
        return ChainedHandlers<ContextT>(nextHandlers)
    }

    // Registration callers must append handlers in the exact order anchored at
    // src/Sema/NativeFFI/ObjC/AfterTypeCheck/Desugar.cpp:44-75.
    public func Handle(ctx: ContextT): Unit {
        for (handler in handlers) {
            handler(ctx)
        }
    }
}

// C++ src/Sema/NativeFFI/ObjC/Utils/Handler.h:84-92.
// ContextT is a method parameter because Cangjie forbids a static member from depending on its
// enclosing class's type parameter; the resulting Start call still infers the same context type.
public class HandlerFactory {
    public static func Start<ContextT>(firstHandler: Handler<ContextT>): ChainedHandlers<ContextT> {
        return ChainedHandlers<ContextT>(firstHandler)
    }
}
