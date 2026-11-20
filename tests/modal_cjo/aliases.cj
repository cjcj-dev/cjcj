package aliassigs

public type Callback = (Int64, Int64 @local!) -> Int64
public type Visitor = ((Int64, Int64 @local?) -> Int64) -> Int64
public type Factory = () -> (Int64, Int64 @local!) -> Int64
public type Plain = (Int64, Int64) -> Int64
