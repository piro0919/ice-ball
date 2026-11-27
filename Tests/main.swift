import AppKit
import SwiftUI

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

print("ShapeAnimation")
do {
    expect(ShapeAnimation.easeOut(0) == 0 && ShapeAnimation.easeOut(1) == 1, "easing starts at 0 and ends at 1")
    expect(ShapeAnimation.easeOut(0.5) > 0.5, "easing is ahead of linear: it slows down at the end")
    let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(ShapeAnimation.easeOut)
    expect(
        zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 } && samples.allSatisfy { $0 <= 1 },
        "easing never goes back or past the end (no overshoot)")
    expect(ShapeAnimation.easeOut(-1) == 0 && ShapeAnimation.easeOut(2) == 1, "easing clamps outside 0…1")

    let from = [CGRect(x: 6, y: 3, width: 447, height: 33), CGRect(x: 1053, y: 3, width: 741, height: 33)]
    let to = [CGRect(x: 6, y: 3, width: 300, height: 33), CGRect(x: 1053, y: 3, width: 741, height: 33)]
    expect(ShapeAnimation.interpolate(from: from, to: to, progress: 0) == from, "progress 0 is the old frames")
    expect(ShapeAnimation.interpolate(from: from, to: to, progress: 1) == to, "progress 1 is the new frames")
    let middle = ShapeAnimation.interpolate(from: from, to: to, progress: 0.5)
    expect(
        middle[0].width < 447 && middle[0].width > 300 && middle[0].minX == 6,
        "the left shape grows or shrinks from its left edge")
    expect(middle[1] == to[1], "an unchanged shape stays put")
    expect(ShapeAnimation.interpolate(from: [from[0]], to: to, progress: 0.5) == to, "a different count jumps")

    let viewBounds = CGRect(x: 0, y: 0, width: 1800, height: 55)
    let dirty = ShapeAnimation.dirtyRect(from: from, to: to, in: viewBounds, cornerRadius: 20, reach: 5)
    expect(
        dirty == CGRect(x: 306 - 16.5 - 5, y: 0, width: 453 - 306 + 16.5 + 10, height: 55),
        "only the moving end of the left shape is redrawn, with its corner and shadow")
    expect(
        ShapeAnimation.dirtyRect(from: from, to: from, in: viewBounds, cornerRadius: 20, reach: 5) == .zero,
        "nothing moved, nothing redrawn")
    expect(
        ShapeAnimation.dirtyRect(from: [from[0]], to: to, in: viewBounds, cornerRadius: 20, reach: 5) == viewBounds,
        "a different count redraws everything")

    var config = AppearanceConfiguration.default
    config.shape = .split
    let model = OverlayDrawModel(
        bar: bar, shapes: from, configuration: config, isDark: false, placement: .belowMenuBar, wallpaper: nil)
    var moved = model
    moved.shapes = to
    expect(ShapeAnimation.shouldAnimate(from: model, to: moved), "a change of the shapes alone moves them")
    expect(!ShapeAnimation.shouldAnimate(from: model, to: model), "no change, no movement")
    var resized = moved
    resized.bar.size.width = 1352
    expect(!ShapeAnimation.shouldAnimate(from: model, to: resized), "a resolution change jumps")
    var restyled = moved
    restyled.configuration.horizontalMargin += 2
    expect(!ShapeAnimation.shouldAnimate(from: model, to: restyled), "a settings change jumps")
    var fallback = moved
    fallback.shapes = [CGRect(x: 6, y: 3, width: 1788, height: 33)]
    expect(!ShapeAnimation.shouldAnimate(from: model, to: fallback), "two shapes becoming one jumps")

    let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 1800, height: 55))
    view.model = model
    expect(view.displayedShapes == nil, "the first model is drawn as it is")
    view.model = moved
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        expect(view.displayedShapes == nil, "with Reduce motion on, the shapes jump")
    } else {
        expect(view.displayedShapes == from, "the view starts moving from the old frames")
    }
    view.model = restyled
    expect(view.displayedShapes == nil, "a settings change stops the movement and jumps")
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
    // With Mission Control open the hit test lands on WindowManager and nothing can be read.
    expect(
        MenuBarRegions.nextApplicationMenuExtent(frames: nil, on: main, previous: 445, keepingMissing: false) == 445,
        "an unreadable menu bar keeps the last width, even on the last retry")
    expect(
        MenuBarRegions.nextApplicationMenuExtent(frames: [], on: main, previous: 445, keepingMissing: true) == 445,
        "a menu bar read as empty keeps the last width while retrying")
    expect(
        MenuBarRegions.nextApplicationMenuExtent(frames: [], on: main, previous: 445, keepingMissing: false) == nil,
        "the last retry accepts a menu bar read as empty")
    expect(
        MenuBarRegions.nextApplicationMenuExtent(frames: menus, on: main, previous: 360, keepingMissing: false) == 445,
        "a reading replaces the last width")

    expect(
        MenuBarRegions.nextApplicationMenuExtent(
            frames: nil, on: main, previous: 445, keepingMissing: false,
            unreadableFor: MenuBarRegions.unreadableGrace) == nil,
        "a menu bar unreadable for too long falls back to one shape")

    var owners = StatusItemOwners()
    let clock = [CGRect(x: 1664, y: 0, width: 115, height: 39)]
    let grace = StatusItemOwners.emptyGrace
    owners.record(clock, for: 10, at: 0)
    owners.record([], for: 20, at: 0)
    expect(owners.pids == [10], "a process with no status items is not an owner")
    for t in [0.1, 0.2, 0.3, grace - 1] { owners.record([], for: 10, at: t) }
    expect(owners.allFrames == clock, "an owner read as empty keeps its last frames, however many scans")
    owners.record(clock, for: 10, at: grace - 1)
    owners.record([], for: 10, at: grace + 1)
    expect(owners.pids == [10], "a reading with items starts the time again")
    owners.record([], for: 10, at: grace * 2)
    expect(owners.pids.isEmpty, "an owner empty for long enough is dropped")
    let raycast = [CGRect(x: 1126, y: 7, width: 68, height: 24)]
    owners.record(clock, for: 10, at: 0)
    owners.record(raycast, for: 30, at: 0)
    expect(owners.frames(excluding: [30]) == clock, "an excluded owner's items are left out")
    expect(owners.pids == [10, 30], "an excluded owner stays known")
    owners.keepOnly(running: [20])
    expect(owners.pids.isEmpty, "a process that quit is forgotten")

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

    // Shape of Dimble's settings as read on 2026-11-27 (Dimble build 95), trimmed.
    let dimble = Data(
        """
        {"sectionModel":{"assignments":[
          "bundle:org.mozilla.firefox","hidden",
          "bundle:com.raycast.macos","alwaysHidden",
          "status:com.apple.MenuBarAgent::com.apple.menuextra.display","alwaysHidden",
          "bundle:io.kkweb.wacchi","visible",
          "bundle:org.p0deje.Maccy"
        ]}}
        """.utf8)
    expect(
        ConcealedStatusItems.dimbleConcealedBundleIDs(settings: dimble)
            == ["org.mozilla.firefox", "com.raycast.macos"],
        "Dimble's hidden and always hidden apps are read; single items and visible apps are not")
    expect(
        ConcealedStatusItems.dimbleConcealedBundleIDs(settings: Data("[]".utf8)).isEmpty,
        "unreadable Dimble settings hide nothing")
    expect(
        ConcealedStatusItems.concealedBundleIDs(runningBundleIDs: []).isEmpty,
        "nothing is hidden while Dimble is not running")

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

    let plum = CGContext(
        data: nil, width: 40, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    plum.setFillColor(CGColor(srgbRed: 0.5, green: 0.2, blue: 0.4, alpha: 1))
    plum.fill(CGRect(x: 0, y: 0, width: 40, height: 8))
    let average = WallpaperProvider.averageColor(of: plum.makeImage()!)
    expect(
        abs(average.red - 0.5) < 0.02 && abs(average.green - 0.2) < 0.02 && abs(average.blue - 0.4) < 0.02,
        "the average color of a solid picture is that color")
}

