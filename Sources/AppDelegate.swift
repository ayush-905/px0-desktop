import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var tabs: [TabController] = []
    private let bridge = ScriptBridge()
    private var launched = false
    private var launchTargets: [String] = []
    private var quitConfirmed = false
    private var terminationSignal: DispatchSourceSignal?
    private var debugSnapshotPath: String?

    // MARK: - Launch and quit

    func applicationWillFinishLaunching(_ notification: Notification) {
        Log.start()
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.make(recentMenuDelegate: self)
        // `open -a "px0 Desktop" https://github.com/owner/repo/pull/1` arrives as a get-URL event.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:replyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        // `kill` quits as cleanly as ⌘Q.
        signal(SIGTERM, SIG_IGN)
        terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSignal?.setEventHandler {
            // Quit from the run loop, not from inside this main-queue block: the
            // main queue would be blocked while quitting waits for the pages.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
        terminationSignal?.resume()
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--debug-snapshot"), flag + 1 < arguments.count {
            debugSnapshotPath = arguments[flag + 1]
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Px0Environment.shared.whenResolved { [weak self] in self?.refreshStartPages() }
        restoreTabs()
        launched = true
        launchTargets.forEach { open(target: $0) }
        launchTargets.removeAll()
        if tabs.isEmpty { newWindow(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && tabs.isEmpty { newWindow(nil) }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Folders dropped on the Dock icon, and `open -a "px0 Desktop" <folder>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(target: url.isFileURL ? url.path : url.absoluteString) }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        if let target = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue { open(target: target) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitConfirmed { return .terminateNow }
        let pages = tabs.filter(\.isShowingPx0)
        guard !pages.isEmpty else {
            finishQuitting()
            return .terminateNow
        }
        checkUnsavedWork(in: pages) { unsaved in
            guard !unsaved || self.confirmQuit() else { return NSApp.reply(toApplicationShouldTerminate: false) }
            self.finishQuitting()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func finishQuitting() {
        quitConfirmed = true
        saveTabs()
        // Each px0's shell would stop it once this app exits anyway; this is just sooner.
        tabs.compactMap(\.session).forEach { $0.stop() }
    }

    private final class Tally {
        var remaining: Int
        var unsaved = false
        var done = false
        init(_ remaining: Int) { self.remaining = remaining }
    }

    /// Asks each px0 page whether it has unsaved work, giving up after two
    /// seconds so that a stuck page cannot keep the app from quitting.
    private func checkUnsavedWork(in pages: [TabController], _ completion: @escaping (Bool) -> Void) {
        let tally = Tally(pages.count)
        let finish = { (unsaved: Bool) in
            guard !tally.done else { return }
            tally.done = true
            // Always later: applicationShouldTerminate has to return before it gets a reply.
            RunLoop.main.perform(inModes: [.common]) { completion(unsaved) }
        }
        for page in pages {
            page.hasUnsavedWork { unsaved in
                tally.unsaved = tally.unsaved || unsaved
                tally.remaining -= 1
                if tally.remaining == 0 { finish(tally.unsaved) }
            }
        }
        RunLoop.main.add(Timer(timeInterval: 2, repeats: false) { _ in finish(tally.unsaved) }, forMode: .common)
    }

    private func confirmQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit px0 Desktop?"
        alert.informativeText = "Some tabs have unsaved changes, or a coding agent that is still working. Quitting discards them."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Tabs and windows

    private var pageZoom: CGFloat {
        let saved = UserDefaults.standard.double(forKey: "PageZoom")
        return saved > 0 ? CGFloat(saved) : 1
    }

    private var keyTab: TabController? {
        tabs.first { $0.window === NSApp.keyWindow } ?? tabs.first { $0.window === NSApp.mainWindow }
    }

    @discardableResult
    func makeWindow(configuration: WKWebViewConfiguration? = nil) -> TabController {
        let tab = makeController(configuration)
        let window = tab.window!
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame px0.window") != nil
        if window.setFrameAutosaveName("px0.window") {
            if !hasSavedFrame { window.center() }
        } else if let front = tabs.last(where: { $0 !== tab && $0.window?.isVisible == true })?.window {
            window.setFrame(front.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        }
        tab.showWindow(nil)
        return tab
    }

    @discardableResult
    func makeTab(after anchor: NSWindow?, configuration: WKWebViewConfiguration? = nil) -> TabController {
        guard let anchor = anchor ?? keyTab?.window, tabs.contains(where: { $0.window === anchor }) else {
            return makeWindow(configuration: configuration)
        }
        let tab = makeController(configuration)
        anchor.addTabbedWindow(tab.window!, ordered: .above)
        tab.window!.makeKeyAndOrderFront(nil)
        return tab
    }

    private func makeController(_ configuration: WKWebViewConfiguration?) -> TabController {
        let tab = TabController(configuration: configuration ?? TabController.configuration(bridge: bridge))
        tab.webView.pageZoom = pageZoom
        tabs.append(tab)
        return tab
    }

    /// A tab opened from a px0 page, showing that page's px0.
    @discardableResult
    func openTab(sharing session: Px0Session?, loading url: URL? = nil,
                 configuration: WKWebViewConfiguration? = nil, after anchor: NSWindow?) -> TabController {
        let tab = makeTab(after: anchor, configuration: configuration)
        tab.attach(session)
        if let url { tab.webView.load(URLRequest(url: url)) }
        return tab
    }

    func tabClosed(_ tab: TabController) {
        tabs.removeAll { $0 === tab }
        release(tab.session)
    }

    /// Stops a px0 once no tab shows it.
    private func release(_ session: Px0Session?) {
        guard let session, !tabs.contains(where: { $0.session === session }) else { return }
        session.stop()
    }

    private func refreshStartPages() {
        tabs.filter(\.isStartPage).forEach { $0.showStartPage() }
    }

    // MARK: - Opening folders and pull requests

    /// Opens a folder path or pull request URL in the start-page tab it came
    /// from, or the front start-page tab, and otherwise in a new tab.
    func open(target raw: String, from source: TabController? = nil, directory: URL? = nil) {
        guard launched else { return launchTargets.append(raw) }
        let target = Self.normalized(raw)
        if let existing = tabs.first(where: { $0.session?.target == target }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let front = source ?? keyTab
        let tab = front.flatMap { $0.isStartPage ? $0 : nil } ?? makeTab(after: front?.window)
        start(target, in: tab, directory: directory)
    }

    func openPullRequest(_ target: String, from webView: WKWebView?) {
        let source = tabs.first { $0.webView === webView }
        // From inside a clone, px0 checks the pull request out as a worktree of it.
        open(target: target, from: source, directory: source?.session?.workspace.map { URL(fileURLWithPath: $0) })
    }

    func retry(_ tab: TabController) {
        guard let old = tab.session else { return }
        start(old.target, in: tab, directory: old.directory)
        release(old)
    }

    private func start(_ target: String, in tab: TabController, directory: URL? = nil, restorePath: String? = nil) {
        let directory = directory ?? (Px0Session.isPullRequest(target) ? Recents.clone(forPullRequest: target) : nil)
        let session = Px0Session(target: target, directory: directory)
        session.onChange = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionChanged(session)
        }
        let previous = tab.session
        tab.show(session, restorePath: restorePath)
        release(previous)
        Px0Environment.shared.whenResolved { session.start() }
    }

    private func sessionChanged(_ session: Px0Session) {
        for tab in tabs where tab.session === session { tab.render() }
        if case .ready = session.state, !session.recorded {
            session.recorded = true
            Recents.add(Recent(target: session.target, title: session.title, detail: session.detail))
            refreshStartPages()
        }
    }

    private static func normalized(_ target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if Px0Session.isPullRequest(trimmed) { return trimmed }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
    }

    private func chooseFolder(for tab: TabController?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"
        panel.message = "Choose a folder to open in px0."
        let opened: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls { self.open(target: url.path, from: tab) }
        }
        if let window = tab?.window { panel.beginSheetModal(for: window, completionHandler: opened) } else { panel.begin(completionHandler: opened) }
    }

    private func askForPullRequest(for tab: TabController?) {
        let alert = NSAlert()
        alert.messageText = "Open a Pull Request"
        alert.informativeText = "Paste the URL of the pull request to review."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://github.com/owner/repo/pull/123"
        if let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           copied.hasPrefix("https://"), copied.contains("/pull/") {
            field.stringValue = copied
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let answered: (NSApplication.ModalResponse) -> Void = { response in
            let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn, !url.isEmpty { self.open(target: url, from: tab) }
        }
        if let window = tab?.window { alert.beginSheetModal(for: window, completionHandler: answered) } else { answered(alert.runModal()) }
    }

    /// Links on the app's own pages (px0-desktop://open-folder and the like).
    func handle(command url: URL, from tab: TabController) {
        let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "target" }?.value
        switch url.host {
        case "open-folder": chooseFolder(for: tab)
        case "open-pr": askForPullRequest(for: tab)
        case "open": if let target { open(target: target, from: tab) }
        case "forget":
            if let target { Recents.remove(target) }
            refreshStartPages()
        case "retry": retry(tab)
        case "start":
            let previous = tab.session
            tab.showStartPage()
            release(previous)
        case "log": showLog(nil)
        case "recheck": Px0Environment.shared.refresh { [weak self] in self?.refreshStartPages() }
        default: break
        }
    }

    // MARK: - Restoring tabs

    private struct SavedTab: Codable {
        var target: String?
        var path: String?
    }

    private struct SavedWindow: Codable {
        var tabs: [SavedTab]
        var selected: Int
    }

    private func saveTabs() {
        var windows: [[NSWindow]] = []
        // Back to front, so the front window is restored last, on top.
        let ordered = NSApp.orderedWindows.reversed() + tabs.compactMap(\.window)
        for window in ordered where tabs.contains(where: { $0.window === window }) {
            let group = window.tabbedWindows ?? [window]
            if !windows.contains(where: { $0.contains { $0 === window } }) { windows.append(group) }
        }
        let saved = windows.map { group in
            SavedWindow(tabs: group.compactMap { window in tabs.first { $0.window === window } }
                            .map { SavedTab(target: $0.session?.target, path: $0.currentPath) },
                        selected: group.firstIndex { $0 === $0.tabGroup?.selectedWindow } ?? 0)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "OpenTabs")
    }

    private func restoreTabs() {
        guard let data = UserDefaults.standard.data(forKey: "OpenTabs"),
              let windows = try? JSONDecoder().decode([SavedWindow].self, from: data) else { return }
        for saved in windows where !saved.tabs.isEmpty {
            var group: [TabController] = []
            for savedTab in saved.tabs {
                let tab = group.first.map { makeTab(after: $0.window) } ?? makeWindow()
                if let target = savedTab.target {
                    start(target, in: tab, restorePath: savedTab.path)
                } else {
                    tab.showStartPage()
                }
                group.append(tab)
            }
            group[min(max(saved.selected, 0), group.count - 1)].window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Menu actions

    @objc func newTab(_ sender: Any?) {
        makeTab(after: keyTab?.window).showStartPage()
    }

    @objc func newWindow(_ sender: Any?) {
        makeWindow().showStartPage()
    }

    @objc func openFolder(_ sender: Any?) {
        chooseFolder(for: keyTab)
    }

    @objc func openPullRequest(_ sender: Any?) {
        askForPullRequest(for: keyTab)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let target = sender.representedObject as? String { open(target: target) }
    }

    @objc func clearRecent(_ sender: Any?) {
        Recents.clear()
        refreshStartPages()
    }

    @objc func actualSizePage(_ sender: Any?) { setZoom(1) }
    @objc func zoomInPage(_ sender: Any?) { setZoom(pageZoom + 0.1) }
    @objc func zoomOutPage(_ sender: Any?) { setZoom(pageZoom - 0.1) }

    private func setZoom(_ zoom: CGFloat) {
        let zoom = min(max((zoom * 10).rounded() / 10, 0.5), 3)
        UserDefaults.standard.set(Double(zoom), forKey: "PageZoom")
        tabs.forEach { $0.webView.pageZoom = zoom }
    }

    @objc func showLog(_ sender: Any?) {
        NSWorkspace.shared.open(Log.url)
    }

    @objc func openPx0Website(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://px0.ai")!)
    }

    @objc func openPx0GitHub(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/px0-ai/px0")!)
    }

    /// File ▸ Open Recent.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for recent in Recents.all {
            let item = NSMenuItem(title: "\(recent.title) — \(recent.detail)", action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = recent.target
            item.target = self
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            menu.addItem(NSMenuItem(title: "No Recent Items", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    // MARK: - Debugging

    /// `--debug-snapshot <file.png>` saves each page as it finishes loading.
    func debugSnapshot(of tab: TabController) {
        guard let path = debugSnapshotPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tab.webView.takeSnapshot(with: nil) { image, _ in
                guard let tiff = image?.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
