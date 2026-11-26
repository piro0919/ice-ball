import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// LSUIElement in Info.plist already hides the Dock icon; this keeps it hidden when run
// as a bare executable during development.
app.setActivationPolicy(.accessory)
app.run()
