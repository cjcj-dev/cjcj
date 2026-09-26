package callsite

import java.internal.*
import java.lang.*

public func make(): JArray<Int32> {
    let arr = JArray<Int32>(4)
    return (arr as JArray<Int32>).getOrThrow()
}
