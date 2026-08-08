package cjcj::utils

import std.collection.*
import std.convert.*
import std.env.{atExit, getVariable}
import std.sync.*

// GNU make jobserver protocol constants. The protocol carries one opaque byte per
// available execution slot; cjc never interprets the byte and returns it unchanged.
private let JOBSERVER_DISABLED_LEASE: Int64 = 0
private let JOBSERVER_IMPLICIT_LEASE: Int64 = 1
private let JOBSERVER_PIPE_LEASE: Int64 = 2
private let JOBSERVER_LOCAL_LEASE: Int64 = 3

@When[os == "Linux"]
@C
struct JobserverFdSet {
    var bits: VArray<UIntNative, $16>

    init() {
        bits = VArray<UIntNative, $16>({ _: Int64 => UIntNative(0) })
    }
}

@When[os == "macOS" || os == "iOS"]
@C
struct JobserverFdSet {
    var bits: VArray<UInt32, $32>

    init() {
        bits = VArray<UInt32, $32>({ _: Int64 => 0u32 })
    }
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
@C
struct JobserverTimeval {
    var seconds: IntNative
    var microseconds: IntNative

    init(seconds: IntNative, microseconds: IntNative) {
        this.seconds = seconds
        this.microseconds = microseconds
    }
}

@When[os == "Linux" || os == "macOS" || os == "iOS"]
private let JOBSERVER_OPEN_READ_WRITE: Int32 = 2

@When[os == "Linux" || os == "macOS" || os == "iOS"]
foreign {
    func write(fd: Int32, buffer: CPointer<UInt8>, count: UIntNative): IntNative
    func select(nfds: Int32, readFds: CPointer<JobserverFdSet>, writeFds: CPointer<JobserverFdSet>,
        exceptFds: CPointer<JobserverFdSet>, timeout: CPointer<JobserverTimeval>): Int32
}

@When[os == "Linux"]
private func JobserverFdZero(set: CPointer<JobserverFdSet>): Unit {
    unsafe {
        var value = set.read()
        var index: Int64 = 0
        while (index < 16) {
            value.bits[index] = UIntNative(0)
            index++
        }
        set.write(value)
    }
}

@When[os == "Linux"]
private func JobserverFdAdd(fd: Int32, set: CPointer<JobserverFdSet>): Bool {
    if (fd < 0 || fd >= 1024) {
        return false
    }
    unsafe {
        var value = set.read()
        let word = Int64(fd) / 64
        let bit = UIntNative(Int64(fd) % 64)
        value.bits[word] = value.bits[word] | (UIntNative(1) << bit)
        set.write(value)
    }
    return true
}

@When[os == "macOS" || os == "iOS"]
private func JobserverFdZero(set: CPointer<JobserverFdSet>): Unit {
    unsafe {
        var value = set.read()
        var index: Int64 = 0
        while (index < 32) {
            value.bits[index] = 0u32
            index++
        }
        set.write(value)
    }
}

@When[os == "macOS" || os == "iOS"]
private func JobserverFdAdd(fd: Int32, set: CPointer<JobserverFdSet>): Bool {
    if (fd < 0 || fd >= 1024) {
        return false
    }
    unsafe {
        var value = set.read()
        let word = Int64(fd) / 32
        let bit = UInt32(Int64(fd) % 32)
        value.bits[word] = value.bits[word] | (1u32 << bit)
        set.write(value)
    }
    return true
}

private func FindJobserverAuth(flags: String): Option<String> {
    let authPrefix = "--jobserver-auth="
    let fdsPrefix = "--jobserver-fds="
    var start: Int64 = 0
    while (start < flags.size) {
        while (start < flags.size && (flags[start] == b' ' || flags[start] == b'\t')) {
            start++
        }
        var end = start
        while (end < flags.size && flags[end] != b' ' && flags[end] != b'\t') {
            end++
        }
        if (end > start) {
            let field = flags[start..end]
            if (field.startsWith(authPrefix)) {
                return Some(field[authPrefix.size..])
            }
            if (field.startsWith(fdsPrefix)) {
                return Some(field[fdsPrefix.size..])
            }
        }
        start = end + 1
    }
    return None
}

private func GetJobserverAuthFromEnvironment(): Option<String> {
    for (name in ["CARGO_MAKEFLAGS", "MAKEFLAGS", "MFLAGS"]) {
        if (let Some(flags) <- getVariable(name)) {
            if (let Some(auth) <- FindJobserverAuth(flags)) {
                return Some(auth)
            }
        }
    }
    return None
}

public class ConcurrencyLease {
    private let owner: ConcurrencyBudget
    private let kind: Int64
    private let token: UInt8
    private var released: Bool = false

    init(owner: ConcurrencyBudget, kind: Int64, token!: UInt8 = 0u8) {
        this.owner = owner
        this.kind = kind
        this.token = token
    }

