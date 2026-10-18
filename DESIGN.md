# Design

The radial is the product. It has to appear instantly, be readable over any wallpaper, and be as easy with a keyboard or a trackpad as with a mouse.

## Geometry

| Token | Default | Range (Settings → Radial Menu) |
|---|---|---|
| Outer radius | 168 pt (336 pt disc) | 130–230 pt |
| Hub radius | 36 % of the outer radius, at least 48 pt | derived |
| Wedges | 8 | 6–10 |
| Wedge gap | 3 pt, constant width (angular gap differs at inner and outer edge) | fixed |
| Panel margin | 26 pt around the disc for shadow and rim light | fixed |
| Icon size | 22 pt | 16–30 pt |

- Wedge 0 is centered at 12 o'clock and indexes run clockwise. Number keys follow that order.
- Hit testing is by angle. Anything outside the hub and inside the panel selects the wedge in that direction, so the pointer only needs a direction, not a target. The hub is "back".
- A level with more items than wedges shows `n − 1` items plus a **More** wedge that pages forward (wrapping). Search results page the same way.
- The panel is placed centered on the pointer and clamped to the visible frame of the screen under it (menu bar, Dock and camera housing excluded). Only the transparent margin may cross an edge.

## Wedge content

Each wedge shows an SF Symbol, a short title (format name or action) and a subtitle: the fidelity for conversions (Lossy, Lossless, Rasterized, Text only …), "Options…" for actions that open a panel, or coverage such as "2 of 3" when it applies to part of a mixed selection. Disabled wedges stay in place at 45 % opacity with a ⃠ badge, and the hub shows the reason when they are focused ("Requires FFmpeg. Install it with `brew install ffmpeg`."). Color is never the only signal: focus also changes the outline weight and slightly scales the label.

The hub shows the selection's first thumbnail (generated asynchronously; the menu never waits for it), a summary such as "3 PNG files", the focused item, and the breadcrumb or search query. It never shows file names.

## Glass

| Material | Implementation | When |
|---|---|---|
| Liquid Glass (default) | `NSGlassEffectView` clipped to a circle | macOS 26 and later |
| Frosted | `NSVisualEffectView`, `.hudWindow`, behind-window blending | before macOS 26, or chosen |
| Solid | Window background color | chosen, High Contrast, or Reduce Transparency |

On top of the material: a faint tint of the window background (18 % × opacity) so text stays readable on busy wallpapers, a 1 pt rim with a top-to-bottom white gradient (55 % → 8 %), a 0.5 pt dark hairline, and an 18 pt soft shadow.

### Opacity

The slider runs from 20 % to 100 % and changes only the glass body; labels and the focus highlight stay fully opaque. Below 60 %, each label gets its own small material plate so text keeps contrast at any setting. The settings pane shows a live preview over a deliberately busy gradient, and the next menu uses the new value.

## Motion

- Appear: spring, response 0.22 s, damping 0.82, from 90 % scale and 0 opacity.
- Focus change: spring, response 0.18 s. Level change: response 0.24 s.
- The animation speed multiplier (0–2×) divides response times; 0 turns animation off.
- Reduce Motion (system, or forced in settings) removes scale effects and keeps short fades.
- The panel is on screen before the selection is read. Measured hot path: 28–44 ms to a populated first frame when warm (see [TESTING.md](TESTING.md)).

## Keyboard

| Key | Action |
|---|---|
| 1–8 | Focus that wedge (when no search is active) |
| ← → / Tab ⇧Tab | Move focus around the ring |
| ↓ | Open the focused submenu or next page |
| Return / Space | Run the focused action, or open the submenu |
| ↑ | Back one level (or back to page 1) |
| Letters, digits after a letter, `.` `-` | Search inside the ring across every level, e.g. `webp`, `mp4`, `crop` |
| Backspace | Edit the search; with no search, go back |
| Escape | Clear the search, then go back, then close |
| ⌘W / ⌘. | Close |

Nothing runs on focus alone. The menu closes only on Return, a click on an action, a click outside, or Escape at the top level. Selection does not time out and does not close when another app takes focus.

Inspector panels follow the standard pattern: Return applies, Escape cancels. The canvas editor (crop, markup, area redaction) is fully keyboard-operable: arrows move the selection by 1 px (⇧ 10 px), ⌥ arrows resize the crop, Tab selects the next shape, Delete removes it, ⌘Z undoes, `[` `]` change PDF pages.

## Trackpad and pointer

- Hovering focuses by angle; clicking or tapping runs.
- Two-finger scroll turns the ring one wedge per 18 points of scroll (one step per wheel notch on a mouse).
- Right click or a click on the hub goes back.
- Optional dwell (Settings → Radial Menu) opens submenus after resting the pointer 450 ms. Dwell never runs an action.
- Experimental drag invocation: while dragging files in Finder, tap ⇧ or ⌘ and drop onto a wedge. Finder's own drag and drop is untouched because Ringo only observes events.

## Accessibility

- Every wedge is an accessibility element with a label that includes its title, fidelity, coverage, submenu status and unavailability reason, plus a "run" action.
- With VoiceOver on, focus changes are announced; opening the menu announces the mode; a disabled selection announces its reason; job completion announces the result from the progress panel.
- High Contrast swaps glass for an opaque background, thickens outlines and uses a fully opaque focus color.
- Reduce Transparency and Reduce Motion are honored automatically.
- Light, dark or system appearance is selectable for the radial independently of the system.

## Progress and results

After an action the radial closes at once. A compact panel appears below where the radial was, showing a progress bar and a cancel button. When the job ends it shows "Done", "3 files done" or "2 done, 1 failed", with Reveal (selects outputs in Finder) and a details list of per-file results and warnings. Success hides after 4 seconds; failures stay until dismissed. The menu bar icon changes while a job runs, and its menu keeps the last result.

## Settings window

The only conventional window, built after the local `macos-settings-ui` skill: an `NSWindowController` with `.fullSizeContentView` for Liquid Glass chrome, a fixed sidebar, back/forward history, and grouped transparent forms. Panes: General, Shortcuts, Radial Menu, Conversion, File Tools, Providers, Advanced, About.
