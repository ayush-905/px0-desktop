import Foundation

/// The app's own pages: the start page, and what a tab shows while px0 starts
/// or when it cannot. Their links use the px0-desktop: scheme, which
/// AppDelegate.handle(command:from:) answers.
enum Pages {
    static func start() -> String {
        let environment = Px0Environment.shared
        var body = """
        <div class="mark">px<b>0</b></div>
        <p class="lede">Review a folder or a pull request.</p>
        """
        if environment.isResolved && environment.executable == nil {
            body += """
            <div class="notice">
              <p><strong>px0 isn't installed</strong>, or it isn't on your shell's PATH. Install it from a terminal, then check again.</p>
              <code>curl -fsSL https://px0.ai/install.sh | sh</code>
              <div class="actions"><a class="btn primary" href="px0-desktop://recheck">Check Again</a></div>
            </div>
            """
        } else {
            body += """
            <div class="actions">
              <a class="btn primary" href="px0-desktop://open-folder">Open Folder… <kbd>⌘O</kbd></a>
              <a class="btn" href="px0-desktop://open-pr">Open Pull Request… <kbd>⌥⌘O</kbd></a>
            </div>
            """
        }
        let recents = Recents.all
        if !recents.isEmpty {
            body += "<h2>Recent</h2><ul>" + recents.map(row).joined() + "</ul>"
        }
        let version = environment.version.map { " · px0 \(escape($0))" } ?? ""
        body += """
        <footer>Drop a folder on this window, or run <code>open -a "px0 Desktop" .</code> in a terminal\(version)</footer>
        """
        return page(body, title: "px0")
    }

    static func opening(_ name: String, progress: String?) -> String {
        page("""
        <div class="spinner"></div>
        <h1>Opening \(escape(name))…</h1>
        <p id="progress" class="dim">\(escape(progress ?? ""))</p>
        """, title: name, centered: true)
    }

    static func failed(_ name: String, message: String) -> String {
        page("""
        <h1>Couldn't open \(escape(name))</h1>
        <pre>\(escape(message))</pre>
        <div class="actions">
          <a class="btn primary" href="px0-desktop://retry">Try Again</a>
          <a class="btn" href="px0-desktop://start">Start Page</a>
          <a class="btn" href="px0-desktop://log">Show Log</a>
        </div>
        """, title: name)
    }

    static let notInstalledMessage = """
    px0 isn't installed, or it isn't on your shell's PATH.

    Install it from a terminal:
      curl -fsSL https://px0.ai/install.sh | sh
    """

    /// Percent-encodes a query value, '+' included: px0-desktop links are read back with URLComponents.
    static func queryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func row(_ recent: Recent) -> String {
        let target = queryValue(recent.target)
        let icon = Px0Session.isPullRequest(recent.target) ? pullRequestIcon : folderIcon
        return """
        <li><a class="row" href="px0-desktop://open?target=\(target)" title="\(escape(recent.target))">\(icon)\
        <span class="name">\(escape(recent.title))</span><span class="detail">\(escape(recent.detail))</span></a>\
        <a class="forget" href="px0-desktop://forget?target=\(target)" title="Remove from Recent">×</a></li>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func page(_ body: String, title: String, centered: Bool = false) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title><style>\(css)</style></head>
        <body><div class="wrap"><main\(centered ? " class=\"centered\"" : "")>
        \(body)
        </main></div></body></html>
        """
    }

    private static let folderIcon = """
    <svg class="icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round">\
    <path d="M1.75 4.25v8a1 1 0 0 0 1 1h10.5a1 1 0 0 0 1-1v-6.5a1 1 0 0 0-1-1H8L6.5 3.25H2.75a1 1 0 0 0-1 1Z"/></svg>
    """

    private static let pullRequestIcon = """
    <svg class="icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">\
    <circle cx="4" cy="3.5" r="1.6"/><circle cx="4" cy="12.5" r="1.6"/><circle cx="12" cy="12.5" r="1.6"/>\
    <path d="M4 5.1v5.8M12 10.9V6.5a2 2 0 0 0-2-2H7.2m0 0 1.6-1.5M7.2 4.5 8.8 6"/></svg>
    """

