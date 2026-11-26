import AppKit
import ImageIO
import ScreenCaptureKit

/// Supplies the strip of desktop picture under each display's menu bar.
/// Needed only for `.aboveMenuBar` placement.
///
/// Ice captures the Dock's wallpaper window with the obsoleted `CGWindowListCreateImage…`
/// API on a 5-second timer. This app tries, in order:
/// 1. ScreenCaptureKit, capturing only the desktop-level windows, when the Screen Recording
///    permission has already been granted. Matches dynamic and Aerial wallpapers.
/// 2. Decoding the file from `NSWorkspace.desktopImageURL(for:)` and reproducing the
///    "Fill/Fit/Stretch/Center" choice. No permission, but fails when the file sits in
///    another app's container (macOS blocks that read), and shows only the first frame of
///    dynamic wallpapers.
/// Captures run once per change: on the wallpaper store file changing, on space and
/// display changes. There is no timer.
final class WallpaperProvider {
    private struct Key: Equatable {
        var displayID: CGDirectDisplayID
        var bar: CGRect
        var scale: CGFloat
    }

    private var cache: [CGDirectDisplayID: (key: Key, image: CGImage, average: RGBAColor)] = [:]
    private var loading: [CGDirectDisplayID: Key] = [:]
    /// Keys whose last load produced nothing; not retried until `invalidate()`.
    private var failures: [CGDirectDisplayID: Key] = [:]
    private var generation = 0
    private var watcher: DispatchSourceFileSystemObject?
    private var onChange: (() -> Void)?

    /// macOS 14+ stores the wallpaper choice here and rewrites it on every change.
    private static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    static var hasScreenCapturePermission: Bool { CGPreflightScreenCaptureAccess() }

    /// The cached strip for `bar` (a Cocoa rect in global coordinates). When it is missing
    /// or stale, a load starts and `onChange` fires once it finishes.
    func image(for screen: NSScreen, bar: NSRect) -> CGImage? {
        let key = Key(displayID: screen.displayID, bar: bar, scale: screen.backingScaleFactor)
        if let cached = cache[key.displayID], cached.key == key { return cached.image }
        startLoadingIfNeeded(key: key, screen: screen)
        return nil
    }

    /// Average luminance (0–1) of the strip, once `image(for:bar:)` has loaded it.
    func luminance(for screen: NSScreen, bar: NSRect) -> CGFloat? {
        averageColor(for: screen, bar: bar).map(Self.luminance)
    }

    /// Average color of the strip, once `image(for:bar:)` has loaded it.
    func averageColor(for screen: NSScreen, bar: NSRect) -> RGBAColor? {
        let key = Key(displayID: screen.displayID, bar: bar, scale: screen.backingScaleFactor)
        guard let cached = cache[key.displayID], cached.key == key else { return nil }
        return cached.average
    }

    private func startLoadingIfNeeded(key: Key, screen: NSScreen) {
        if failures[key.displayID] == key { return }
        if loading[key.displayID] != key { load(key: key, screen: screen) }
    }

    func invalidate() {
        generation += 1
        cache.removeAll()
        loading.removeAll()
        failures.removeAll()
    }

    private func load(key: Key, screen: NSScreen) {
        loading[key.displayID] = key
        let generation = generation
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let screenFrame = screen.frame
        Task { [weak self] in
            var image: CGImage?
            if Self.hasScreenCapturePermission {
                image = await Self.capture(
                    displayID: key.displayID, screenFrame: screenFrame, bar: key.bar, scale: key.scale)
            }
            if image == nil, let url {
                image = Self.render(
                    url: url, options: options, screenFrame: screenFrame, bar: key.bar, scale: key.scale)
            }
            guard let self, self.generation == generation, self.loading[key.displayID] == key else { return }
            self.loading[key.displayID] = nil
            if let image {
                self.cache[key.displayID] = (key, image, Self.averageColor(of: image))
            } else {
                self.failures[key.displayID] = key
            }
            self.onChange?()
        }
    }

    // MARK: Watching

    /// Starts watching the wallpaper store. `handler` runs on the main queue.
    func startWatching(_ handler: @escaping () -> Void) {
        onChange = handler
        guard watcher == nil else { return }
        openWatcher()
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        onChange = nil
    }

