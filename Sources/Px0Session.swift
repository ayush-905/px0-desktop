import Foundation

/// One px0 server showing one folder or pull request.
///
/// px0 runs under a small shell that also holds this app's end of a pipe. When
/// the pipe closes, because the tab closed or the app quit or crashed, the
/// shell stops px0 with SIGTERM, and px0 shuts its language servers down too.
/// Nothing is left running behind the app.
final class Px0Session {
    enum State {
        case starting(progress: String?)
        case ready(URL)
        case failed(String)
    }

    /// A folder path or a pull request URL.
    let target: String
    /// Where px0 starts. For a pull request, a clone of its repository makes
    /// px0 check it out as a git worktree instead of cloning it again.
    let directory: URL?
    private(set) var state: State = .starting(progress: nil) { didSet { onChange?() } }
    var onChange: (() -> Void)?
    /// "api-server" for a folder, "#123 Fix the login redirect" for a pull request.
    private(set) var title: String
    /// The folder px0 serves, as it reported it.
    private(set) var workspace: String?
    /// Whether it has been added to Recent.
    var recorded = false

    private var process: Process?
    private var keepAlive: Pipe?
    private var stopped = false
    private var partialLine = ""
    private var lines: [String] = []

    init(target: String, directory: URL?) {
        self.target = target
        self.directory = directory
        title = Self.isPullRequest(target) ? Self.pullRequestLabel(target) : (target as NSString).lastPathComponent
    }

    static func isPullRequest(_ target: String) -> Bool {
        target.hasPrefix("https://") || target.hasPrefix("http://")
    }

    var isPullRequest: Bool { Self.isPullRequest(target) }

    /// "owner/repo · pull request", or the folder with ~ for home.
    var detail: String {
        if isPullRequest, let parts = URL(string: target)?.pathComponents, parts.count >= 3 {
            return "\(parts[1])/\(parts[2]) · pull request"
        }
        return ((workspace ?? target) as NSString).abbreviatingWithTildeInPath
    }

    func start() {
        guard !stopped else { return }
        guard let px0 = Px0Environment.shared.executable else {
            state = .failed(Pages.notInstalledMessage)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", Self.watchdog, "px0-desktop", px0.path,
                             "-no-open", "-no-color", "-port", "0", target]
        process.environment = Px0Environment.shared.variables
        process.currentDirectoryURL = directory ?? FileManager.default.homeDirectoryForCurrentUser
        let keepAlive = Pipe()
        let output = Pipe()
        process.standardInput = keepAlive
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] process in
            // Let the last of the output arrive first: it usually says why.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.exited(process) }
        }
        do {
            try process.run()
        } catch {
            state = .failed("Could not run px0: \(error.localizedDescription)")
            return
        }
        self.process = process
        self.keepAlive = keepAlive
        Log.write("[\(title)] px0 \(target)")
    }

    /// Closes the pipe px0's shell waits on, so px0 gets SIGTERM and exits.
    func stop() {
        stopped = true
        try? keepAlive?.fileHandleForWriting.close()
        keepAlive = nil
    }

    private func consume(_ data: Data) {
        partialLine += String(decoding: data, as: UTF8.self)
        while let newline = partialLine.firstIndex(of: "\n") {
            let line = String(partialLine[..<newline]).replacingOccurrences(of: "\r", with: "")
            partialLine.removeSubrange(...newline)
            handle(line)
        }
    }

    /// Reads px0's startup lines:
    ///
    ///     px0 0.1.17
    ///       PR:        #123 Fix the login redirect
    ///       workspace: /Users/me/code/app
    ///       url:       http://127.0.0.1:52344/
    private func handle(_ line: String) {
        Log.write("[\(title)] \(line)")
        lines.append(line)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        guard case .starting = state else { return }
        let text = line.trimmingCharacters(in: .whitespaces)
        if let url = Self.field("url", in: text).flatMap(URL.init(string:)) {
            state = .ready(url)
        } else if let pullRequest = Self.field("PR", in: text) {
            title = pullRequest
            onChange?()
        } else if let workspace = Self.field("workspace", in: text) {
            self.workspace = workspace
            if !isPullRequest { title = (workspace as NSString).lastPathComponent }
        } else if !text.isEmpty, !text.hasPrefix("px0 "), Self.field("access", in: text) == nil {
            // Progress while a pull request is fetched, e.g. "> Cloning owner/repo...".
            state = .starting(progress: text.replacingOccurrences(of: #"^(\[[A-Z]+\]|[>›·✓✗!])\s+"#,
                                                                  with: "", options: .regularExpression))
        }
    }

    private func exited(_ process: Process) {
        guard process === self.process else { return }
        self.process = nil
        keepAlive = nil
        if !partialLine.isEmpty { handle(partialLine) }
        partialLine = ""
        Log.write("[\(title)] px0 exited with status \(process.terminationStatus)")
        guard !stopped else { return }
        let output = lines.suffix(30).joined(separator: "\n")
        if case .ready = state {
            state = .failed("px0 stopped unexpectedly (exit status \(process.terminationStatus)).\n\n\(output)")
        } else {
            state = .failed(output.isEmpty ? "px0 exited with status \(process.terminationStatus)." : output)
        }
    }

    private static func field(_ key: String, in line: String) -> String? {
        guard line.hasPrefix(key + ":") else { return nil }
        let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func pullRequestLabel(_ target: String) -> String {
        guard let number = URL(string: target)?.pathComponents.last, Int(number) != nil else { return "Pull request" }
        return "PR #\(number)"
    }

    /// Runs px0 ("$@") until this app's end of stdin closes, then stops it.
    /// It exits with px0's status if px0 stops first.
    private static let watchdog = """
    exec 3<&0
    "$@" </dev/null 3<&- &
    pid=$!
    ( while read -r _; do :; done; kill -TERM "$pid" 2>/dev/null ) <&3 &
    watcher=$!
    exec 3<&-
    wait "$pid"
    status=$?
    kill "$watcher" 2>/dev/null
    exit "$status"
    """
}
