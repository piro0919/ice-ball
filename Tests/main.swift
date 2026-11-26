import AppKit

// A dependency-free test runner: `./test.sh`. Checks the pure geometry and renders the
// overlay view offscreen to PNG files for visual inspection.

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message) (line \(line))")
    }
}

let bar = CGRect(x: 0, y: 0, width: 1800, height: 39)

print("ShapeLayout")
do {
    var config = AppearanceConfiguration.default
    config.shape = .standard
    expect(ShapeLayout.rects(for: config, in: bar, leftExtent: 400, rightExtent: 700).isEmpty, "Default draws nothing")

    config.shape = .rounded
    config.horizontalMargin = 6
    config.verticalMargin = 3
    let rounded = ShapeLayout.rects(for: config, in: bar, leftExtent: nil, rightExtent: nil)
    expect(rounded == [CGRect(x: 6, y: 3, width: 1788, height: 33)], "Rounded is the bar inset by the margins")

    config.shape = .split
    let split = ShapeLayout.rects(for: config, in: bar, leftExtent: 445, rightExtent: 739)
    expect(split.count == 2, "Split draws two shapes")
    expect(split.first?.maxX == 445 + ShapeLayout.splitPadding, "left shape ends just after the app menus")
    expect(split.last?.minX == 1800 - 739 - ShapeLayout.splitPadding, "right shape starts just before the status items")
    expect(split.last?.maxX == 1794, "right shape keeps the horizontal margin")

    let overlapping = ShapeLayout.rects(for: config, in: bar, leftExtent: 1000, rightExtent: 790)
    expect(overlapping.count == 1, "Split falls back to one shape when the halves would touch")
    let unmeasured = ShapeLayout.rects(for: config, in: bar, leftExtent: nil, rightExtent: 300)
    expect(unmeasured == rounded, "Split without measurements looks like Rounded")

    config.verticalMargin = 30
    expect(
        ShapeLayout.rects(for: config, in: bar, leftExtent: 400, rightExtent: 400).isEmpty,
        "margins larger than the bar draw nothing")
}

print("MenuBarRegions")
do {
    // Values measured on the development machine (macOS 27.2.1, 14-inch notch display + Sidecar).
    let main = MenuBarRegions.DisplayInfo(
        bounds: CGRect(x: 0, y: 0, width: 1800, height: 1169), menuBarHeight: 39, notchXRange: 790...1010)
    let sidecar = MenuBarRegions.DisplayInfo(
        bounds: CGRect(x: -1600, y: 0, width: 1600, height: 1200), menuBarHeight: 30, notchXRange: nil)
    let menus = [
        CGRect(x: 10, y: 0, width: 34, height: 39), CGRect(x: 43, y: 0, width: 66, height: 39),
        CGRect(x: 388, y: 0, width: 57, height: 39),
    ]
    expect(
        MenuBarRegions.applicationMenuExtent(frames: menus, on: main) == 445,
        "app menu extent is measured from the display's left edge")
    // Firefox's menus on the Sidecar display, as Accessibility reported them (y = 9).
    let sidecarMenus = [CGRect(x: -1590, y: 9, width: 34, height: 21), CGRect(x: -972, y: 9, width: 57, height: 21)]
    expect(
        MenuBarRegions.applicationMenuExtent(frames: sidecarMenus, on: sidecar) == 685,
        "each display gets its own app menu extent")
    expect(
        MenuBarRegions.applicationMenuExtent(frames: sidecarMenus, on: main) == nil,
        "menus of another display are ignored")
    // After macOS rebuilt the menu bar, the built-in display's menus came back at y = -9.
    let shiftedUp = menus.map { $0.offsetBy(dx: 0, dy: -9) }
    expect(
        MenuBarRegions.applicationMenuExtent(frames: shiftedUp, on: main) == 445,
        "menus reported slightly above the display still count")

    // A contiguous run from 1061 to the clock, plus one item parked behind the notch.
    let items =
        stride(from: 1061.0, to: 1664.0, by: 26.8).map { CGRect(x: $0, y: 7.5, width: 26.8, height: 24) }
        + [CGRect(x: 1664, y: 0, width: 115, height: 39), CGRect(x: 900, y: 7.5, width: 22, height: 24)]
    expect(
        MenuBarRegions.statusItemsExtent(frames: items, displays: [sidecar, main]) == 739,
        "status items behind the notch are ignored")

    // Measured: Raycast reported at 1158 while the drawn items start at Wacchi (1292).
    let withStray = [
        CGRect(x: 1158, y: 7.5, width: 20, height: 24), CGRect(x: 1292, y: 7.5, width: 28, height: 24),
        CGRect(x: 1318, y: 7.5, width: 23, height: 24), CGRect(x: 1664, y: 0, width: 115, height: 39),
    ]
    let run =
        withStray.dropFirst().map { $0 }
        + stride(from: 1341.0, to: 1664.0, by: 23).map { CGRect(x: $0, y: 7.5, width: 23, height: 24) }
    expect(
        MenuBarRegions.statusItemsExtent(frames: [withStray[0]] + run, displays: [main]) == 1800 - 1292,
        "an item far left of the run is ignored")

    let offscreen = [CGRect(x: 1100, y: 600, width: 22, height: 24)]
    expect(
        MenuBarRegions.statusItemsExtent(frames: offscreen, displays: [main]) == nil,
        "frames outside the menu bar strip are ignored")

    let onSidecar = [CGRect(x: -400, y: 3, width: 24, height: 24)]
    expect(
        MenuBarRegions.statusItemsExtent(frames: onSidecar, displays: [sidecar, main]) == 400,
        "extent works on a display left of the primary")
}

