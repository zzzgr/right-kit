import Darwin
import Foundation

public enum ScriptRunState: String, Sendable {
    case running, succeeded, failed, cancelled, timedOut

    public var title: String {
        switch self {
        case .running: return Strings.Custom.running
        case .succeeded: return Strings.Custom.succeeded
        case .failed: return Strings.Custom.failed
        case .cancelled: return Strings.Custom.cancelled
        case .timedOut: return Strings.Custom.timedOut
        }
    }
}

public struct ScriptRunSnapshot: Sendable {
    public var state: ScriptRunState = .running
    public var stdout = ""
    public var stderr = ""
    public var stdoutTruncated = false
    public var stderrTruncated = false
    public var exitCode: Int32?
    public var error: String?
    public var duration: TimeInterval = 0
    public var completedInvocations = 0
    public var totalInvocations = 1

    public init() {}
}

/// Cancellation is observed by the worker, which owns the process group. Keeping
/// signals off the caller's thread also prevents signalling a stale/reused PID.
public final class ScriptRunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    fileprivate var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Used identically by Finder handoffs and manual draft tests. No shell command is
/// assembled: selected paths are literal argv entries, even when they contain shell
/// syntax. Callbacks run on the worker queue; UI consumers dispatch to MainActor.
public enum ScriptRunner {
    @discardableResult
    public static func start(
        action: CustomAction,
        in context: ActionContext,
        secrets: [UUID: String] = [:],
        onUpdate: @escaping (ScriptRunSnapshot) -> Void = { _ in },
        completion: @escaping (ScriptRunSnapshot) -> Void
    ) -> ScriptRunHandle {
        let handle = ScriptRunHandle()
        DispatchQueue.global(qos: .utility).async {
            let worker = ScriptWorker(action: action, context: context, secrets: secrets, handle: handle, onUpdate: onUpdate)
            completion(worker.run())
        }
        return handle
    }
}

private final class ScriptWorker {
    private let action: CustomAction
    private let context: ActionContext
    private let secrets: [UUID: String]
    private let handle: ScriptRunHandle
    private let onUpdate: (ScriptRunSnapshot) -> Void
    private let started = ProcessInfo.processInfo.systemUptime
    private var lastUpdate: TimeInterval = 0
    private var snapshot = ScriptRunSnapshot()
    private var stdout = ScriptOutputBuffer()
    private var stderr = ScriptOutputBuffer()
    private var redactions: [String] = []

    init(action: CustomAction, context: ActionContext, secrets: [UUID: String], handle: ScriptRunHandle,
         onUpdate: @escaping (ScriptRunSnapshot) -> Void) {
        self.action = action
        self.context = context
        self.secrets = secrets
        self.handle = handle
        self.onUpdate = onUpdate
    }

    private var elapsed: TimeInterval { ProcessInfo.processInfo.systemUptime - started }

