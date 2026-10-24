package cjcj::meta_transformation

import cjcj::basic.CANGJIE_VERSION
import std.unittest.*
import std.unittest.testmacro.*

@C
func PluginValidationCallback(builder: NativeMetaTransformPluginBuilderRef): Unit {}

@Test
class NativeMetaTransformPluginValidationTest {
    @TestCase
    func nullVersionWithPresentCallbackIsRejected(): Unit {
        let callback: CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit> = PluginValidationCallback
        let info = MetaTransformPluginInfo(CString(CPointer<UInt8>()), callback)
        @Expect(!IsValidNativePluginInfo(info))
    }

    @TestCase
    func matchingVersionStillRequiresCallback(): Unit {
        let callback = CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit>(CPointer<Unit>())
        try (version = unsafe { LibC.mallocCString(CANGJIE_VERSION) }.asResource()) {
            @Expect(!IsValidNativePluginInfo(MetaTransformPluginInfo(version.value, callback)))
        }
    }

    @TestCase
    func versionValidationHasPositiveAndNegativeControls(): Unit {
        let callback: CFunc<(NativeMetaTransformPluginBuilderRef) -> Unit> = PluginValidationCallback
        try (version = unsafe { LibC.mallocCString(CANGJIE_VERSION) }.asResource()) {
            @Expect(IsValidNativePluginInfo(MetaTransformPluginInfo(version.value, callback)))
        }
        try (version = unsafe { LibC.mallocCString("incompatible-version") }.asResource()) {
            @Expect(!IsValidNativePluginInfo(MetaTransformPluginInfo(version.value, callback)))
        }
    }
}
