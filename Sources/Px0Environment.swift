import Foundation

/// Where px0 is installed and the environment to run it in, found once per launch.
///
/// Apps opened from Finder or the Dock get launchd's bare environment
/// (PATH=/usr/bin:/bin:/usr/sbin:/sbin). px0 needs the user's own to find git,
/// gh, language servers and coding agents, so it is read from an interactive
/// login shell, the way VS Code does it.
final class Px0Environment {
    static let shared = Px0Environment()

    private(set) var variables = ProcessInfo.processInfo.environment
    private(set) var executable: URL?
    private(set) var version: String?
    private(set) var isResolved = false
    private var resolving = false
    private var waiting: [() -> Void] = []

    /// Runs `body` on the main thread once px0 has been looked for.
    func whenResolved(_ body: @escaping () -> Void) {
        if isResolved { return body() }
        waiting.append(body)
        guard !resolving else { return }
        resolving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let variables = Self.shellEnvironment()
            let executable = Self.findPx0(path: variables["PATH"] ?? "")
            let version = executable.flatMap { Self.version(of: $0, environment: variables) }
            DispatchQueue.main.async {
                self.variables = variables
                self.executable = executable
                self.version = version
                self.isResolved = true
                self.resolving = false
                Log.write("px0: \(executable?.path ?? "not found") \(version ?? "")")
                let waiting = self.waiting
                self.waiting = []
                waiting.forEach { $0() }
            }
        }
    }

    /// Looks again, for when px0 was installed while the app was open.
    func refresh(_ body: @escaping () -> Void) {
        if !resolving { isResolved = false }
        whenResolved(body)
    }

    private static func shellEnvironment() -> [String: String] {
        var variables = ProcessInfo.processInfo.environment
        for (key, value) in loginShellVariables() ?? [:] where !["PWD", "OLDPWD", "SHLVL", "_"].contains(key) {
            variables[key] = value
        }
        // The usual install locations, in case the shell setup does not add them.
        let home = NSHomeDirectory()
        var path = (variables["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in ["\(home)/.local/bin", "\(home)/bin", "/opt/homebrew/bin", "/usr/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !path.contains(dir) {
            path.append(dir)
        }
        variables["PATH"] = path.joined(separator: ":")
        return variables
    }

    private final class Output {
        var data = Data()
        var finished = false
    }

    private static func loginShellVariables(timeout: TimeInterval = 10) -> [String: String]? {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = Data("__px0_desktop_\(UUID().uuidString)__".utf8)
        let markerText = String(decoding: marker, as: UTF8.self)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-i", "-l", "-c", "printf %s \(markerText); /usr/bin/env -0; printf %s \(markerText)"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        // Read up to the closing marker rather than EOF: prompt helpers such as
        // gitstatusd can outlive the shell and hold the pipe open.
        let output = Output()
        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock()
            defer { lock.unlock() }
            guard !output.finished else { return }
            output.data.append(chunk)
            if chunk.isEmpty || occurrences(of: marker, in: output.data) >= 2 {
                output.finished = true
                handle.readabilityHandler = nil
                done.signal()
            }
        }
        do { try process.run() } catch { return nil }
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        lock.lock()
        let data = output.data
        lock.unlock()

        guard !timedOut,
              let open = data.range(of: marker),
              let close = data.range(of: marker, in: open.upperBound..<data.endIndex) else { return nil }
        var variables: [String: String] = [:]
        for entry in data[open.upperBound..<close.lowerBound].split(separator: 0) {
            let pair = String(decoding: entry, as: UTF8.self)
            guard let equals = pair.firstIndex(of: "=") else { continue }
            variables[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        return variables.isEmpty ? nil : variables
    }

    private static func occurrences(of needle: Data, in haystack: Data) -> Int {
        var count = 0
        var from = haystack.startIndex
        while let found = haystack.range(of: needle, in: from..<haystack.endIndex) {
            count += 1
            from = found.upperBound
        }
        return count
    }

    private static func findPx0(path: String) -> URL? {
        let files = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: "Px0Path"), files.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("px0")
            if files.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func version(of px0: URL, environment: [String: String]) -> String? {
        let process = Process()
        process.executableURL = px0
        process.arguments = ["-version"]
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // "px0 0.1.17 (darwin/arm64)"
        let words = String(decoding: data, as: UTF8.self).split(separator: " ")
        return words.count >= 2 && words[0] == "px0" ? String(words[1]) : nil
    }
}