print("DesktopPictureColor")
do {
    func close(_ a: RGBAColor, _ b: RGBAColor) -> Bool {
        abs(a.red - b.red) < 0.005 && abs(a.green - b.green) < 0.005 && abs(a.blue - b.blue) < 0.005
    }
    for c in [
        RGBAColor(red: 0.5, green: 0.2, blue: 0.4), RGBAColor(red: 0.1, green: 0.6, blue: 0.3),
        RGBAColor(red: 0.2, green: 0.3, blue: 0.9), RGBAColor(red: 0.9, green: 0.8, blue: 0.1),
    ] {
        let (h, s, l) = DesktopPictureColor.hsl(c)
        expect(close(DesktopPictureColor.color(hue: h, saturation: s, lightness: l), c), "HSL round trip \(c)")
    }
    let blue = RGBAColor(red: 0.2, green: 0.35, blue: 0.7)
    let dark = DesktopPictureColor.fill(from: blue, isDark: true)
    let light = DesktopPictureColor.fill(from: blue, isDark: false)
    expect(
        abs(DesktopPictureColor.hsl(dark).lightness - DesktopPictureColor.darkLightness) < 0.005,
        "behind light titles the fill is dark")
    expect(
        abs(DesktopPictureColor.hsl(light).lightness - DesktopPictureColor.lightLightness) < 0.005,
        "behind dark titles the fill is light")
    expect(
        abs(DesktopPictureColor.hsl(dark).hue - DesktopPictureColor.hsl(blue).hue) < 0.005
            && abs(DesktopPictureColor.hsl(light).hue - DesktopPictureColor.hsl(blue).hue) < 0.005,
        "the fill keeps the picture's hue")
    expect(dark.blue > dark.red && light.blue > light.red, "a blue picture gives a blue fill")
    let red = DesktopPictureColor.fill(from: RGBAColor(red: 1, green: 0, blue: 0), isDark: true)
    expect(
        abs(DesktopPictureColor.hsl(red).saturation - DesktopPictureColor.maximumSaturation) < 0.005,
        "a vivid picture is toned down")
    let gray = DesktopPictureColor.fill(from: RGBAColor(red: 0.4, green: 0.4, blue: 0.4), isDark: false)
    expect(gray.red == gray.green && gray.green == gray.blue, "a gray picture gives a gray fill")
}

