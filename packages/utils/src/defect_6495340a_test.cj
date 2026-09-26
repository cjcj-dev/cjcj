package cjcj::utils

import std.fs.Directory as FSDirectory
import std.fs.File
import std.unittest.*
import std.unittest.testmacro.*

private func expectNoneU64(value: Option<UInt64>, label: String): Unit {
    if (let Some(actual) <- value) {
        println("ASSERT_FAIL ${label} got Some(${actual})")
        @Expect(false, true)
    } else {
        println("ASSERT_RAN ${label}=None")
        @Expect(true, true)
    }
}

private func expectSomeU64(value: Option<UInt64>, expected: UInt64, label: String): Unit {
    if (let Some(actual) <- value) {
        println("ASSERT_RAN ${label}=${actual}")
        @Expect(actual, expected)
    } else {
        println("ASSERT_FAIL ${label} got None")
        @Expect(0u64, expected)
    }
}

class SeparatorRecord <: UserBase {
    public init() {
        super()
    }

    protected override func GetSuffix(): String {
        return ".fake.prof"
    }

    protected override func GetJson(): String {
        return "{}"
    }
}

@Test
class Defect6495340aTest {
    @TestCase
    func stouiMinusZeroIsNone(): Unit {
        println("ASSERT_TARGET Stoui(-0)=None")
        expectNoneU64(Stoui("-0"), "Stoui(-0)")
    }

    @TestCase
    func stouiMinusOneIsNone(): Unit {
        println("ASSERT_NAMED Stoui(-1)=None")
        expectNoneU64(Stoui("-1"), "Stoui(-1)")
        expectNoneU64(Stoui("  -42"), "Stoui(space-42)")
        expectNoneU64(Stoui("-ff", base: 16), "Stoui(-ff,16)")
    }

    @TestCase
    func stouiTrailingJunkStillParsed(): Unit {
        expectSomeU64(Stoui("5-"), 5u64, "Stoui(5-)")
        expectSomeU64(Stoui("7abc"), 7u64, "Stoui(7abc)")
        if (let Some(stolValue) <- Stol("-1")) {
            println("ASSERT_RAN Stol(-1)=${stolValue}")
            @Expect(stolValue, -1)
        } else {
            println("ASSERT_FAIL Stol(-1) got None")
            @Expect(0, -1)
        }
    }

    @TestCase
    func writeJsonReplacesEverySeparator(): Unit {
        let dir = "/tmp/cjcj343_writejson_sep"
        if (FileUtil.IsDir(dir)) {
            let _ = FileUtil.RemoveDirectoryRecursively(dir)
        }
        @Expect(FileUtil.CreateDirs(dir + DIR_SEPARATOR), 0)
        @Expect(FileUtil.CreateDirs(FileUtil.JoinPath(dir, "a-b") + DIR_SEPARATOR), 0)
        let record = SeparatorRecord()
        record.SetOutputDir(dir)
        record.SetPackageName("a/b/c")
        record.Enable(true)
        record.OutputResult()
        let flat = FileUtil.JoinPath(dir, "a-b-c.fake.prof")
        let nested = FileUtil.JoinPath(FileUtil.JoinPath(dir, "a-b"), "c.fake.prof")
        let flatExists = FileUtil.FileExist(flat)
        let nestedExists = FileUtil.FileExist(nested)
        println("ASSERT_TARGET flat=${flatExists} nested=${nestedExists}")
        @Expect(flatExists, true)
        @Expect(nestedExists, false)
        let _ = FileUtil.RemoveDirectoryRecursively(dir)
    }
}

@When[os == "Windows"]
@Test
class WindowsRemoveGuardTest {
    @TestCase
    func removeRefusesSystemAttribute(): Unit {
        let dir = "/tmp/cjcj343_remove_system"
        if (FileUtil.IsDir(dir)) {
            let _ = FileUtil.RemoveDirectoryRecursively(dir)
        }
        @Expect(FileUtil.CreateDirs(dir + DIR_SEPARATOR), 0)
        let path = FileUtil.JoinPath(dir, "system_bit.txt")
        File.writeTo(path, "x".toArray())
        @Expect(FileUtil.FileExist(path), true)
        var setOk = false
        try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
            if (!cPath.value.isNull()) {
                let rc = unsafe { SetFileAttributesA(cPath.value, 0x4u32) }
                setOk = rc != 0
                println("ASSERT_RAN SetFileAttributesA(SYSTEM)=${rc}")
            }
        } catch (e: Exception) {
            setOk = false
        }
        @Expect(setOk, true)
        println("ASSERT_TARGET Remove(SYSTEM)=false")
        @Expect(FileUtil.Remove(path), false)
        @Expect(FileUtil.FileExist(path), true)
        let _ = FileUtil.RemoveDirectoryRecursively(dir)
    }
}
