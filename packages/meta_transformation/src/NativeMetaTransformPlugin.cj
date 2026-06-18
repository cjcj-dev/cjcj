package cangjie_compiler::meta_transformation

@When[os != "Windows"]
private let DLOPEN_MODE: Int32 = 0x101

@When[os != "Windows"]
foreign {
    func dlopen(filename: CString, flag: Int32): CPointer<Unit>
    func dlsym(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func dlclose(handle: CPointer<Unit>): Int32
}

@When[os == "Windows"]
foreign {
    func LoadLibraryA(filename: CString): CPointer<Unit>
    func GetProcAddress(handle: CPointer<Unit>, symbol: CString): CPointer<Unit>
    func FreeLibrary(handle: CPointer<Unit>): Int32
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
    private let metaTransformPluginInfo: NativeMetaTransformPluginInfo
    private var handle: CPointer<Unit>

    private init() {
        pluginPath = ""
        metaTransformPluginInfo = NativeMetaTransformPluginInfo()
        handle = CPointer<Unit>()
    }

    private init(pluginPath: String, metaTransformPluginInfo: NativeMetaTransformPluginInfo, handle: CPointer<Unit>) {
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
        let pluginInfo = GetNativeMetaTransformPluginInfo(symbol) ??
            throw IllegalStateException("native MetaTransform plugin info symbol is null: " + path)
        return NativeMetaTransformPlugin(path, pluginInfo, handle)
    }

    public func IsValid(): Bool {
        return !pluginPath.isEmpty() && metaTransformPluginInfo.IsValid()
    }

    public func IsValidForVersion(version: String): Bool {
        return !pluginPath.isEmpty() && metaTransformPluginInfo.IsValidForVersion(version)
    }

    public func GetHandle(): CPointer<Unit> {
        return handle
    }

    public func GetPluginInfo(): NativeMetaTransformPluginInfo {
        return metaTransformPluginInfo
    }

    public func RegisterCallbackTo(builder: NativeMetaTransformPluginBuilderRef): Unit {
        metaTransformPluginInfo.RegisterTo(builder)
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