    private func openWatcher() {
        let fd = open(Self.storeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The file is replaced atomically; reopen to keep following the new inode.
                if source.data.contains(.rename) || source.data.contains(.delete) {
                    self.watcher?.cancel()
                    self.watcher = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self, self.onChange != nil else { return }
                        self.openWatcher()
                    }
                }
                // The new picture is drawn a moment after the store is written.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.invalidate()
                    self?.onChange?()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    // MARK: ScreenCaptureKit

    private nonisolated static func capture(
        displayID: CGDirectDisplayID, screenFrame: NSRect, bar: NSRect, scale: CGFloat
    ) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
            let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        // Desktop-picture windows sit at or below the desktop window level, under the icons.
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let displayBounds = CGDisplayBounds(displayID)
        let wallpaperWindows = content.windows.filter {
            $0.windowLayer <= desktopLevel && $0.frame.intersects(displayBounds)
        }
        guard !wallpaperWindows.isEmpty else { return nil }

        let filter = SCContentFilter(display: display, including: wallpaperWindows)
        let config = SCStreamConfiguration()
        // sourceRect is in display points with the origin at the display's top-left.
        config.sourceRect = CGRect(
            x: bar.minX - screenFrame.minX, y: screenFrame.maxY - bar.maxY, width: bar.width, height: bar.height)
        config.width = Int(bar.width * scale)
        config.height = Int(bar.height * scale)
        config.showsCursor = false
        config.capturesAudio = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: Desktop picture file

    private nonisolated static func render(
        url: URL, options: [NSWorkspace.DesktopImageOptionKey: Any], screenFrame: NSRect, bar: NSRect, scale: CGFloat
    ) -> CGImage? {
        let screenPixels = CGSize(width: screenFrame.width * scale, height: screenFrame.height * scale)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Decode no larger than the screen to keep memory low.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(screenPixels.width, screenPixels.height),
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else {
            return nil
        }

        let scaling =
            (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
            ?? .scaleProportionallyUpOrDown
        let allowsClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        let fillColor = (options[.fillColor] as? NSColor)?.cgColor ?? CGColor(gray: 0, alpha: 1)

        let imageSize = CGSize(width: decoded.width, height: decoded.height)
        let target = imageRect(imageSize: imageSize, in: screenPixels, scaling: scaling, allowsClipping: allowsClipping)

        // Render only the strip under the menu bar.
        let stripPixels = CGSize(width: bar.width * scale, height: bar.height * scale)
        guard stripPixels.width >= 1, stripPixels.height >= 1,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(stripPixels.width), height: Int(stripPixels.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else { return nil }
        context.setFillColor(fillColor)
        context.fill(CGRect(origin: .zero, size: stripPixels))
        // Strip origin in screen pixel space (y up, origin at the screen's bottom-left).
        let stripOrigin = CGPoint(x: (bar.minX - screenFrame.minX) * scale, y: (bar.minY - screenFrame.minY) * scale)
        context.interpolationQuality = .high
        context.draw(decoded, in: target.offsetBy(dx: -stripOrigin.x, dy: -stripOrigin.y))
        return context.makeImage()
    }

    /// Rec. 709 luma averaged over a 32×4 downscale of the image.
    nonisolated static func averageLuminance(of image: CGImage) -> CGFloat {
        luminance(averageColor(of: image))
    }

    /// Rec. 709 luma of a color (the average of the luma equals the luma of the average).
    nonisolated static func luminance(_ c: RGBAColor) -> CGFloat {
        CGFloat(0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue)
    }

    /// sRGB average over a 32×4 downscale of the image.
    nonisolated static func averageColor(of image: CGImage) -> RGBAColor {
        let width = 32
        let height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return RGBAColor(red: 0.5, green: 0.5, blue: 0.5) }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sums = (0.0, 0.0, 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sums.0 += Double(pixels[i])
            sums.1 += Double(pixels[i + 1])
            sums.2 += Double(pixels[i + 2])
        }
        let count = Double(width * height) * 255
        return RGBAColor(red: sums.0 / count, green: sums.1 / count, blue: sums.2 / count)
    }

    /// Where the image lands on the screen for each "Fill/Fit/Stretch/Center" choice.
    nonisolated static func imageRect(
        imageSize: CGSize, in screen: CGSize, scaling: NSImageScaling, allowsClipping: Bool
    ) -> CGRect {
        let size: CGSize
        switch scaling {
        case .scaleAxesIndependently:
            size = screen
        case .scaleNone:
            size = imageSize
        default:
            let sx = screen.width / imageSize.width
            let sy = screen.height / imageSize.height
            let factor = allowsClipping ? max(sx, sy) : min(sx, sy)
            size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        }
        return CGRect(
            x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2, width: size.width,
            height: size.height)
    }
}
