# Changelog

## [0.1.4]

- Split: with Dimble hiding status items, the right shape no longer stretches left over the empty space those items leave

## [0.1.3]

- Split no longer turns into one shape for a few seconds after Mission Control. The right shape also no longer shrinks to a few status items for up to a minute afterwards

## [0.1.2]

- Split: when you switch apps, the left shape grows or shrinks to the new app's menus in 0.25 s instead of jumping. With Reduce motion on, it still jumps
- "Color from Desktop Picture" in the Background settings: the fill takes the hue of the desktop picture under each display's menu bar, dark behind light menu titles and light behind dark ones. Off by default; the two colors remain the fallback when the picture cannot be read
- "Reach Toward Pointer" in Shape and Margins: the bottom edge of the shape swells toward the pointer as it nears the menu bar, and springs back when it leaves. Off by default, and off while a menu is open or Reduce motion is on
- The Japanese label for the opacity slider now reads 不透明度. It read 透明度 (transparency), which suggested the opposite of what the slider does
- Split no longer falls back to one shape for a moment right after an app switch

## [0.1.1]

- Opening the app shows its settings window; at login it starts with the window closed
- Only one instance runs: opening a second copy brings up the running one's settings and quits

## [0.1.0]

- First release. Ice Ball draws the macOS menu bar as one rounded shape (Rounded) or two, around the app menus and the status items (Split), with the fill color, opacity, corner radius, margins, border and shadow of your choice
- Works on each display's own menu bar, follows light and dark, hides in full screen and while the menu bar is set to hide automatically
- Japanese and English
- No Dock or menu bar icon: launch the app again to open its settings, which also hold the update check and Quit
- Checks for updates once at launch
