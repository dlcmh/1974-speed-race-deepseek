import AppKit
import Metal

// Speed Race (1974) — Swift + Metal port.
//
// Window and application lifecycle, matching src/main.rs's `window_conf`:
// a resizable 960 x 720 window titled "SPEED RACE - Taito 1974", high-DPI
// aware, with no mouse capture.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var view: GameView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            presentFatal("This Mac has no Metal device, so Speed Race cannot render.")
            return
        }
        let frame = CGRect(x: 0, y: 0, width: 960, height: 720)
        do {
            let view = try GameView(frame: frame, device: device)
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            window.title = "SPEED RACE - Taito 1974"
            window.contentView = view
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            window.minSize = NSSize(width: 480, height: 360)
            self.window = window
            self.view = view
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            presentFatal("Speed Race could not start Metal: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Speed Race"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}
