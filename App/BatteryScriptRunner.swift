import Foundation
import Darwin

struct BatteryScriptResult {
    let level: Int?
    let charging: Bool?
    let connected: Bool

    static func parse(_ data: Data) throws -> BatteryScriptResult {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let level = Int(text), (0...100).contains(level) {
            return BatteryScriptResult(level: level, charging: nil, connected: true)
        }
        struct Payload: Decodable {
            let level: Int?
            let charging: Bool?
            let connected: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw DeviceError.invalid(L10n.text("The script must output an integer from 0 to 100, battery JSON, or {\"connected\":false}"))
        }
        if payload.connected == false {
            return BatteryScriptResult(level: nil, charging: nil, connected: false)
        }
        guard let level = payload.level, (0...100).contains(level) else {
            throw DeviceError.invalid(L10n.text("Connected devices must report a battery level between 0 and 100"))
        }
        return BatteryScriptResult(level: level, charging: payload.charging, connected: true)
    }
}

enum BatteryScriptRunner {
    static func run(_ script: BatteryScript, deviceID: String, timeout: TimeInterval = 10) throws -> BatteryScriptResult {
        try script.validate()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let outputURL = temporary.appendingPathComponent("stdout")
        let errorURL = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["BATTERIES_DEVICE_ID"] = deviceID
        let arguments = ["/bin/zsh", "-c", script.command].map { strdup($0) }
        let variables = environment.map { strdup("\($0.key)=\($0.value)") }
        defer {
            arguments.forEach { free($0) }
            variables.forEach { free($0) }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors.fileDescriptor, STDERR_FILENO)
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, FileManager.default.homeDirectoryForCurrentUser.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, FileManager.default.homeDirectoryForCurrentUser.path)
        }
        // A separate process group lets timeouts clean up subprocesses as well as the shell.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var processID: pid_t = 0
        let code = (arguments + [nil]).withUnsafeBufferPointer { argv in
            (variables + [nil]).withUnsafeBufferPointer { envp in
                posix_spawn(&processID, "/bin/zsh", &actions, &attributes,
                            argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard code == 0 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        defer { kill(-processID, SIGKILL) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var status: Int32 = 0
        while true {
            let waited = waitpid(processID, &status, WNOHANG)
            if waited == processID { break }
            if waited < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let outputSize = (try? output.offset()) ?? 0
            let errorSize = (try? errors.offset()) ?? 0
            var failure: String?
            if outputSize + errorSize > 65536 {
                failure = L10n.text("Script output exceeds 64 KB")
            } else if ProcessInfo.processInfo.systemUptime >= deadline {
                failure = L10n.text("Script timed out after %d seconds", Int(timeout))
            }
            if let failure {
                kill(-processID, SIGKILL)
                while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
                throw DeviceError.invalid(failure)
            }
            usleep(50_000)
        }
        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        guard outputData.count + errorData.count <= 65536 else {
            throw DeviceError.invalid(L10n.text("Script output exceeds 64 KB"))
        }
        guard status == 0 else {
            let message = String(decoding: errorData.prefix(2048), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            let detail = message.isEmpty ? "" : ", " + message
            throw DeviceError.invalid(L10n.text("Script exit code %d%@", exitCode, detail))
        }
        return try BatteryScriptResult.parse(outputData)
    }
}
