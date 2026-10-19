import AppKit

// px0 Desktop: px0 in native macOS windows and tabs instead of browser tabs.
// Each tab runs its own px0 server for one folder or pull request.
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
