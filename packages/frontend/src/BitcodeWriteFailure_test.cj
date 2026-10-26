package cjcj::frontend

import std.collection.*
import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::codegen.{LLVMContextHandle, LLVMModuleHandle, LLVMParseBitcodeFile}

// The runner supplies a private directory with an existing "blocked" subdirectory.
// Passing that directory to the real LLVM file writer must fail at open, not in
// frontend path preparation. Successful siblings must still be valid bitcode.
private func BitcodeWriteTestRoot(): String {
    return getVariable("CJCJ_BITCODE_TEST_DIR").getOrThrow()
}

@Test
public class BitcodeWriteFailureTest {
    @TestCase
    public func SingleNativeFailureIsReturned(): Unit {
        try (context = LLVMContextHandle.Create(),
            module = LLVMModuleHandle.Create("single-write-failure", context)) {
            let modules = ArrayList<LLVMModuleHandle>([module])
            let paths = ArrayList<String>([BitcodeWriteTestRoot() + "/blocked"])
            @Expect(SaveGeneratedBitcode(modules, paths), false)
            @Expect(module.isClosed(), false)
        }
    }

    @TestCase
    public func ParallelFailureIsReturnedAfterSuccessfulSibling(): Unit {
        try (leftContext = LLVMContextHandle.Create(), rightContext = LLVMContextHandle.Create(),
            left = LLVMModuleHandle.Create("successful-sibling", leftContext),
            right = LLVMModuleHandle.Create("failed-sibling", rightContext)) {
            let path = BitcodeWriteTestRoot() + "/successful-sibling.bc"
            let modules = ArrayList<LLVMModuleHandle>([left, right])
            let paths = ArrayList<String>([path, BitcodeWriteTestRoot() + "/blocked"])
            @Expect(SaveGeneratedBitcode(modules, paths), false)
            let parsed = LLVMParseBitcodeFile(leftContext, path)
            @Assert(parsed.ok)
            parsed.module.close()
        }
    }

    @TestCase
    public func SuccessfulNativeWritesRemainReadable(): Unit {
        try (leftContext = LLVMContextHandle.Create(), rightContext = LLVMContextHandle.Create(),
            left = LLVMModuleHandle.Create("control-left", leftContext),
            right = LLVMModuleHandle.Create("control-right", rightContext)) {
            let leftPath = BitcodeWriteTestRoot() + "/control-left.bc"
            let rightPath = BitcodeWriteTestRoot() + "/control-right.bc"
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
}