    private static let css = """
    :root {
      color-scheme: light dark;
      --bg: #f7f7f5; --panel: #ffffff; --line: #e3e3df; --hover: #f0f0ec;
      --fg: #1c1c1e; --dim: #6b6b70; --faint: #98989d; --accent: #ff8700;
    }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #161719; --panel: #1e1f22; --line: #2e2f34; --hover: #26272b;
              --fg: #e9e9ea; --dim: #a1a1a6; --faint: #6f6f75; }
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; height: 100%; }
    body { background: var(--bg); color: var(--fg); cursor: default; -webkit-user-select: none;
           font: 13px/1.45 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; -webkit-font-smoothing: antialiased; }
    .wrap { min-height: 100%; display: flex; align-items: center; justify-content: center; padding: 48px 24px; }
    main { width: 100%; max-width: 580px; }
    main.centered { text-align: center; }
    .mark { font: 700 34px/1 ui-monospace, "SF Mono", Menlo, monospace; letter-spacing: -1px; }
    .mark b { color: var(--accent); }
    .lede, .dim { color: var(--dim); }
    .lede { margin: 10px 0 24px; }
    h1 { font-size: 17px; font-weight: 600; margin: 18px 0 8px; }
    h2 { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .06em; color: var(--faint); margin: 36px 0 8px; }
    .actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; }
    main.centered .actions { justify-content: center; }
    .lede + .actions { margin-top: 0; }
    .btn { display: inline-flex; align-items: center; gap: 10px; padding: 7px 14px; border-radius: 8px; font-weight: 500;
           border: 1px solid var(--line); background: var(--panel); color: var(--fg); text-decoration: none; }
    .btn:hover { background: var(--hover); }
    .btn.primary { background: var(--accent); border-color: var(--accent); color: #1c1c1e; }
    .btn.primary:hover { filter: brightness(1.06); }
    kbd { font: 11px ui-monospace, Menlo, monospace; opacity: .6; }
    ul { list-style: none; margin: 0; padding: 0; border: 1px solid var(--line); border-radius: 10px; background: var(--panel); overflow: hidden; }
    li { display: flex; align-items: center; border-top: 1px solid var(--line); }
    li:first-child { border-top: 0; }
    li:hover { background: var(--hover); }
    .row { flex: 1; min-width: 0; display: flex; align-items: center; gap: 10px; padding: 9px 4px 9px 12px; color: inherit; text-decoration: none; }
    .icon { width: 16px; height: 16px; flex: none; color: var(--dim); }
    .name { font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: none; max-width: 55%; }
    .detail { color: var(--faint); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-left: auto; padding-left: 12px; }
    .forget { padding: 6px 12px; color: var(--faint); text-decoration: none; font-size: 15px; visibility: hidden; }
    li:hover .forget { visibility: visible; }
    .forget:hover { color: var(--fg); }
    .notice { border: 1px solid var(--line); background: var(--panel); border-radius: 10px; padding: 4px 16px 16px; }
    footer { margin-top: 28px; color: var(--faint); font-size: 12px; }
    code { font: 12px ui-monospace, Menlo, monospace; background: var(--panel); border: 1px solid var(--line);
           border-radius: 5px; padding: 1px 5px; -webkit-user-select: all; }
    .notice code { display: inline-block; padding: 6px 10px; }
    pre { text-align: left; white-space: pre-wrap; word-break: break-word; max-height: 50vh; overflow: auto;
          font: 12px/1.5 ui-monospace, Menlo, monospace; color: var(--dim); -webkit-user-select: text; cursor: text;
          background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; }
    .spinner { width: 22px; height: 22px; margin: 0 auto; border-radius: 50%;
               border: 2px solid var(--line); border-top-color: var(--accent); animation: spin .8s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
    """
}
