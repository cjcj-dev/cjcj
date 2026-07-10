package cjcj::compiler_unittest

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::sema.Plugin.*

private func Parse(json: String): JsonObject {
    return ParseJsonObject(json.toArray())
}

@Test
public class ParseJsonTest {
    @TestCase
    public func parseEmptyObject(): Unit {
        let obj = Parse("{}")
        @Expect(obj.pairs.size, 0)
    }

    @TestCase
    public func parseSimpleString(): Unit {
        let obj = Parse(#"{"key": "value"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].key, "key")
        @Expect(obj.pairs[0].valueStr.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "value")
    }

    @TestCase
    public func parseMultipleKeys(): Unit {
        let obj = Parse(#"{"key1": "value1", "key2": "value2"}"#)
        @Expect(obj.pairs.size, 2)
        @Expect(obj.pairs[0].key, "key1")
        @Expect(obj.pairs[0].valueStr[0], "value1")
        @Expect(obj.pairs[1].key, "key2")
        @Expect(obj.pairs[1].valueStr[0], "value2")
    }

    @TestCase
    public func parseNumber(): Unit {
        let obj = Parse(#"{"count": 42}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].key, "count")
        @Expect(obj.pairs[0].valueNum.size, 1)
        @Expect(obj.pairs[0].valueNum[0], 42u64)
    }

    @TestCase
    public func parseNestedObject(): Unit {
        let obj = Parse(#"{"outer": {"inner": "value"}}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].key, "outer")
        @Expect(obj.pairs[0].valueObj.size, 1)
        let innerObj = obj.pairs[0].valueObj[0]
        @Expect(innerObj.pairs.size, 1)
        @Expect(innerObj.pairs[0].key, "inner")
        @Expect(innerObj.pairs[0].valueStr[0], "value")
    }

    @TestCase
    public func parseArray(): Unit {
        let obj = Parse(#"{"items": ["a", "b", "c"]}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].key, "items")
        @Expect(obj.pairs[0].valueStr.size, 3)
        @Expect(obj.pairs[0].valueStr[0], "a")
        @Expect(obj.pairs[0].valueStr[1], "b")
        @Expect(obj.pairs[0].valueStr[2], "c")
    }

    @TestCase
    public func parseEscapedDoubleQuotes(): Unit {
        let obj = Parse(#"{"key": "value\"with\"quotes"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "value\"with\"quotes")
    }

    @TestCase
    public func parseEscapedBackslash(): Unit {
        let obj = Parse(#"{"path": "C:\\Users\\test"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "C:\\Users\\test")
    }

    @TestCase
    public func parseEscapedNewline(): Unit {
        let obj = Parse(#"{"text": "line1\nline2"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "line1\nline2")
    }

    @TestCase
    public func parseEscapedTab(): Unit {
        let obj = Parse(#"{"text": "col1\tcol2"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "col1\tcol2")
    }

    @TestCase
    public func parseComplexEscapedString(): Unit {
        let obj = Parse(#"{"key": "a\"b\\c\nd\te"}"#)
        @Expect(obj.pairs.size, 1)
        @Expect(obj.pairs[0].valueStr[0], "a\"b\\c\nd\te")
    }

    @TestCase
    public func getJsonStringTest(): Unit {
        let obj = Parse(#"{"name": "test", "value": "123"}"#)
        var values = GetJsonString(obj, "name")
        @Expect(values.size, 1)
        @Expect(values[0], "test")

        values = GetJsonString(obj, "value")
        @Expect(values.size, 1)
        @Expect(values[0], "123")

        values = GetJsonString(obj, "notexist")
        @Expect(values.size, 0)
    }

    @TestCase
    public func getJsonObjectTest(): Unit {
        let obj = Parse(#"{"config": {"setting": "enabled"}}"#)
        let innerObj = GetJsonObject(obj, "config", 0).getOrThrow()
        @Expect(innerObj.pairs.size, 1)
        @Expect(innerObj.pairs[0].key, "setting")
        @Expect(innerObj.pairs[0].valueStr[0], "enabled")
    }

    @TestCase
    public func parseWhitespaceHandling(): Unit {
        let obj = Parse("{\n        \"key1\": \"value1\",\n        \"key2\": 123\n    }")
        @Expect(obj.pairs.size, 2)
        @Expect(obj.pairs[0].key, "key1")
        @Expect(obj.pairs[1].key, "key2")
    }

    @TestCase
    public func parseNumberWithoutColon(): Unit {
        let obj = Parse("{123}")
        @Expect(obj.pairs.size, 0)
    }

    @TestCase
    public func parseObjectWithoutColon(): Unit {
        let obj = Parse(#"{{"inner": "value"}}"#)
        @Expect(obj.pairs.size, 0)
    }

    @TestCase
    public func parseArrayWithoutColon(): Unit {
        let obj = Parse(#"{["a", "b"]}"#)
        @Expect(obj.pairs.size, 0)
    }
}