print("PointerReach")
do {
    // View coordinates, y up: a Rounded shape 33 pt tall whose bottom edge is at y = 19.
    let shape = CGRect(x: 6, y: 19, width: 1788, height: 33)
    let r: CGFloat = 10
    expect(
        PointerReach.target(pointer: CGPoint(x: 900, y: 19 - 41), shapes: [shape], cornerRadius: r) == nil,
        "a pointer more than 40 pt below the shape does not pull it")
    let far = PointerReach.target(pointer: CGPoint(x: 900, y: 19 - 30), shapes: [shape], cornerRadius: r)
    let near = PointerReach.target(pointer: CGPoint(x: 900, y: 19 - 5), shapes: [shape], cornerRadius: r)
    let inside = PointerReach.target(pointer: CGPoint(x: 900, y: 40), shapes: [shape], cornerRadius: r)
    expect(far != nil && near != nil && far!.strength < near!.strength, "the closer the pointer, the stronger the pull")
    expect(inside?.strength == 1, "a pointer on the bar pulls fully")
    expect(near?.x == 900, "the swelling is centered under the pointer")
    let corner = PointerReach.target(pointer: CGPoint(x: 8, y: 15), shapes: [shape], cornerRadius: r)
    expect(corner?.x == 6 + r + PointerReach.halfWidth, "the swelling stays clear of the rounded corner")

    let left = CGRect(x: 6, y: 19, width: 447, height: 33)
    let right = CGRect(x: 1053, y: 19, width: 741, height: 33)
    expect(
        PointerReach.target(pointer: CGPoint(x: 1100, y: 10), shapes: [left, right], cornerRadius: r)?.index == 1,
        "with Split, the shape nearest the pointer is pulled")
    expect(
        PointerReach.target(pointer: CGPoint(x: 753, y: 10), shapes: [left, right], cornerRadius: r) == nil,
        "a pointer in the middle of a wide gap pulls neither shape")
    let narrow = CGRect(x: 6, y: 19, width: 60, height: 33)
    expect(
        PointerReach.target(pointer: CGPoint(x: 30, y: 15), shapes: [narrow], cornerRadius: r) == nil,
        "a shape too narrow for the swelling is left alone")

    let swollen = PointerReach.path(
        for: [shape], cornerRadius: r, bulge: .init(index: 0, x: 900, depth: PointerReach.maximumDepth))
    expect(swollen.contains(CGPoint(x: 900, y: 19 - 5)), "the swollen edge reaches below the shape")
    expect(
        !swollen.contains(CGPoint(x: 900 - PointerReach.halfWidth - 2, y: 18)), "only the part under the pointer swells"
    )
    expect(
        swollen.contains(CGPoint(x: 900, y: 35)) && swollen.contains(CGPoint(x: 100, y: 35)),
        "the rest of the shape is still filled")
    expect(!swollen.contains(CGPoint(x: 7, y: 51)), "the corners stay rounded")
    let shrunk = CGRect(x: 6, y: 19, width: 600, height: 33)
    let stale = PointerReach.path(
        for: [shrunk], cornerRadius: r, bulge: .init(index: 0, x: 900, depth: PointerReach.maximumDepth))
    expect(
        stale.boundingBox.maxX <= shrunk.maxX + 0.5,
        "a swelling left behind by a shrinking shape stays inside it")
    let flat = PointerReach.path(for: [shape], cornerRadius: r, bulge: .init(index: 0, x: 900, depth: 0.01))
    expect(flat == ShapeLayout.path(for: [shape], cornerRadius: r), "a swelling too small to see draws the plain shape")

    let bar = CGRect(x: 0, y: 16, width: 1800, height: 39)
    expect(
        PointerReach.maximumDepth(shape: shape, bar: bar, placement: .belowMenuBar) == PointerReach.maximumDepth,
        "under a transparent bar the swelling goes its full depth")
    expect(
        PointerReach.maximumDepth(shape: shape, bar: bar, placement: .aboveMenuBar) == 3,
        "over the system's bar the swelling stops at the bar's bottom edge")
    expect(
        PointerReach.maximumDepth(shape: bar, bar: bar, placement: .aboveMenuBar) == 0,
        "with no bottom margin there is no room to swell over the system's bar")

    var spring = Spring()
    var peak = 0.0
    var frames = 0
    while !(spring.isSettled(at: 6)) && frames < 600 {
        spring.step(toward: 6, dt: 1.0 / 60)
        peak = max(peak, spring.value)
        frames += 1
    }
    expect(spring.value == 6, "the spring settles on its target")
    expect(peak > 6.1 && peak < 7.5, "it overshoots a little on the way (peak \(peak))")
    expect(frames < 90, "and settles within a second and a half (\(frames) frames)")
    spring.step(toward: 0, dt: 5)
    expect(spring.value.isFinite && abs(spring.value) < 7, "a long pause between frames does not blow up")
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
    expect(
        decoded?.colorFromDesktopPicture == false, "configurations saved before the switch existed keep their colors")
    store.configuration.colorFromDesktopPicture = true
    expect(SettingsStore(defaults: defaults).configuration.colorFromDesktopPicture, "the switch survives a reload")
    expect(
        decoded?.reachesTowardPointer == false && AppearanceConfiguration.default.reachesTowardPointer == false,
        "Reach Toward Pointer is off by default and for older saved settings")
    store.configuration.reachesTowardPointer = true
    expect(
        SettingsStore(defaults: defaults).configuration.reachesTowardPointer, "Reach Toward Pointer survives a reload")
}

