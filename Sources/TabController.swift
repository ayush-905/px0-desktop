import AppKit
import WebKit

/// A window holding one tab: the start page, or the page of a px0 session.
/// Tabs are native window tabs, so each one is its own NSWindow.
final class TabController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private(set) var session: Px0Session?
    /// Path and query to open once the session is ready, from a restored tab.
    private var restorePath: String?
    private var showingProgress = false
    private var closeConfirmed = false

    private var app: AppDelegate { NSApp.delegate as! AppDelegate }

    static func configuration(bridge: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let preferences = configuration.preferences
        // "Inspect Element" in the context menu.
        if preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) {
            preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        let content = configuration.userContentController
        content.addUserScript(WKUserScript(source: ScriptBridge.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(ThemeScript.userScript)
        content.add(bridge, name: ScriptBridge.name)
        return configuration
    }

    init(configuration: WKWebViewConfiguration) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        webView = WKWebView(frame: frame, configuration: configuration)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "px0"
        window.tabbingIdentifier = "px0"
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init(window: window)
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(macOS 13.3, *) { webView.isInspectable = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isStartPage: Bool { session == nil }

    /// Whether a px0 page is loaded, rather than the app's own pages.
    var isShowingPx0: Bool {
        guard session != nil, let url = webView.url else { return false }
        return Self.isLocal(url)
    }

    func showStartPage() {
        session = nil
        restorePath = nil
        showingProgress = false
        webView.loadHTMLString(Pages.start(), baseURL: nil)
        updateTitle()
    }

    func show(_ session: Px0Session, restorePath: String? = nil) {
        self.session = session
        self.restorePath = restorePath
        showingProgress = false
        render()
    }

    /// For a tab opened from a px0 page (a target=_blank link, ⌘-click), which loads its own page.
    func attach(_ session: Px0Session?) {
        self.session = session
        updateTitle()
    }

    func render() {
        guard let session else { return }
        switch session.state {
        case .starting(let progress):
            if showingProgress {
                let text = (try? JSONEncoder().encode(progress ?? "")).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
                webView.evaluateJavaScript("document.getElementById('progress').textContent = \(text)")
            } else {
                showingProgress = true
                webView.loadHTMLString(Pages.opening(session.title, progress: progress), baseURL: nil)
            }
        case .ready(let server):
            showingProgress = false
            if !isShowing(server) {
                let url = restorePath.flatMap { URL(string: $0, relativeTo: server)?.absoluteURL } ?? server
                restorePath = nil
                webView.load(URLRequest(url: url))
            }
        case .failed(let message):
            showingProgress = false
            webView.loadHTMLString(Pages.failed(session.title, message: message), baseURL: nil)
        }
        updateTitle()
    }

    func updateTitle() {
        guard let window else { return }
        window.title = session?.title ?? "px0"
        // A folder gets the title bar's proxy icon: ⌘-click the title for its path.
        if let session, !session.isPullRequest, let workspace = session.workspace {
            window.representedURL = URL(fileURLWithPath: workspace)
        } else {
            window.representedURL = nil
        }
    }

    /// The px0 page's path and query, to reopen the tab there at next launch.
    var currentPath: String? {
        guard let url = webView.url, Self.isLocal(url),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return restorePath }
        return parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    /// Asks the page what a browser would before closing it: px0 cancels
    /// `beforeunload` while a file has unsaved edits or a coding agent is writing.
    func hasUnsavedWork(_ completion: @escaping (Bool) -> Void) {
        guard isShowingPx0 else { return completion(false) }
        let probe = "(() => { const e = new Event('beforeunload', { cancelable: true }); dispatchEvent(e); return e.defaultPrevented; })()"
        webView.evaluateJavaScript(probe) { result, _ in completion(result as? Bool ?? false) }
    }

    private func isShowing(_ server: URL) -> Bool {
        guard let url = webView.url, Self.isLocal(url) else { return false }
        return url.host == server.host && url.port == server.port
    }

    static func isLocal(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }

    // MARK: - Menu actions

    @objc func reloadPage(_ sender: Any?) {
        if let session, case .failed = session.state {
            app.retry(self)
        } else if isStartPage {
            showStartPage()
        } else {
            webView.reload()
        }
    }

    @objc func closeWindow(_ sender: Any?) {
        for window in window?.tabbedWindows ?? [window].compactMap({ $0 }) {
            window.performClose(sender)
        }
    }

    /// The tab bar's + button.
    override func newWindowForTab(_ sender: Any?) {
        app.makeTab(after: window).showStartPage()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeConfirmed || !isShowingPx0 { return true }
        hasUnsavedWork { [weak self] unsaved in
            guard let self else { return }
            guard unsaved else {
                self.closeConfirmed = true
                sender.close()
                return
            }
            let alert = NSAlert()
            alert.messageText = "Close \(self.session?.title ?? "this tab")?"
            alert.informativeText = "px0 has unsaved changes here, or a coding agent is still working. Closing the tab discards them."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { response in
                guard response == .alertFirstButtonReturn else { return }
                self.closeConfirmed = true
                sender.close()
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        app.tabClosed(self)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        switch url.scheme {
        case "px0-desktop":
            app.handle(command: url, from: self)
            return decisionHandler(.cancel)
        case "file":
            // A folder or file dropped on the window.
            app.open(target: url.path, from: self)
            return decisionHandler(.cancel)
        case "about", "data", "blob":
            return decisionHandler(.allow)
        default:
            break
        }
        if Self.isLocal(url) {
            // ⌘-click opens a px0 link in a new tab, as in a browser.
            if navigationAction.navigationType == .linkActivated, navigationAction.modifierFlags.contains(.command) {
                app.openTab(sharing: session, loading: url, after: window)
                return decisionHandler(.cancel)
            }
            return decisionHandler(.allow)
        }
        if navigationAction.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
        // GitHub, docs, mailto: and the rest belong to the default browser and apps.
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        app.debugSnapshot(of: self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let error = error as NSError
        // Loads stopped on purpose, such as links handed to the browser above.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return }
        guard let session else { return }
        webView.loadHTMLString(Pages.failed(session.title, message: error.localizedDescription), baseURL: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - WKUIDelegate

    /// target=_blank and window.open(): px0 pages get a new tab, other sites the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty, url.scheme != "about", !Self.isLocal(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return app.openTab(sharing: session, configuration: configuration, after: window).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    private func present(_ alert: NSAlert, _ completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}

/// Gives px0's pages what they would otherwise ask the px0 server for.
final class ScriptBridge: NSObject, WKScriptMessageHandler {
    static let name = "px0desktop"

    /// px0's command palette opens a pull request by asking its server to
    /// start another px0, which then opens a browser tab. Here it becomes a
    /// tab of this app instead.
    static let source = """
    (() => {
      const send = window.fetch;
      window.fetch = function (input, init) {
        try {
          const url = new URL(input instanceof Request ? input.url : String(input), location.href);
          const method = String((init && init.method) || (input instanceof Request && input.method) || 'GET').toUpperCase();
          if (method === 'POST' && url.pathname.endsWith('/api/pr/launch') && init && typeof init.body === 'string') {
            const target = JSON.parse(init.body).target;
            if (target) {
              window.webkit.messageHandlers.\(name).postMessage({ openPullRequest: String(target) });
              return Promise.resolve(new Response('{"ok":true}', { headers: { 'Content-Type': 'application/json' } }));
            }
          }
        } catch (e) {}
        return send.apply(this, arguments);
      };
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let target = body["openPullRequest"] as? String else { return }
        (NSApp.delegate as? AppDelegate)?.openPullRequest(target, from: message.webView)
    }
}