    public func Release(): Unit {
        if (released) {
            return
        }
        released = true
        owner.ReleaseLease(kind, token)
    }
}

// Single process-wide authority for compiler concurrency. When CJPM_JOBSERVER is
// absent, callers receive the exact legacy width and every requested worker is
// admitted. With the switch enabled, one worker may use the process's implicit
// GNU-make slot and every additional worker must hold one pipe/FIFO token.
public class ConcurrencyBudget {
    private static let singleton = ConcurrencyBudget()
    private let mutex = Mutex()
    private var initialized: Bool = false
    private var enabled: Bool = false
    private var jobserverReady: Bool = false
    private var ownsDescriptors: Bool = false
    private var readFd: Int32 = -1
    private var writeFd: Int32 = -1
    private var implicitHeld: Bool = false
    private var localLimit: Int64 = 1
    private var localHeld: Int64 = 0
    private var acquiredCount: Int64 = 0
    private var releasedCount: Int64 = 0
    private var activeCount: Int64 = 0
    private var peakActiveCount: Int64 = 0
    private let heldTokens = ArrayList<UInt8>()
    private let leaseThreadIds = HashSet<Int64>()

    private init() {
        atExit({ => ReleaseAllAtExit() })
    }

    public static func Get(): ConcurrencyBudget {
        return singleton
    }

    public func Configure(requestedParallelism: Int64): Unit {
        EnsureInitialized()
        synchronized(mutex) {
            localLimit = if (requestedParallelism > 0) { requestedParallelism } else { 1 }
        }
    }

    // Jobserver availability takes precedence over -j. The token pool is the hard
    // limit, while hardware concurrency is only a finite upper bound on how many
    // workers a single task queue attempts to create.
    public func GetParallelism(requestedParallelism: Int64, hardwareParallelism: Int64): Int64 {
        EnsureInitialized()
        let requested = if (requestedParallelism > 0) { requestedParallelism } else { 1 }
        let hardware = if (hardwareParallelism > 0) { hardwareParallelism } else { 1 }
        synchronized(mutex) {
            return if (enabled && jobserverReady) { hardware } else { requested }
        }
    }

    public func IsEnabled(): Bool {
        EnsureInitialized()
        synchronized(mutex) {
            return enabled
        }
    }

    public func TryAcquire(): Option<ConcurrencyLease> {
        EnsureInitialized()
        synchronized(mutex) {
            // A worker that already owns one execution slot must run nested work
            // serially. In particular, it must never hold a jobserver token while
            // waiting for another token-backed worker.
            if (enabled && leaseThreadIds.contains(Thread.currentThread.id)) {
                return None
            }
            if (!enabled) {
                return Some(ConcurrencyLease(this, JOBSERVER_DISABLED_LEASE))
            }
            if (jobserverReady) {
                if (!implicitHeld) {
                    implicitHeld = true
                    RecordAcquire()
                    return Some(ConcurrencyLease(this, JOBSERVER_IMPLICIT_LEASE))
                }
                if (let Some(token) <- TryReadToken()) {
                    heldTokens.add(token)
                    RecordAcquire()
                    return Some(ConcurrencyLease(this, JOBSERVER_PIPE_LEASE, token: token))
                }
                return None
            }
            if (localHeld < localLimit) {
                localHeld++
                RecordAcquire()
                return Some(ConcurrencyLease(this, JOBSERVER_LOCAL_LEASE))
            }
            return None
        }
    }

    public func SpawnBudgeted<T>(body: () -> T): Option<Future<T>> {
        if (let Some(lease) <- TryAcquire()) {
            return Some(SpawnWithLease(lease, body))
        }
        return None
    }

    public func SpawnWithLease<T>(lease: ConcurrencyLease, body: () -> T): Future<T> {
        return spawn {
            EnterLeaseThread()
            try {
                body()
            } finally {
                LeaveLeaseThread()
                lease.Release()
            }
        }
    }

    private func EnterLeaseThread(): Unit {
        synchronized(mutex) {
            if (enabled) {
                leaseThreadIds.add(Thread.currentThread.id)
            }
        }
    }

    private func LeaveLeaseThread(): Unit {
        synchronized(mutex) {
            if (enabled) {
                leaseThreadIds.remove(Thread.currentThread.id)
            }
        }
    }

    // I/O reapers do not consume a CPU execution slot, but still route through the
    // authority so raw production spawn sites remain centralized and auditable.
    public func SpawnUnbudgeted<T>(body: () -> T): Future<T> {
        return spawn { body() }
    }

    public func ReleaseLease(kind: Int64, token: UInt8): Unit {
        synchronized(mutex) {
            if (kind == JOBSERVER_IMPLICIT_LEASE) {
                implicitHeld = false
            } else if (kind == JOBSERVER_PIPE_LEASE) {
                var index: Int64 = 0
                while (index < heldTokens.size) {
                    if (heldTokens[index] == token) {
                        heldTokens.remove(at: index)
                        break
                    }
                    index++
                }
                WriteToken(token)
            } else if (kind == JOBSERVER_LOCAL_LEASE && localHeld > 0) {
                localHeld--
            }
            if (enabled) {
                releasedCount++
                if (activeCount > 0) {
                    activeCount--
                }
            }
        }
    }

