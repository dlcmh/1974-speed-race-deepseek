import AppKit

// Speed Race (1974) — Swift + Metal port.
//
// `.regular` activation policy gives the process a Dock icon and menu bar even
// though it is launched from a terminal (docs/DECISIONS.md P-0001).

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