print("Wallpaper scaling")
do {
    let screen = CGSize(width: 3600, height: 2338)
    let fill = WallpaperProvider.imageRect(
        imageSize: CGSize(width: 6000, height: 4000), in: screen, scaling: .scaleProportionallyUpOrDown,
        allowsClipping: true)
    expect(fill.width >= screen.width && fill.height >= screen.height, "Fill covers the screen")
    let fit = WallpaperProvider.imageRect(
        imageSize: CGSize(width: 6000, height: 4000), in: screen, scaling: .scaleProportionallyUpOrDown,
        allowsClipping: false)
    expect(fit.width <= screen.width && fit.height <= screen.height, "Fit stays inside the screen")
}

print("Desktop picture brightness")
do {
    func solid(_ gray: CGFloat) -> CGImage {
        let c = CGContext(
            data: nil, width: 40, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        c.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: 40, height: 8))
        return c.makeImage()!
    }
    expect(WallpaperProvider.averageLuminance(of: solid(0)) < 0.05, "black reads as dark")
    expect(WallpaperProvider.averageLuminance(of: solid(1)) > 0.95, "white reads as light")
    expect(abs(WallpaperProvider.averageLuminance(of: solid(0.5)) - 0.5) < 0.02, "mid gray reads as mid")
}

print("Settings persistence")
do {
    let defaults = UserDefaults(suiteName: "IceBallTests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    expect(store.configuration == .default, "fresh store uses the defaults")
    store.configuration.cornerRadius = 15
    store.configuration.shape = .split
    let reloaded = SettingsStore(defaults: defaults)
    expect(
        reloaded.configuration.cornerRadius == 15 && reloaded.configuration.shape == .split, "changes survive a reload")
    reloaded.resetToDefaults()
    expect(SettingsStore(defaults: defaults).configuration == .default, "reset is persisted")

    let partial = #"{"shape":"split","cornerRadius":4}"#.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(AppearanceConfiguration.self, from: partial)
    expect(
        decoded?.shape == .split && decoded?.cornerRadius == 4
            && decoded?.borderWidth == AppearanceConfiguration.default.borderWidth, "missing keys fall back to defaults"
    )
}

print("Offscreen render")
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(name: String, shape: MenuBarShape, isDark: Bool, placement: OverlayPlacement, wallpaper: CGImage? = nil)
    -> NSBitmapImageRep?
{
    var config = AppearanceConfiguration.default
    config.shape = shape
    config.borderWidth = 1
    config.backgroundOpacity = 0.8
    let width: CGFloat = 1800
    let barInView = CGRect(x: 0, y: OverlayPanel.shadowMargin, width: width, height: 39)
    let view = OverlayView(frame: NSRect(x: 0, y: 0, width: width, height: 39 + OverlayPanel.shadowMargin))
    view.model = OverlayDrawModel(
        bar: barInView,
        shapes: ShapeLayout.rects(for: config, in: barInView, leftExtent: 445, rightExtent: 739),
        configuration: config,
        isDark: isDark,
        placement: placement,
        wallpaper: wallpaper
    )
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: outputDirectory.appending(path: "\(name).png"))
    }
    return rep
}

/// Alpha at a point given in view points (the bitmap may be 2x).
func alpha(_ rep: NSBitmapImageRep, x: CGFloat, yFromTop: CGFloat) -> CGFloat {
    let scale = CGFloat(rep.pixelsWide) / 1800
    return rep.colorAt(x: Int(x * scale), y: Int(yFromTop * scale))?.alphaComponent ?? -1
}

// y counts from the top, in points. The bar occupies rows 0..<39; the shadow margin follows.
if let rep = render(name: "split-dark-below", shape: .split, isDark: true, placement: .belowMenuBar) {
    expect(alpha(rep, x: 200, yFromTop: 20) > 0.7, "inside the left shape is filled")
    expect(alpha(rep, x: 1500, yFromTop: 20) > 0.7, "inside the right shape is filled")
    expect(alpha(rep, x: 750, yFromTop: 20) < 0.05, "the gap between the split shapes stays transparent")
    expect(
        alpha(rep, x: 1, yFromTop: 20) < 0.5,
        "the fill does not reach into the horizontal margin (only the shadow does)")
    expect(alpha(rep, x: 200, yFromTop: 41) > 0.02, "a shadow falls below the shape")
}
if let rep = render(name: "rounded-light-below", shape: .rounded, isDark: false, placement: .belowMenuBar) {
    expect(alpha(rep, x: 900, yFromTop: 20) > 0.7, "Rounded fills across the middle")
    expect(alpha(rep, x: 7, yFromTop: 4) < 0.3, "the rounded corner is cut away")
}

// A striped stand-in for the desktop picture.
let wallpaperContext = CGContext(
    data: nil, width: 1800, height: 39, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
for i in stride(from: 0, to: 1800, by: 40) {
    wallpaperContext.setFillColor(
        i % 80 == 0
            ? CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1)
            : CGColor(srgbRed: 0.9, green: 0.6, blue: 0.3, alpha: 1))
    wallpaperContext.fill(CGRect(x: i, y: 0, width: 40, height: 39))
}
if let rep = render(
    name: "split-dark-above", shape: .split, isDark: true, placement: .aboveMenuBar,
    wallpaper: wallpaperContext.makeImage())
{
    expect(alpha(rep, x: 750, yFromTop: 20) > 0.99, "above the menu bar, the gap is painted with the desktop picture")
    expect(
        alpha(rep, x: 200, yFromTop: 20) < 0.5,
        "above the menu bar, the fill opacity is capped so menu text stays readable")
}

print("Snapshots written to \(outputDirectory.path)")
print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