    private func RecordAcquire(): Unit {
        acquiredCount++
        activeCount++
        if (activeCount > peakActiveCount) {
            peakActiveCount = activeCount
        }
    }

    private func EnsureInitialized(): Unit {
        synchronized(mutex) {
            if (initialized) {
                return
            }
            initialized = true
            enabled = (getVariable("CJPM_JOBSERVER") ?? "") == "1"
            if (!enabled) {
                return
            }
            if (let Some(auth) <- GetJobserverAuthFromEnvironment()) {
                jobserverReady = InitializeJobserver(auth)
            }
            if (!jobserverReady) {
                eprintln("warning: CJPM_JOBSERVER is enabled but no usable GNU jobserver was inherited; using -j fallback")
            }
        }
    }

    @When[os == "Linux" || os == "macOS" || os == "iOS"]
    private func InitializeJobserver(auth: String): Bool {
        if (auth.startsWith("fifo:")) {
            let path = auth[5..]
            if (path.isEmpty()) {
                return false
            }
            try (cPath = unsafe { LibC.mallocCString(path) }.asResource()) {
                let fd = unsafe { open(cPath.value, JOBSERVER_OPEN_READ_WRITE) }
                if (fd < 0 || fd >= 1024) {
                    if (fd >= 0) {
                        let _ = unsafe { close(fd) }
                    }
                    return false
                }
                readFd = fd
                writeFd = fd
                ownsDescriptors = true
                return true
            }
        }
        if (let Some(comma) <- auth.indexOf(",")) {
            try {
                let parsedReadFd = Int32.parse(auth[..comma])
                let parsedWriteFd = Int32.parse(auth[comma + 1..])
                if (parsedReadFd < 0 || parsedReadFd >= 1024 || parsedWriteFd < 0) {
                    return false
                }
                readFd = parsedReadFd
                writeFd = parsedWriteFd
                ownsDescriptors = false
                return true
            } catch (_: Exception) {
                return false
            }
        }
        return false
    }

    @When[os == "Windows" || env == "ohos" || env == "android"]
    private func InitializeJobserver(_: String): Bool {
        return false
    }

    @When[os == "Linux" || os == "macOS" || os == "iOS"]
    private func TryReadToken(): Option<UInt8> {
        var result: Option<UInt8> = None
        try (readSet = LibC.malloc<JobserverFdSet>().asResource(),
            timeout = LibC.malloc<JobserverTimeval>().asResource(),
            token = LibC.malloc<UInt8>().asResource()) {
            if (readSet.value.isNull() || timeout.value.isNull() || token.value.isNull()) {
                result = None
            } else {
                JobserverFdZero(readSet.value)
                if (JobserverFdAdd(readFd, readSet.value)) {
                    unsafe { timeout.value.write(JobserverTimeval(0, 0)) }
                    let ready = unsafe {
                        select(readFd + 1, readSet.value, CPointer<JobserverFdSet>(),
                            CPointer<JobserverFdSet>(), timeout.value)
                    }
                    if (ready > 0 && unsafe { read(readFd, token.value, UIntNative(1)) } == 1) {
                        result = Some(unsafe { token.value.read() })
                    }
                }
            }
        }
        return result
    }

    @When[os == "Windows" || env == "ohos" || env == "android"]
    private func TryReadToken(): Option<UInt8> {
        return None
    }

    @When[os == "Linux" || os == "macOS" || os == "iOS"]
    private func WriteToken(tokenValue: UInt8): Unit {
        try (token = LibC.malloc<UInt8>().asResource()) {
            if (!token.value.isNull()) {
                unsafe {
                    token.value.write(tokenValue)
                    let _ = write(writeFd, token.value, UIntNative(1))
                }
            }
        }
    }

    @When[os == "Windows" || env == "ohos" || env == "android"]
    private func WriteToken(_: UInt8): Unit {}

    private func ReleaseAllAtExit(): Unit {
        synchronized(mutex) {
            if ((getVariable("CJCJ_JOBSERVER_TRACE") ?? "") == "1") {
                println("CJCJ_JOBSERVER acquired=${acquiredCount} released=${releasedCount} " +
                    "active=${activeCount} peak=${peakActiveCount} held_tokens=${heldTokens.size}")
            }
            for (token in heldTokens) {
                WriteToken(token)
            }
            heldTokens.clear()
            implicitHeld = false
            localHeld = 0
            CloseJobserver()
        }
    }

    @When[os == "Linux" || os == "macOS" || os == "iOS"]
    private func CloseJobserver(): Unit {
        if (ownsDescriptors && readFd >= 0) {
            let _ = unsafe { close(readFd) }
        }
        readFd = -1
        writeFd = -1
        ownsDescriptors = false
        jobserverReady = false
    }

    @When[os == "Windows" || env == "ohos" || env == "android"]
    private func CloseJobserver(): Unit {
        readFd = -1
        writeFd = -1
        ownsDescriptors = false
        jobserverReady = false
    }
}
