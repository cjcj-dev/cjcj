package cjcj::frontend

import std.collection.*
import std.fs.Directory as FSDirectory
import std.fs.removeIfExists
import cjcj::utils.{TaskQueue, TaskResult}
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::codegen.{LLVMContextHandle, LLVMModuleHandle, LLVMParseBitcodeFile, SavePackageModule}

// Every normal CJPM/registered invocation prepares and owns its own fixture.
// No runner-only environment variable or pre-existing directory is required.
private class BitcodeWriteTestDirectory <: Resource {
    let root: String
    private var closed = false

    init() {
        root = FSDirectory.createTemp(".").toString()
        try {
            FSDirectory.create(root + "/blocked")
        } catch (e: Exception) {
            let _ = removeIfExists(root, recursive: true)
            throw e
        }
    }

    public func isClosed(): Bool { return closed }

    public func close(): Unit {
        if (!closed) {
            let _ = removeIfExists(root, recursive: true)
            closed = true
        }
    }
}

@Test
public class BitcodeWriteFailureTest {
    @TestCase
    public func SingleNativeFailureIsReturned(): Unit {
        try (directory = BitcodeWriteTestDirectory(), context = LLVMContextHandle.Create(),
            module = LLVMModuleHandle.Create("single-write-failure", context)) {
            let modules = ArrayList<LLVMModuleHandle>([module])
            let paths = ArrayList<String>([directory.root + "/blocked"])
            @Expect(SaveGeneratedBitcode(modules, paths), false)
            @Expect(module.isClosed(), false)
        }
    }

    @TestCase
    public func ParallelFailureIsReturnedAfterSuccessfulSibling(): Unit {
        try (directory = BitcodeWriteTestDirectory(), leftContext = LLVMContextHandle.Create(), rightContext = LLVMContextHandle.Create(),
            left = LLVMModuleHandle.Create("successful-sibling", leftContext),
            right = LLVMModuleHandle.Create("failed-sibling", rightContext)) {
            let path = directory.root + "/successful-sibling.bc"
            let modules = ArrayList<LLVMModuleHandle>([left, right])
            let paths = ArrayList<String>([path, directory.root + "/blocked"])
            @Expect(SaveGeneratedBitcode(modules, paths), false)
            let parsed = LLVMParseBitcodeFile(leftContext, path)
            @Assert(parsed.ok)
            parsed.module.close()
        }
    }

    @TestCase
    public func SuccessfulNativeWritesRemainReadable(): Unit {
        try (directory = BitcodeWriteTestDirectory(), leftContext = LLVMContextHandle.Create(), rightContext = LLVMContextHandle.Create(),
            left = LLVMModuleHandle.Create("control-left", leftContext),
            right = LLVMModuleHandle.Create("control-right", rightContext)) {
            let leftPath = directory.root + "/control-left.bc"
            let rightPath = directory.root + "/control-right.bc"
            let modules = ArrayList<LLVMModuleHandle>([left, right])
            let paths = ArrayList<String>([leftPath, rightPath])
            @Expect(SaveGeneratedBitcode(modules, paths), true)
            let parsedLeft = LLVMParseBitcodeFile(leftContext, leftPath)
            let parsedRight = LLVMParseBitcodeFile(rightContext, rightPath)
            @Assert(parsedLeft.ok)
            @Assert(parsedRight.ok)
            parsedLeft.module.close()
            parsedRight.module.close()
        }
    }

    @TestCase
    public func ExceptionDoesNotSkipSuccessfulNativeSibling(): Unit {
        try (directory = BitcodeWriteTestDirectory(),
            context = LLVMContextHandle.Create(), module = LLVMModuleHandle.Create("exception-sibling", context)) {
            let queue = TaskQueue(2)
            let failed = queue.AddTask<Bool>({ =>
                throw IllegalArgumentException("injected writer exception")
            })
            let successful = queue.AddTask<Bool>({ => SavePackageModule(module, directory.root + "/sibling.bc") })
            queue.RunAndWaitForAllTasksCompleted()
            @Expect(failed.isCompleted(), true)
            @Expect(successful.isCompleted(), true)
            var caught = false
            try {
                let _ = CollectBitcodeWriteResults(ArrayList<TaskResult<Bool>>([failed, successful]))
            } catch (e: IllegalArgumentException) {
                caught = e.message == "injected writer exception"
            }
            @Expect(caught, true)
            // get consumes a successful TaskResult exactly once. If the first
            // exception skipped this result, this second get would succeed.
            var consumed = false
            try {
                let _ = successful.get()
            } catch (_: Exception) {
                consumed = true
            }
            @Expect(consumed, true)
            let parsed = LLVMParseBitcodeFile(context, directory.root + "/sibling.bc")
            @Assert(parsed.ok)
            parsed.module.close()
        }
    }

    @TestCase
    public func NativeFalseDoesNotMaskWorkerException(): Unit {
        try (directory = BitcodeWriteTestDirectory(),
            context = LLVMContextHandle.Create(), module = LLVMModuleHandle.Create("false-and-exception", context)) {
            let queue = TaskQueue(2)
            let rejected = queue.AddTask<Bool>({ => SavePackageModule(module, directory.root + "/blocked") })
            let failed = queue.AddTask<Bool>({ => throw IllegalStateException("later writer exception") })
            queue.RunAndWaitForAllTasksCompleted()
            var caught = false
            try {
                let _ = CollectBitcodeWriteResults(ArrayList<TaskResult<Bool>>([rejected, failed]))
            } catch (e: IllegalStateException) {
                caught = e.message == "later writer exception"
            }
            @Expect(caught, true)
            @Expect(rejected.isCompleted(), true)
            @Expect(failed.isCompleted(), true)
        }
    }

}
