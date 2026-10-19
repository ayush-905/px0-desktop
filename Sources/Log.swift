import Foundation

/// ~/Library/Logs/px0-desktop.log: px0's output from every tab, started fresh
/// at each launch.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/px0-desktop.log")
    private static var handle: FileHandle?

    static func start() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    static func write(_ line: String) {
        handle?.write(Data((line + "\n").utf8))
    }
}
