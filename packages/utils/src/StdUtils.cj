package cjcj::utils

public let STOINT_BASE: Int32 = 10

private let ERANGE_ERRNO: Int32 = 34

foreign {
    func strtol(nptr: CString, endptr: CPointer<CString>, base: Int32): IntNative
    func strtoul(nptr: CString, endptr: CPointer<CString>, base: Int32): UIntNative
    func strtoll(nptr: CString, endptr: CPointer<CString>, base: Int32): Int64
    func strtoull(nptr: CString, endptr: CPointer<CString>, base: Int32): UInt64
    func strtod(nptr: CString, endptr: CPointer<CString>): Float64
}

@When[os == "Linux"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    unsafe {
        return __errno_location()
    }
}

@When[os == "macOS"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    unsafe {
        return __error()
    }
}

@When[os != "Linux" && os != "macOS"]
private func errnoLocationForStdUtils(): CPointer<Int32> {
    return CPointer<Int32>()
}

private func resetStdUtilsErrno(): Unit {
    unsafe {
        let errnoPtr = errnoLocationForStdUtils()
        if (!errnoPtr.isNull()) {
            errnoPtr.write(0)
        }
    }
}

private func stdUtilsErrno(): Int32 {
    unsafe {
        let errnoPtr = errnoLocationForStdUtils()
        if (errnoPtr.isNull()) {
            return 0
        }
        return errnoPtr.read()
    }
}

public func Stoi(s: String, base!: Int32 = STOINT_BASE): Option<Int64> {
    var result: Option<Int64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let parsed = unsafe { strtol(cInput.value, endPtr.value, base) }
            let endValue = unsafe { endPtr.value.read() }
            let value = Int64(parsed)
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO ||
                value < Int64(Int32.Min) || value > Int64(Int32.Max)) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stoui(s: String, base!: Int32 = STOINT_BASE): Option<UInt64> {
    var result: Option<UInt64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let value = UInt64(unsafe { strtoul(cInput.value, endPtr.value, base) })
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO ||
                value > UInt64(UInt32.Max)) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stol(s: String, base!: Int32 = STOINT_BASE): Option<Int64> {
    var result: Option<Int64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let value = Int64(unsafe { strtol(cInput.value, endPtr.value, base) })
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stoul(s: String, base!: Int32 = STOINT_BASE): Option<UInt64> {
    var result: Option<UInt64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let value = UInt64(unsafe { strtoul(cInput.value, endPtr.value, base) })
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stoll(s: String, base!: Int32 = STOINT_BASE): Option<Int64> {
    var result: Option<Int64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let value = unsafe { strtoll(cInput.value, endPtr.value, base) }
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stoull(s: String, base!: Int32 = STOINT_BASE): Option<UInt64> {
    var result: Option<UInt64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let value = unsafe { strtoull(cInput.value, endPtr.value, base) }
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                value
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stod(s: String): Option<Float64> {
    var result: Option<Float64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let parsed = unsafe { strtod(cInput.value, endPtr.value) }
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                parsed
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}

public func Stold(s: String): Option<Float64> {
    var result: Option<Float64> = None
    try (cInput = unsafe { LibC.mallocCString(s) }.asResource(),
        endPtr = LibC.malloc<CString>().asResource()) {
        if (!cInput.value.isNull()) {
            unsafe { endPtr.value.write(CString(CPointer<UInt8>())) }
            resetStdUtilsErrno()
            let parsed = unsafe { strtod(cInput.value, endPtr.value) }
            let endValue = unsafe { endPtr.value.read() }
            result = if (endValue.isNull() ||
                unsafe { strlen(endValue) } == unsafe { strlen(cInput.value) } ||
                stdUtilsErrno() == ERANGE_ERRNO) {
                None
            } else {
                parsed
            }
        }
    } catch (e: Exception) {
        result = None
    }
    return result
}
