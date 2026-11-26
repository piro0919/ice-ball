# Ice Ball

A small macOS menu bar app that changes how the menu bar looks — Default, Rounded or Split — with a transparent, click-through overlay. It does not hide, reorder or manage menu bar items.

Ice Ball is an independent project. It is not affiliated with or endorsed by [Ice](https://github.com/jordanbaird/Ice) or its author; Ice's source was studied as a reference (see "Findings from Ice"), and no Ice code is included.

Target: Apple silicon, macOS 26 or later. Developed and checked on macOS 27.2.1.

There is a page for it at [ice-ball.kkweb.io](https://ice-ball.kkweb.io).

## Install

Download `IceBall-<version>.dmg` from [Releases](https://github.com/piro0919/ice-ball/releases/latest) and drag Ice Ball into Applications, or use Homebrew:

```bash
brew install --cask piro0919/tap/ice-ball
```

The app is signed with a personal certificate, not by a registered Apple developer, so macOS blocks the first launch. Open System Settings › Privacy & Security and click **Open Anyway**; after that it opens normally.

Ice Ball checks for a new version once at launch (Sparkle, from this repository's GitHub Releases) and asks before installing it. **Check for Updates…** in the settings window checks on demand.

## Build and run

Xcode is not needed; the Command Line Tools are enough. `build.sh` fetches [Sparkle](https://sparkle-project.org) into `Vendor/` (checked against its SHA-256) the first time.

```bash
./build.sh            # release build → build/release/IceBall.app
./build.sh debug      # debug build   → build/debug/IceBall.app
open build/release/IceBall.app
```

Development aids, compiled into debug builds only:

```bash
open build/debug/IceBall.app --args --snapshot /some/dir     # PNG of the top of each display after 4 s (needs Screen Recording)
open build/debug/IceBall.app --args --request-accessibility  # show the Accessibility prompt
```

Tests (geometry, settings persistence, offscreen rendering; snapshots go to `build/snapshots`):

```bash
./test.sh
```

The app has no Dock icon and no menu bar icon. Opening it shows the settings window; when it is already running, open it again from Finder or Spotlight. At login it starts with the window closed. Only one instance runs: opening a second copy from another folder brings up the running one's settings and quits. The settings window also has "Check for Updates…" and "Quit Ice Ball".

## Permissions

| Permission | Needed for | Without it |
| --- | --- | --- |
| Accessibility | **Split** only: reading the frames of the app menus and the status items | Split is drawn like Rounded |
| Screen Recording | Only when "Show menu bar background" is on **and** the desktop picture file cannot be read (for example, it lives in another app's container) | The overlay stays hidden and the standard menu bar shows |

Default and Rounded on a transparent menu bar (the macOS 26 default) need no permission. The settings window explains which permission is missing and opens the right pane of System Settings.

`build.sh` signs with the certificate named by `SIGN_IDENTITY` (default `Okigae Dev`, the developer's local certificate) and falls back to an ad-hoc signature when it is missing. With an ad-hoc signature macOS records the Accessibility grant against that exact binary, so every rebuild needs it granted again (seen in the `tccd` log as "Failed to match existing code requirement"). Signing with a certificate keeps Screen Recording across rebuilds:

```bash
SIGN_IDENTITY="Your Certificate Name" ./build.sh debug
```

Even then, an Accessibility grant made while an ad-hoc build was running stays tied to that build; clear it with `tccutil reset Accessibility io.kkweb.IceBall` and grant it again. A grant made from a certificate-signed build survived a rebuild in testing.

## Architecture

```
IceBall/
  App/        main.swift, AppDelegate — lifecycle, the settings window at launch and on reopen, a single instance, light/dark fallback; Updater (Sparkle)
  Settings/   AppearanceConfiguration (Codable values), SettingsStore (@Observable, UserDefaults, login item)
  MenuBar/    SystemMenuBar (window list facts), MenuBarRegionReader (Accessibility), MenuBarRegions (pure math)
  Overlay/    OverlayController (events → layout), OverlayPanel, OverlayView (drawing),
              ShapeLayout (pure geometry, shared with the preview), ShapeAnimation (easing and redraw area),
              DesktopPictureColor (fill from the desktop picture), WallpaperProvider
  UI/         SettingsWindowController, SettingsView, AppearancePreview (SwiftUI), Localization (Japanese and English)
Tests/        main.swift — dependency-free checks run by test.sh
Tools/        make-icon.py — writes Resources/AppIcon.icns and assets/AppIcon.png from assets/icon-source.png (prompt in docs/art-prompt.md)
```

How it works:

1. **Menu bar frame.** `CGWindowListCopyWindowInfo` lists one WindowServer window named `Menubar` per display that has a menu bar. Its frame gives the position and height (39 pt on a notched 14-inch display, 30 pt on an external one in testing). Nothing is hard-coded.
2. **Placement.** On macOS 26+ the menu bar is transparent unless "Show menu bar background" is on.
   - Transparent: the overlay panel sits one level *below* the menu bar window, so the system keeps drawing menus and status items on top of the shape. Any fill opacity works.
   - Background shown: the panel sits one level *above* the menu bar window, as Ice does. The area outside the shape is painted with the desktop picture, and the fill opacity is capped at 35 % because it covers the menu titles.
3. **Shapes.** `ShapeLayout` turns the configuration and the measured extents into rounded rectangles. Split uses two: from the left edge to the end of the app menus, and from the first status item to the right edge. When either is unknown or they would touch, Split falls back to one shape.
   - When only the shapes' frames change (in practice the left shape after an app switch, or the right one when a status item changes width), they move to the new frames in 0.25 s with an ease-out curve, without overshoot, at up to 60 frames a second. Each frame redraws only the strip around the moving end. A change of the settings, the display size or the number of shapes jumps, and so does everything while "Reduce motion" is on in System Settings › Accessibility › Display.
4. **Regions.** Each display's menu bar can show a different app (the app of that display's frontmost window). `MenuBarRegionReader` hit-tests the left end of each display's menu bar with Accessibility, reads that app's `AXMenuBar` children, and measures them on that display. Status items come from each app's `AXExtrasMenuBar`; they are reported for the active display only and are laid out from the right edge the same way everywhere, so one extent serves all displays. All calls run on a background queue with a 0.1 s timeout per app.
   - Right after an app switch the new app's menus read as nothing for about 0.2 s (macOS 27.2.1). While the retries after a switch are running, a display that reads as nothing keeps its last width; only the last retry, 1.5 s after the switch, accepts nothing.
5. **Fill color.** The light or dark color is chosen from the brightness of the desktop picture under the bar. With "Color from Desktop Picture" on, the fill instead takes the hue of that strip's average color, with the saturation capped at 50 % and the lightness set to 22 % behind light menu titles or 86 % behind dark ones (`DesktopPictureColor`). Each display uses its own picture. When the picture is not available, the two configured colors are used. The settings preview treats its own gradient as the picture.
6. **Events.** Display changes, Space changes (which includes entering and leaving full screen), wake, app launch/quit, the menu-bar-owning app changing, light/dark changes, the wallpaper store file changing, and the global defaults `_HIHideMenuBar` / `SLSMenuBarUseBlurredAppearance` changing all trigger a re-layout. A panel is redrawn only when its draw model changes.
   - After a wallpaper change or turning auto-hide off, macOS takes the menu bar off screen while it rebuilds it and posts nothing when it is back (observed from about 10 s up to several minutes, ending at the next app switch). While a display's menu bar is missing, Ice Ball looks again at growing intervals (1 s up to 60 s, about 5 minutes in all) and also on every app switch.
7. **Quit / disable.** The system menu bar is never modified; closing the panels restores the standard look.

## Privacy

Ice Ball reads the menu bar's position from the window list, the frames of menus and status items through Accessibility (Split only), and the desktop picture. None of it is stored or sent anywhere. The only network request is the update check at launch, which fetches `appcast.xml` from GitHub Releases. There is no analytics or crash reporting.

## Releasing

```bash
./release.sh 0.1.1
```

The script checks that the tree is clean and pushed, takes the release notes from the version's section of `CHANGELOG.md`, runs the tests, builds and signs the app, makes the DMG and the update zip, signs `appcast.xml` with the Sparkle key in the login keychain, and creates the GitHub release. The Homebrew cask in `piro0919/homebrew-tap` is updated separately.

## Landing page

`lp/` is the page at [ice-ball.kkweb.io](https://ice-ball.kkweb.io): Next.js with next-intl (English and Japanese), deployed on Vercel with `lp` as the root directory. The menu bar samples on wallpaper strips (`lp/src/app/[locale]/menu-bar.tsx`) are drawn in code, matching the app's strings in `IceBall/UI/Localization.swift` and the defaults in `AppearanceConfiguration.swift`; change them together.

```bash
pnpm install
pnpm lp:dev
```

## Findings from Ice

Ice (GPL-3.0) was studied at commit `11edd39` (2025-09-20). No code was copied; this project is an independent implementation. What Ice does, from its source:

| Topic | Ice | Ice Ball |
| --- | --- | --- |
| Overlay | `MenuBarOverlayPanel`: borderless non-activating `NSPanel`, level `.statusBar`, `ignoresMouseEvents`, `.moveToActiveSpace`, re-shown on every Space change | Same kind of panel; `.canJoinAllSpaces` + `.stationary`, no re-show; level below or above the menu bar depending on the system setting |
| Wallpaper | Captures the Dock window titled `Wallpaper…` with the obsoleted `CGWindowListCreateImage…`, every 5 s, plus a 1 s loop for 5 s after a theme change | ScreenCaptureKit of desktop-level windows when Screen Recording is already granted; otherwise decodes `desktopImageURL(for:)`. Refreshed only on events |
| Shape | `NSBezierPath` unions of rects and ovals ("end caps"); the wallpaper is drawn outside the shape with an even-odd clip; inside stroke by doubling the line width and clipping | Rounded rectangles with an adjustable radius; same even-odd and inside-stroke ideas |
| App menu frame | `AXUIElementCopyElementAtPosition` at the display origin, union of enabled children of the `AXMenuBar`; ignored on displays other than the main one, with a comment that Accessibility returns the active display's menu bar regardless; polled every 1 s for 10 s after an app switch, and every 10 s | Same hit test, done for every display: on macOS 27.2.1 it returns each display's own app (Claude on one display, Firefox on the other in testing), with frames on that display. Retried at 0 / 0.15 / 0.5 / 1.5 s after a switch, and every 5 s while Split is on |
| Status item frames | Private `CGSGetProcessMenuBarWindowList` + `CGSGetScreenRectForWindow`, summing item widths | On macOS 27.2.1 that private call returns only the two `Menubar` windows, and the public window list has no status item windows. Ice Ball reads `AXExtrasMenuBar` instead |
| Full screen | Private `CGSSpaceGetType(CGSGetActiveSpace())` | Public window list: a WindowManager window named `Fullscreen Backdrop` covers a display while it shows a full-screen space (seen on macOS 27.2.1). Window geometry alone cannot tell: on a notched display the full-screen window sits below the notch, exactly like a zoomed one |
| Auto-hide | Overlay made fully transparent while `NSApp.currentSystemPresentationOptions` or the `_HIHideMenuBar` default says the bar is hidden, re-read when its control item's window moves | Same policy (no overlay while auto-hide is on). On macOS 27.2.1 the status item's window does not move or change occlusion when the bar hides, so the change is caught by key-value observing `_HIHideMenuBar` on `UserDefaults.standard`, which delivers changes made in System Settings |
| Undocumented names read | Window titles `Menubar` and `Wallpaper…`, global default `_HIHideMenuBar` | `SLSMenuBarUseBlurredAppearance` (global default), WindowServer window `Menubar`, WindowManager window `Fullscreen Backdrop` |
| Private APIs | `CGSMainConnectionID`, `CGSGetWindowList`, `CGSGetOnScreenWindowList`, `CGSGetProcessMenuBarWindowList`, `CGSGetScreenRectForWindow`, `CGSCopySpacesForWindows`, `CGSGetActiveSpace`, `CGSSpaceGetType`, `CGSCopy/SetConnectionProperty`, `CGSEventIsAppUnresponsive` | **None** (see the row above for the undocumented names it reads) |

## Performance

Measured on the development machine with the release build:

- Rounded, idle for 60 s: 0.01 s of CPU time, 15 MB physical footprint.
- Split's work, measured with the same Accessibility calls in a separate program: asking all ~160 processes once takes 1.7 s of wall time but 0.02 s of CPU time; asking the 16 processes that own status items 10 times takes 0.02 s of CPU time. Ice Ball does the small ask every 5 s and the full one every 60 s, only while Split is selected. The cost on the processes being asked was not measured.

Moving the shapes after an app switch, measured as CPU time over 20 switches between Claude and Calculator (Split, shadow on, background shown, notched built-in display): 0.81 s with the movement, against 0.29 s for 0.1.1, so about 26 ms more per switch. Redrawing the whole bar on every frame at 120 frames a second took 2.0 s; redrawing only the moving strip and capping at 60 frames a second brought it to 0.81 s.

There are no timers in Default and Rounded. Split's 5-second timer exists because macOS posts nothing when a status item changes width.

## Known limitations

- **"Show menu bar background" detection is only partly checked.** The global default `SLSMenuBarUseBlurredAppearance` is read as that switch. Toggling the switch in System Settings on macOS 27.2.1 removed the key when turned off and wrote 1 when turned back on, so the mapping holds. With the switch off, though, the system still drew the menu bar as solid dark gray (32, 32, 32) on the development machine, with Claude or Finder in front and with other windows hidden, so how the overlay looks over a transparent bar remains unchecked. If the detection is wrong, override it:
  ```bash
  defaults write io.kkweb.IceBall PlacementOverride below   # or: above; delete the key to go back to detection
  ```
- With the background shown, the fill sits above the menu titles, so its opacity is capped at 35 %.
- Desktop picture from the file: dynamic, shuffle and Aerial wallpapers show only their first frame. Files in another app's container cannot be read; Screen Recording is then needed.
- Menu text color follows the desktop picture, not the overlay. The fill picks the light or dark color from the picture's brightness under the bar; without the picture (no Screen Recording and an unreadable file) it falls back to the system's light or dark setting, which does not follow the picture.
- "Color from Desktop Picture" shows little with "Show menu bar background" on: the fill is capped at 35 % over the system's own bar. On the development machine, a brown wood picture gave a fill of (100, 98, 95) at a sample point, against a neutral (110, 110, 110) with the switch off.
- Status items are taken as the contiguous run from the right edge (gaps up to 16 pt), to skip items that Accessibility reports but macOS does not draw.
- Status item frames are reported for the active display only and are applied to the others from the right edge.
- Status items that macOS hides behind the notch are ignored.
- The full-screen check depends on the undocumented window name `Fullscreen Backdrop`; if a later macOS renames it, the overlay would stay visible in full-screen spaces.
- Login at startup uses `SMAppService.mainApp`; macOS may require approval in System Settings › General › Login Items.

## Verification status

Checked:

- Builds with `swiftc` (Swift 6.4.2, macOS 27.2 SDK, deployment target 26.0) with no warnings; `./test.sh` passes (71 checks).
- Offscreen rendering of Split/Rounded, light/dark, below/above placement (`build/snapshots`).
- On the real machine: one panel per display with a menu bar (notched built-in display and a Sidecar display), at the right frames and window level; no panels when the desktop picture is unavailable in "background shown" mode; CPU and memory above.
- Accessibility frames of app menus and status items, and the private window list no longer listing status items, on macOS 27.2.1.
- With "Show menu bar background" on (above placement, desktop picture captured with ScreenCaptureKit), from Ice Ball's own `--snapshot` captures of both displays (notched built-in and Sidecar):
  - Rounded: one rounded shape, desktop picture outside it, shadow below. Also confirmed by eye on the built-in display.
  - Split: two shapes per display, the left one fitted to that display's own app menus (445 pt for Claude on the built-in display, 360 pt for System Settings on Sidecar), the right one around the status items.
  - Switching the frontmost app from Claude to Finder and back changed the built-in display's app menu extent 445 → 441 → 445 pt within about 0.3 s.
- Auto-hide: turned on and off three times through System Events; the overlay disappeared while the bar was hidden and came back within 2 s of turning it off each time.
- Wallpaper change: setting the built-in display to a solid plum picture repainted the area outside the shapes with it once macOS brought the menu bar back. The bar stayed off screen until an app switch; the overlay followed.
- Split after macOS rebuilt the menu bar: Accessibility then reported the built-in display's menus at y = −9; the region check was changed to accept vertical overlap.
- Light/dark fill: with a black desktop picture the fill turned dark (41/41/43 at a sample point) and with the original light picture light again (129/129/129). The status item's own appearance stayed `VibrantLight` throughout, so the fill now follows the brightness of the desktop picture under the bar (threshold 0.5; macOS's own rule is not documented).
- Revealing an auto-hidden bar with the pointer: the system bar slid in and no overlay was drawn, as intended.
- Resolution change: switching the built-in display to 1352 × 845 redrew the overlay at the new width (the menu bar became 30 pt high); the desktop picture took a few seconds to be recaptured, during which no overlay was shown. Switched back afterwards.
- Status item run: Accessibility reported one item (Raycast) at x = 1158 while the drawn items started at 1292; only the contiguous run from the right edge is used now, and the right shape hugs the visible icons.
- Launch at login: turning the switch on registered the app (`sfltool dumpbtm`: enabled, allowed); turning it off removed it.
- Launch and a second copy: `open` on the built app showed the settings window (window list, layer 0). Opening a copy from another folder left one process; with the window closed beforehand, the running instance showed it again.
- Switching desktops: with a second desktop added on the built-in display, Control-→ and Control-← kept the overlay in place on both desktops (snapshots of each; the second desktop was removed afterwards).
- Shape movement after an app switch, from screen recordings of the built-in display (Split, background shown): Calculator → Claude moved the left shape's end from 648 to 888 px over about 0.2 s, fast at first and slowing to a stop; Claude → Calculator moved it back the same way. Before the change, Claude → Calculator showed one full-width shape for about 0.3 s first (seen with 0.1.1 too), from the empty measurement described under "Regions"; after it, no such frame.
- "Color from Desktop Picture", with the background shown and a brown wood desktop picture: the fill at a sample point was (100, 98, 95) with the switch on and (110, 110, 110) with it off; the settings window showed the switch at the top of Background with the two colors dimmed. With a transparent menu bar it was not checked: turning "Show menu bar background" off on this machine still left a solid system bar (see Known limitations).
- Full screen and the space switch it causes: putting a Finder window into full screen on the built-in display hid only that display's overlay (the Sidecar one stayed), and leaving full screen showed it again. Checked from the window list's on-screen flags.

Not checked:

- How the overlay looks with a transparent menu bar (below placement): this machine has the menu bar background turned on.
- Plugging or unplugging a display (a resolution change, which goes through the same notification, was checked).
- A status item appearing or disappearing: a test app's new status item was not shown by macOS at all (Accessibility returned no value for it), and quitting one of the machine's own status item apps was not done.
- Actually starting at login (registration was checked, a log-in was not done), and so whether the settings window stays closed then. The check reads `keyAELaunchedAsLogInItem` from the launch event.