    func run() -> ScriptRunSnapshot {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("RightKit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try action.validate(forExecution: true)
            guard !context.targets.isEmpty, context.targets.count <= 1000,
                  context.targets.allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }),
                  context.container?.isFileURL != false else {
                throw CustomActionError.message(Strings.Custom.invalidSelection)
            }
            guard context.targets.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw CustomActionError.message(Strings.Custom.missingInput)
            }
            guard action.rules.matches(context) else { throw CustomActionError.message(Strings.Custom.invalidSelection) }
            let environment = try makeEnvironment()
            let executable = try interpreter(environment: environment)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let script: URL
            if action.source == .inline {
                script = temporary.appendingPathComponent("action.\(action.language.fileExtension)")
                try Data(action.script.utf8).write(to: script)
            } else {
                script = URL(fileURLWithPath: action.scriptPath)
                guard FileManager.default.isReadableFile(atPath: script.path), !PathUtilities.isDirectory(script) else {
                    throw CustomActionError.message(Strings.Custom.invalidScriptPath)
                }
            }

            let batches = action.batchMode == .individually ? context.targets.map { [$0] } : [context.targets]
            snapshot.totalInvocations = batches.count
            for (index, inputs) in batches.enumerated() {
                if let stopped = stopReason { snapshot.state = stopped; break }
                let directory = try workingDirectory(for: inputs)
                let contextFile = temporary.appendingPathComponent("context.json")
                let runContext = ScriptContext(
                    actionID: action.id, paths: inputs.map(\.path), allPaths: context.targets.map(\.path),
                    finderDirectory: context.container?.path, workingDirectory: directory.path,
                    invocationIndex: index + 1, invocationCount: batches.count
                )
                try JSONEncoder().encode(runContext).write(to: contextFile, options: .atomic)
                var invocationEnvironment = environment
                invocationEnvironment["RIGHTKIT_INPUTS_JSON"] = String(decoding: try JSONEncoder().encode(inputs.map(\.path)), as: UTF8.self)
                invocationEnvironment["RIGHTKIT_CONTEXT_FILE"] = contextFile.path
                invocationEnvironment["RIGHTKIT_CURRENT_DIRECTORY"] = directory.path
                invocationEnvironment["RIGHTKIT_INPUT_COUNT"] = String(inputs.count)
                invocationEnvironment["PWD"] = directory.path
                let arguments = interpreterArguments + [script.path] + inputs.map(\.path)
                snapshot.exitCode = try execute(executable: executable, arguments: arguments, environment: invocationEnvironment, directory: directory)
                if snapshot.state != .running { break }
                snapshot.completedInvocations += 1
                if snapshot.exitCode != 0 {
                    snapshot.state = .failed
                    break
                }
            }
            if snapshot.state == .running { snapshot.state = .succeeded }
        } catch {
            snapshot.state = stopReason ?? .failed
            snapshot.error = ScriptOutputBuffer.redact(error.localizedDescription, secrets: redactions)
        }
        return currentSnapshot(final: true)
    }

    private var stopReason: ScriptRunState? {
        if handle.isCancelled { return .cancelled }
        if elapsed >= Double(action.timeoutSeconds) { return .timedOut }
        return nil
    }

    private func makeEnvironment() throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let inherited = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var paths: [String] = []
        for path in commonPaths + inherited where path.hasPrefix("/") && !paths.contains(path) { paths.append(path) }
        environment["PATH"] = paths.joined(separator: ":")
        if action.language == .python {
            environment["PYTHONUNBUFFERED"] = "1"
            environment["PYTHONIOENCODING"] = "utf-8"
        }
        for variable in action.environment {
            let value: String
            if variable.isSecret {
                guard let saved = variable.value.isEmpty ? secrets[variable.id] : variable.value, !saved.isEmpty else {
                    throw CustomActionError.message(Strings.Custom.missingSecret(variable.name))
                }
                value = saved
                redactions.append(saved)
            } else {
                value = variable.value
            }
            guard !value.contains("\0"), value.utf8.count <= 16 * 1024 else {
                throw CustomActionError.message(Strings.Custom.invalidEnvironmentValue)
            }
            environment[variable.name] = value
        }
        return environment
    }

    private func interpreter(environment: [String: String]) throws -> String {
        if action.language != .python { return "/bin/\(action.language.rawValue)" }
        return try PythonInterpreter.resolve(preferredPath: action.interpreterPath, environment: environment)
    }

    private var interpreterArguments: [String] {
        switch action.language {
        case .python: return ["-u"]
        case .zsh: return ["-f"]
        case .bash: return ["--noprofile", "--norc"]
        case .sh: return []
        }
    }

    private func workingDirectory(for inputs: [URL]) throws -> URL {
        let directory: URL?
        switch action.workingDirectory {
        case .selection: directory = ActionContext(targets: inputs, container: context.container).workingDirectory
        case .finder: directory = context.creationDirectory ?? context.workingDirectory
        case .custom: directory = URL(fileURLWithPath: action.customWorkingDirectory)
        }
        guard let directory, directory.isFileURL, PathUtilities.isDirectory(directory) else {
            throw CustomActionError.message(Strings.Custom.invalidDirectory)
        }
        return directory.standardizedFileURL
    }

    private func execute(executable: String, arguments: [String], environment: [String: String], directory: URL) throws -> Int32 {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { throw systemError(errno) }
        defer { for fd in outPipe where fd >= 0 { close(fd) } }
        guard pipe(&errPipe) == 0 else { throw systemError(errno) }
        defer { for fd in errPipe where fd >= 0 { close(fd) } }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO))
        for fd in outPipe + errPipe { try check(posix_spawn_file_actions_addclose(&actions, fd)) }
        try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var mask = sigset_t()
        sigemptyset(&mask)
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        for signal in [SIGINT, SIGTERM, SIGPIPE, SIGHUP, SIGQUIT] { sigaddset(&mask, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &mask))
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)))

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv + envp { free(pointer) }
        }
        var pid: pid_t = 0
        let spawnError = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        try check(spawnError)
        close(outPipe[1]); outPipe[1] = -1
        close(errPipe[1]); errPipe[1] = -1
        _ = fcntl(outPipe[0], F_SETFL, O_NONBLOCK)
        _ = fcntl(errPipe[0], F_SETFL, O_NONBLOCK)

        var exitStatus: Int32?
        var terminationTime: TimeInterval?
        var sentKill = false
        while true {
            if snapshot.state == .running, let reason = stopReason {
                snapshot.state = reason
                terminationTime = ProcessInfo.processInfo.systemUptime
                kill(-pid, SIGTERM)
            }
            var waitStatus: Int32 = 0
            if exitStatus == nil {
                let waited = waitpid(pid, &waitStatus, WNOHANG)
                if waited == pid {
                    exitStatus = waitStatus
                    if terminationTime == nil {
                        // A shell exiting must not leave background uploads alive.
                        terminationTime = ProcessInfo.processInfo.systemUptime
                        kill(-pid, SIGTERM)
                    }
                } else if waited < 0 && errno != EINTR {
                    let failure = errno
                    kill(-pid, SIGKILL)
                    throw systemError(failure)
                }
            }
            if let terminationTime, ProcessInfo.processInfo.systemUptime - terminationTime >= 0.5, !sentKill {
                kill(-pid, SIGKILL)
                sentKill = true
            }
            var descriptors = [
                pollfd(fd: outPipe[0], events: Int16(POLLIN), revents: 0),
                pollfd(fd: errPipe[0], events: Int16(POLLIN), revents: 0)
            ]
            _ = poll(&descriptors, nfds_t(descriptors.count), 40)
            drain(&outPipe[0], into: &stdout)
            drain(&errPipe[0], into: &stderr)
            publishUpdate()
            if exitStatus != nil {
                if outPipe[0] < 0 && errPipe[0] < 0 { break }
                // A child that deliberately leaves our process group can retain a
                // pipe. Never let it hold the app's task open indefinitely.
                if let terminationTime, ProcessInfo.processInfo.systemUptime - terminationTime >= 1 { break }
            }
        }
        kill(-pid, SIGKILL)
        let status = exitStatus ?? 0
        return (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }

    private func drain(_ fd: inout Int32, into buffer: inout ScriptOutputBuffer) {
        guard fd >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        // Bound each pass so a script flooding stdout cannot starve stderr or stop.
        for _ in 0..<8 {
            let count = read(fd, &bytes, bytes.count)
            if count > 0 { buffer.append(Data(bytes.prefix(count))) }
            else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                close(fd)
                fd = -1
                break
            } else { break }
        }
    }

    private func publishUpdate() {
        if elapsed - lastUpdate >= 0.1 {
            lastUpdate = elapsed
            onUpdate(currentSnapshot(final: false))
        }
    }

    private func currentSnapshot(final: Bool) -> ScriptRunSnapshot {
        snapshot.stdout = stdout.text(secrets: redactions, final: final)
        snapshot.stderr = stderr.text(secrets: redactions, final: final)
        snapshot.stdoutTruncated = stdout.truncated
        snapshot.stderrTruncated = stderr.truncated
        snapshot.duration = elapsed
        return snapshot
    }

    private func check(_ code: Int32) throws {
        if code != 0 { throw systemError(code) }
    }

    private func systemError(_ code: Int32) -> Error {
        CustomActionError.message(Strings.Custom.launchError(String(cString: strerror(code))))
    }
}

