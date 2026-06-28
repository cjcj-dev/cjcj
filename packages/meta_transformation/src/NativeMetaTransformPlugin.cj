package cangjie_compiler::meta_transformation

import cangjie_compiler::basic.CANGJIE_VERSION

@When[os != "Windows"]
private let DLOPEN_MODE: Int32 = 0x101

@When[os != "Windows"]
foreign {
    func dlopen(filename: CString, flag: Int32): CPointer<Unit>
    func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func dlclose(handle: CPointer<Unit>): Int32
    func strcmp(lhs: CString, rhs: CString): Int32
}

@When[os == "Windows"]
foreign {
    func LoadLibraryA(filename: CString): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func FreeLibrary(handle: CPointer<Unit>): Int32
    func strcmp(lhs: CString, rhs: CString): Int32
}

@When[os != "Windows"]
private func OpenNativeLibrary(path: CString): CPointer<Unit> {
    return unsafe { dlopen(path, DLOPEN_MODE) }
}

@When[os == "Windows"]
private func OpenNativeLibrary(path: CString): CPointer<Unit> {
    return unsafe { LoadLibraryA(path) }
}

@When[os != "Windows"]
private func GetNativeSymbol(handle: CPointer<Unit>, name: CString): CPointer<Unit> {
    return unsafe { dlsym(handle, name) }
}

@When[os == "Windows"]
private func GetNativeSymbol(handle: CPointer<Unit>, name: CString): CPointer<Unit> {
    return unsafe { GetProcAddress(handle, name) }
}

@When[os != "Windows"]
private func CloseNativeLibrary(handle: CPointer<Unit>): Int64 {
    return Int64(unsafe { dlclose(handle) })
}

@When[os == "Windows"]
private func CloseNativeLibrary(handle: CPointer<Unit>): Int64 {
    return Int64(unsafe { FreeLibrary(handle) })
}

private func LoadNativeLibrary(path: String): CPointer<Unit> {
    var result = CPointer<Unit>()
    try (pathCString = unsafe { LibC.mallocCString(path) }.asResource()) {
        result = OpenNativeLibrary(pathCString.value)
    } catch (e: Exception) {
        result = CPointer<Unit>()
    }
    return result
}

private func LookupNativeSymbol(handle: CPointer<Unit>, name: String): CPointer<Unit> {
    if (handle.isNull() || name.isEmpty()) {
        return CPointer<Unit>()
    }
    var result = CPointer<Unit>()
    try (symbolName = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = GetNativeSymbol(handle, symbolName.value)
    } catch (e: Exception) {
        result = CPointer<Unit>()
    }
    return result
}

public class NativeMetaTransformPlugin {
    private let pluginPath: String
    private let metaTransformPluginInfo: MetaTransformPluginInfo
    private var handle: CPointer<Unit>

    private init() {
        pluginPath = ""
        metaTransformPluginInfo = MetaTransformPluginInfo()
        handle = CPointer<Unit>()
    }

    private init(pluginPath: String, metaTransformPluginInfo: MetaTransformPluginInfo, handle: CPointer<Unit>) {
        this.pluginPath = pluginPath
        this.metaTransformPluginInfo = metaTransformPluginInfo
        this.handle = handle
    }

    public static func Get(path: String): NativeMetaTransformPlugin {
        let handle = LoadNativeLibrary(path)
        if (handle.isNull()) {
            throw IllegalStateException("failed to open native MetaTransform plugin: " + path)
        }
        let symbol = LookupNativeSymbol(handle, META_TRANSFORM_PLUGIN_INFO_SYMBOL)
        if (symbol.isNull()) {
            let _ = CloseNativeLibrary(handle)
            throw IllegalStateException("native MetaTransform plugin info symbol not found: " + path)
        }
        let getter = CFunc<() -> MetaTransformPluginInfo>(symbol)
        let pluginInfo = unsafe { getter() }
        return NativeMetaTransformPlugin(path, pluginInfo, handle)
    }

    public func IsValid(): Bool {
        if (pluginPath.isEmpty()) {
            return false
        }
        var versionMatches = false
        try (expectedVersion = unsafe { LibC.mallocCString(CANGJIE_VERSION) }.asResource()) {
            versionMatches = unsafe { strcmp(metaTransformPluginInfo.cjcVersion, expectedVersion.value) } == 0
        }
        return versionMatches && !CPointer<Unit>(metaTransformPluginInfo.registerTo).isNull()
    }

    public func GetHandle(): CPointer<Unit> {
        return handle
    }

    public func GetPluginInfo(): MetaTransformPluginInfo {
        return metaTransformPluginInfo
    }

    public func RegisterCallbackTo(builder: NativeMetaTransformPluginBuilderRef): Unit {
        unsafe { metaTransformPluginInfo.registerTo(builder) }
    }

    public func Close(): Int64 {
        if (handle.isNull()) {
            return 0
        }
        let result = CloseNativeLibrary(handle)
        handle = CPointer<Unit>()
        return result
    }
}
