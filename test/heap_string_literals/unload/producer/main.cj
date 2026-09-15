package literal_unload_source
import literal_retainer.retainLiteral
@C
public func publishRetainedLiteral(arg: CPointer<Unit>): CPointer<Unit> {
    retainLiteral("unload-世界")
    return arg
}
