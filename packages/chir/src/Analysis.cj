package cangjie_compiler::chir

public enum ReachableKind {
    | UNREACHABLE | REACHABLE
}

public abstract class AbstractDomain<Domain> {
    protected var kind: ReachableKind = ReachableKind.UNREACHABLE

    protected init() {}

    public open func Join(rhs: Domain): Bool {
        let _ = rhs
        return false
    }

    public open func IsBottom(): Bool {
        return match (kind) {
            case ReachableKind.UNREACHABLE => true
            case ReachableKind.REACHABLE => false
        }
    }

    public open func ToString(): String {
        return ""
    }
}

public abstract class Analysis<Domain> where Domain <: AbstractDomain<Domain> {
    protected let `func`: Function
    protected let isDebug: Bool
    protected var currentLambda: Option<Lambda> = None
    protected var isStable: Bool = false
    protected static let name: String = ""
    protected static let blockLimit: Option<UInt32> = None

    protected init(`func`: Function, isDebug!: Bool = false) {
        this.`func` = `func`
        this.isDebug = isDebug
    }

    public func Bottom(): Domain

    public open func InitializeFuncEntryState(state: Domain): Unit {
        let _ = state
    }

    public open func UpdateCurrentLambda(lambda: Lambda): Unit {
        currentLambda = lambda
    }

    public open func InitializeLambdaEntryState(state: Domain): Unit {
        let _ = state
    }

    public open func HandleVarStateCapturedByLambda(state: Domain, lambda: Lambda): Unit {
        let _ = state
        let _ = lambda
    }

    public open func PreHandleLambdaExpression(state: Domain, lambda: Lambda): Unit {
        let _ = state
        let _ = lambda
    }

    public open func PropagateExpressionEffect(state: Domain, expression: Expression): Unit {
        let _ = state
        let _ = expression
    }

    public open func PropagateTerminatorEffect(state: Domain, terminator: Terminator): Option<Block> {
        let _ = state
        let _ = terminator
        return None
    }

    public static func Filter(method: Function): Bool {
        let _ = method
        return true
    }

    public open func CheckInQueueTimes(block: Block, curState: Domain): Bool {
        let _ = block
        let _ = curState
        return false
    }

    public static func GetAnalysisName(): String {
        return name
    }

    public static func GetBlockLimit(): Option<UInt32> {
        return blockLimit
    }

    public func SetToStable(): Unit {
        isStable = true
    }
}