print("Offscreen render")
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(
    name: String, shape: MenuBarShape, isDark: Bool, placement: OverlayPlacement, wallpaper: CGImage? = nil,
    desktopFill: RGBAColor? = nil
) -> NSBitmapImageRep? {
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
        wallpaper: wallpaper,
        desktopFill: desktopFill
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
let teal = DesktopPictureColor.fill(from: RGBAColor(red: 0.1, green: 0.5, blue: 0.5), isDark: false)
if let rep = render(
    name: "rounded-light-desktop-color", shape: .rounded, isDark: false, placement: .belowMenuBar, desktopFill: teal),
    let pixel = rep.colorAt(x: Int(900 * CGFloat(rep.pixelsWide) / 1800), y: Int(20 * CGFloat(rep.pixelsWide) / 1800))?
        .usingColorSpace(.sRGB)
{
    expect(
        pixel.greenComponent > pixel.redComponent + 0.05 && pixel.blueComponent > pixel.redComponent + 0.05,
        "the fill taken from the desktop picture is drawn instead of the light color")
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

print("AppearancePreview")
do {
    // Split must show two shapes in the first frame, before SwiftUI has measured anything.
    let metrics = PreviewMetrics()
    let estimated = (metrics.menusWidth, metrics.statusWidth)
    var config = AppearanceConfiguration.default
    config.shape = .split
    let previewBar = CGRect(x: 0, y: 8, width: 460, height: 30)
    let firstFrame = ShapeLayout.rects(
        for: config, in: previewBar,
        leftExtent: estimated.0 > 0 ? 16 + estimated.0 : nil,
        rightExtent: estimated.1 > 0 ? estimated.1 + 16 : nil)
    expect(firstFrame.count == 2, "the preview's first frame already splits")

    let host = NSHostingView(
        rootView: AppearancePreview(configuration: config, metrics: metrics).frame(width: 460, height: 76))
    host.frame = CGRect(x: 0, y: 0, width: 460, height: 76)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    expect(
        abs(metrics.menusWidth - estimated.0) <= 2 && abs(metrics.statusWidth - estimated.1) <= 2,
        "estimated widths match the laid-out ones (menus \(estimated.0) vs \(metrics.menusWidth), status \(estimated.1) vs \(metrics.statusWidth))"
    )
}

print("Snapshots written to \(outputDirectory.path)")
print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
