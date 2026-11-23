package modalaggregatereceivers

public class CjoAggregateBag {
    public init() {}

    @When[local_mode_api == "on"]
    public exclave init(this @local!) {}

    public prop size: Int64 {
        get() { 1 }
    }

    @When[local_mode_api == "on"]
    public prop size: Int64 @local? {
        get() { 2 }
    }

    public func isEmpty(): Bool { false }

    @When[local_mode_api == "on"]
    public func isEmpty(this @local?): Bool { true }
}
