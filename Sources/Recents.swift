import Foundation

/// A folder or pull request opened before.
struct Recent: Codable {
    var target: String
    var title: String
    var detail: String
}

/// Recently opened folders and pull requests, newest first.
enum Recents {
    private static let key = "Recents"
    private static let limit = 12

    static var all: [Recent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Recent].self, from: data)) ?? []
    }

    static func add(_ recent: Recent) {
        save([recent] + all.filter { $0.target != recent.target })
    }

    static func remove(_ target: String) {
        save(all.filter { $0.target != target })
    }

    static func clear() {
        save([])
    }

    private static func save(_ recents: [Recent]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(recents.prefix(limit))), forKey: key)
    }

    /// A recent folder that is a clone of the pull request's repository. px0
    /// checks the PR out there as a git worktree, much faster than a fresh clone.
    static func clone(forPullRequest target: String) -> URL? {
        guard let url = URL(string: target), let host = url.host?.lowercased(),
              url.pathComponents.count >= 3 else { return nil }
        let repo = "\(url.pathComponents[1])/\(url.pathComponents[2])".lowercased()
        let remotes = ["\(host)/\(repo).git", "\(host)/\(repo)\n", "\(host):\(repo).git", "\(host):\(repo)\n"]
        for recent in all where !Px0Session.isPullRequest(recent.target) {
            let config = URL(fileURLWithPath: recent.target).appendingPathComponent(".git/config")
            guard let text = try? String(contentsOf: config, encoding: .utf8).lowercased() else { continue }
            if remotes.contains(where: text.contains) { return URL(fileURLWithPath: recent.target) }
        }
        return nil
    }
}