private struct ScriptContext: Encodable {
    let actionID: UUID
    let paths: [String]
    let allPaths: [String]
    let finderDirectory: String?
    let workingDirectory: String
    let invocationIndex: Int
    let invocationCount: Int
}

/// Retains a bounded prefix but continues draining both pipes. Redaction operates
/// on the accumulated bytes so secrets split across reads never appear in logs.
struct ScriptOutputBuffer {
    static let limit = 256 * 1024
    private var bytes = Data()
    private var rawTruncated = false
    private var renderedTruncated = false
    private var cache: (count: Int, truncated: Bool, final: Bool, secrets: [String], text: String)?
    var truncated: Bool { rawTruncated || renderedTruncated }

    mutating func append(_ data: Data) {
        let remaining = Self.limit - bytes.count
        bytes.append(data.prefix(remaining))
        rawTruncated = rawTruncated || data.count > remaining
    }

    mutating func text(secrets: [String], final: Bool) -> String {
        if let cache, cache.count == bytes.count, cache.truncated == rawTruncated,
           cache.final == final, cache.secrets == secrets { return cache.text }
        let raw = Array(bytes)
        let patterns = Set(secrets.filter { !$0.isEmpty }).map { Array($0.utf8) }
        // A difference array unions all matching ranges without growing a list of
        // matches. Overlapping secrets and repeated one-byte values stay bounded.
        var coverage = [Int32](repeating: 0, count: raw.count + 1)
        var visibleEnd = raw.count
        for pattern in patterns {
            var prefix = [Int](repeating: 0, count: pattern.count)
            var matched = 0
            if pattern.count > 1 {
                for index in 1..<pattern.count {
                    while matched > 0 && pattern[index] != pattern[matched] { matched = prefix[matched - 1] }
                    if pattern[index] == pattern[matched] { matched += 1 }
                    prefix[index] = matched
                }
            }
            matched = 0
            for (index, byte) in raw.enumerated() {
                while matched > 0 && byte != pattern[matched] { matched = prefix[matched - 1] }
                if byte == pattern[matched] { matched += 1 }
                if matched == pattern.count {
                    coverage[index + 1 - pattern.count] += 1
                    coverage[index + 1] -= 1
                    matched = prefix[matched - 1]
                }
            }
            if !final || rawTruncated { visibleEnd = min(visibleEnd, raw.count - matched) }
        }
        var output = Data()
        let replacement = Data("[REDACTED]".utf8)
        var active: Int32 = 0
        var wasMasked = false
        renderedTruncated = false
        for index in 0..<visibleEnd {
            active += coverage[index]
            if active > 0 {
                if !wasMasked { output.append(replacement) }
            } else { output.append(raw[index]) }
            wasMasked = active > 0
            if output.count > Self.limit {
                output = output.prefix(Self.limit)
                renderedTruncated = true
                break
            }
        }
        let result = String(decoding: output, as: UTF8.self)
        cache = (bytes.count, rawTruncated, final, secrets, result)
        return result
    }

    static func redact(_ text: String, secrets: [String]) -> String {
        var buffer = ScriptOutputBuffer()
        buffer.append(Data(text.utf8))
        return buffer.text(secrets: secrets, final: true)
    }
}
