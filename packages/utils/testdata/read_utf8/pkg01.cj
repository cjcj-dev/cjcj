// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package testpkg

public let one : Int32 = 1
public let two : Int32 = 2
public class pkg {
    public var aaa:Int32 = 1
    protected var one:Int32 = 1
    private var a:Int32 = 0
    public static var aa:Int32 = 0
    public init() {
        this.a = 123
    }
    public init(a: Int32) {
        this.a = a
    }
    public func add(a: Int32, b: Int32){
        return a + b + this.one
    }
    public open func add2(a: Int32, b: Int32) {
        return a + b
    }
    public static func add3(a: Int32, b: Int32) {
        return a + b
    }
}

public struct Test{
    public let width: Int32 = 2
    public let length: Int32 = 5
    public init(a:Int32, b:Int32) {
        width = a
        length = b
    }

    public func area(): Int32 {
        return width * length
    }
}

public enum TimeUnit {
    Year | Month | Day | Hour
}

public func testpkgFunc(): Int32 {
    return 1
}

public interface iPkg {
    let aclass: Int32 = 1
    func foo() : Int32
    default func getNum():Int32 {
        return 1
    }

    static func getSum():Int32 {
        return 1
    }
}