// Copyright (c) Huawei Technologies Co., Ltd. 2025. All rights reserved.
// This source file is part of the Cangjie project, licensed under Apache-2.0
// with Runtime Library Exception.
//
// See https://cangjie-lang.cn/pages/LICENSE for license information.

package testpkg01
internal import testpkg.*
public class pkg01 <: pkg {
    public var aaa:Int32 = 1
    protected var one:Int32 = 1
    private var a:Int32 = 0
    public static var aa:Int32 = 0
    public init() {
        this.a = 100
    }
    public init(a: Int32) {
        this.a = a
    }
}

public interface iPkg01 <: iPkg {
    let aclass: Int32 = 1
    func foo() : Int32
    override default func getNum():Int32 {
        return 1
    }

    static func getSum():Int32 {
        return 1
    }
}
