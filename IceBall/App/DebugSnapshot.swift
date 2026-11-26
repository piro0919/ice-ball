#if DEBUG
    import AppKit
    import ScreenCaptureKit

    /// Development aid: `open IceBall.app --args --snapshot <directory>` writes a PNG of
    /// the top of every display a few seconds after launch, with the overlay composited in.
    /// Needs the Screen Recording permission. Not compiled into release builds.
    enum DebugSnapshot {
        static func scheduleIfRequested() {
            let arguments = CommandLine.arguments
            // `--request-accessibility` also shows the system prompt for Accessibility.
            if arguments.contains("--request-accessibility") {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            // While running, a distributed notification named `io.kkweb.IceBall.debugSnapshot`
            // whose object is a directory path takes a snapshot right away.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("io.kkweb.IceBall.debugSnapshot"), object: nil, queue: .main
            ) { note in
                guard let path = note.object as? String else { return }
                Task { await capture(to: URL(fileURLWithPath: path)) }
            }
            guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
            let directory = URL(fileURLWithPath: arguments[index + 1])
            Task {
                try? await Task.sleep(for: .seconds(4))
                await capture(to: directory)
            }
        }

        private static func capture(to directory: URL) async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                for display in content.displays {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let scale = NSScreen.screens.first { $0.displayID == display.displayID }?.backingScaleFactor ?? 2
                    config.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: 70)
                    config.width = Int(CGFloat(display.width) * scale)
                    config.height = Int(70 * scale)
                    config.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let rep = NSBitmapImageRep(cgImage: image)
                    try rep.representation(using: .png, properties: [:])?.write(
                        to: directory.appending(path: "display-\(display.displayID).png"))
                }
                try "ok".write(to: directory.appending(path: "done.txt"), atomically: true, encoding: .utf8)
            } catch {
                try? "error: \(error)".write(
                    to: directory.appending(path: "done.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
#endif
