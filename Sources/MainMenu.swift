import AppKit
import WebKit

/// The menu bar. px0's pages see key presses first, so its own shortcuts
/// (⌘P, ⌘F, ⌘W for a file tab, …) win over these whenever px0 uses them.
enum MainMenu {
    static func make(recentMenuDelegate: NSMenuDelegate) -> NSMenu {
        let name = "px0 Desktop"
        let menu = NSMenu()

        menu.addItem(submenu(name, [
            item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recent = submenu("Open Recent", [])
        recent.submenu?.delegate = recentMenuDelegate
        // In a px0 page ⌘W closes the file tab, as in an editor, and ⇧⌘W the px0 tab.
        // On the app's own pages ⌘W closes the tab.
        let close = item("Close", #selector(NSWindow.performClose(_:)), "w")
        close.isHidden = true
        close.allowsKeyEquivalentWhenHidden = true
        menu.addItem(submenu("File", [
            item("New Tab", #selector(AppDelegate.newTab(_:)), "t"),
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n"),
            .separator(),
            item("Open Folder…", #selector(AppDelegate.openFolder(_:)), "o"),
            item("Open Pull Request…", #selector(AppDelegate.openPullRequest(_:)), "o", [.command, .option]),
            recent,
            .separator(),
            close,
            item("Close Tab", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            item("Close Window", #selector(TabController.closeWindow(_:)), "w", [.command, .option]),
        ]))

        menu.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))

        let zoomInWithPlus = item("Zoom In", #selector(AppDelegate.zoomInPage(_:)), "+")
        zoomInWithPlus.isHidden = true
        zoomInWithPlus.allowsKeyEquivalentWhenHidden = true
        menu.addItem(submenu("View", [
            item("Reload Page", #selector(TabController.reloadPage(_:)), "r"),
            .separator(),
            item("Actual Size", #selector(AppDelegate.actualSizePage(_:)), "0"),
            item("Zoom In", #selector(AppDelegate.zoomInPage(_:)), "="),
            zoomInWithPlus,
            item("Zoom Out", #selector(AppDelegate.zoomOutPage(_:)), "-"),
            .separator(),
            item("Back", #selector(WKWebView.goBack(_:)), "["),
            item("Forward", #selector(WKWebView.goForward(_:)), "]"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        // px0 uses ⌃Tab for its own file tabs, so these get the browser shortcuts.
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Select Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "{"),
            item("Select Next Tab", #selector(NSWindow.selectNextTab(_:)), "}"),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        menu.addItem(window)
        NSApp.windowsMenu = window.submenu

        let help = submenu("Help", [
            item("px0 Website", #selector(AppDelegate.openPx0Website(_:))),
            item("px0 on GitHub", #selector(AppDelegate.openPx0GitHub(_:))),
            .separator(),
            item("Show px0 Log", #selector(AppDelegate.showLog(_:))),
        ])
        menu.addItem(help)
        NSApp.helpMenu = help.submenu

        return menu
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }
}
