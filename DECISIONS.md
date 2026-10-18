# Decisions

Architecture decision records, feasibility findings, tradeoffs, and work that is deliberately deferred. Status words follow the brief: implemented, planned, provider-dependent, experimental, technically infeasible.

## Phase 0 findings

Verified on the development machine (MacBook Air M2, macOS 27.0.1, Swift 6.4 Command Line Tools, no Xcode):

- ImageIO decodes WebP, AVIF, HEIC and BMP, and encodes AVIF and HEIC, but **cannot encode WebP**. WebP output therefore needs ImageMagick (or another optional encoder).
- `NSImage` renders SVG natively; ImageIO does not read SVG.
- Model I/O imports OBJ, STL, PLY, USD/USDA/USDC/USDZ and Alembic, and exports all of them except USDZ. It does not read glTF, FBX or COLLADA.
- The installed FFmpeg 9.0.2 has libmp3lame, libopus, FLAC, wmav2, libx264/x265, VideoToolbox, libvpx-vp9, SVT-AV1 and WMV2, but **no libvorbis**. Ogg output uses libvorbis, then FFmpeg's experimental native Vorbis encoder, then Opus-in-Ogg, and reports which one ran.
- `NSGlassEffectView` exists from macOS 26; the SwiftUI `@State` attribute is a macro in this SDK whose plugin is not shipped with the Command Line Tools (ADR-011).
- macOS's `bsdtar` is libarchive 3.7.4 and reads RAR 4 and most RAR 5 archives.
- Tangerine and Filee claims were checked against their own pages (PARITY_MATRIX.md).

## ADR-001 Native Swift package, built with Command Line Tools

All code is Swift in one SwiftPM package. The app bundle is assembled by `scripts/build-app.sh` rather than an Xcode project, so the whole product builds with the Command Line Tools alone and the build is reproducible from the terminal. Tradeoff: no asset catalogs or Xcode UI tests; the icon is rendered by a script and UI logic is tested through its models.

## ADR-002 Name

**Ringo** for the app and `ringo` for the CLI, as the brief chose. The bundle identifier is `app.ringo.Ringo`. Before a public release, check Homebrew formulae and casks for an existing `ringo` and rename the formula if needed; the CLI name itself is not reserved anywhere on macOS.

## ADR-003 Finder selection through one Apple Event

macOS has no public API that returns another app's selection. Options considered:

| Option | Verdict |
|---|---|
| Apple Events: `tell application "Finder" to get selection` | **Chosen.** Documented, exact, works for Finder windows and the Desktop, one consent prompt. |
| Finder Sync extension | Only reports selection in monitored folders, needs an app extension target, and is not meant for this. |
| Accessibility scraping of Finder's window | Fragile, needs broader permission, wrong with multiple windows. |
| Pointer position / drag pasteboard | Guessing. Used only for the experimental drag invocation, where the pasteboard is authoritative. |

By default the selection is read only when Finder is frontmost, so a forgotten selection in a background Finder window is not converted by accident (configurable). The menu bar item reads it even when Finder is not in front, because the user explicitly asked.

## ADR-004 Invocation without hijacking Shift and Command

A lone Shift or Command key cannot be registered with `RegisterEventHotKey`, and listening for "Shift pressed" would fire on every capital letter and Shift-click. Ringo therefore uses **double-taps**:

- A tap counts only if the modifier is pressed alone and released within 220 ms with no key, mouse button or other modifier in between. Two taps within 320 ms fire. All three thresholds are configurable.
- Shift-click selection, ⌘C/⌘V, typing capitals, holding a modifier and chords never trigger it (unit tests cover each case).
- Seeing other apps' modifier events requires Accessibility trust. Without it, the Carbon hotkeys ⌃⇧R (convert) and ⌃⌘R (tools) work with no permission. Settings check whether a chosen chord is free.
- Status: double-tap **implemented**; fallback chords **implemented**; drag-and-modifier invocation **experimental** (off by default); drag-and-hold **planned**.
- Force Click and multi-finger gestures in Finder: **technically infeasible** through public APIs. Global monitors do not receive pressure events delivered to other apps, and intercepting them would require an event tap that consumes Finder's input, which the brief rules out.

## ADR-005 Radial panel, focus and outside clicks

A borderless `NSPanel` with `.nonactivatingPanel` becomes key without activating Ringo, so it receives keystrokes while Finder stays the active app. Outside clicks are detected with a passive global monitor, so the click still reaches its target app; nothing is swallowed. Known limitation: the panel is a square; a click in its transparent corners is treated as outside and closes the menu but is not forwarded to the window underneath.

## ADR-006 Not sandboxed; hardened runtime

The App Sandbox would block the core workflow: writing next to arbitrary files the user did not pick in an open panel, running user-installed tools from `/opt/homebrew`, and sending Apple Events to Finder without a temporary-exception entitlement Apple rarely grants. Ringo is therefore distributed outside the Mac App Store, unsandboxed, with the hardened runtime and only the `com.apple.security.automation.apple-events` entitlement. Local builds are ad-hoc signed; Developer ID signing and notarization need an Apple Developer account and are **planned** for a release (`scripts/build-app.sh` is the place to add them).

## ADR-007 Optional tools are discovered, never bundled

Bundling FFmpeg, LibreOffice and friends would add hundreds of megabytes, GPL/LGPL and patent obligations, and update burden, and would not change idle footprint (they only run during jobs). Ringo detects tools on disk lazily, explains what each would unlock, and marks those edges `provider-dependent`. The registry ranks native providers first where quality is equal and lets better external ones (Pandoc for Markdown, FFmpeg's palette GIFs) take over when present.

## ADR-008 No network, no updates over the network

The Sparkle auto-update skill in `.agents/` was not applied: update checks are network calls, and the brief requires none. Updates are manual (rebuild, or a Homebrew cask once one exists). This is shown in Settings → General.

## ADR-009 Redaction by rasterization

Overlay boxes or annotation-based redaction leave the underlying text in the file. Removing glyphs from content streams safely requires a full PDF editor and is easy to get wrong. Ringo rasterizes every page, burns boxes into pixels, rebuilds the PDF from images, and verifies the result (SECURITY.md). Tradeoff: output text is not selectable. Re-adding an OCR text layer for the unredacted parts is **planned**.

## ADR-010 Archive extraction through system libarchive

libarchive is part of macOS, streams large archives and reads ZIP, TAR, GZIP, BZIP2, XZ, 7-Zip and RAR. Ringo validates entry names before extraction, watches the size during it, and cleans links and special files after it (SECURITY.md). Creation also uses `bsdtar` (`--no-mac-metadata`, PAX TAR for long and Unicode names); single-file GZIP uses a native streaming writer that stores the original name.

## ADR-011 SwiftUI `@State` without the macro

In the macOS 27 SDK, `@State` resolves to a macro implemented in `SwiftUIMacros`, which the Command Line Tools do not ship. Views hold `State` storage explicitly (`State(initialValue:)`), or use `ObservableObject` models with `@StateObject` / `@ObservedObject`. `@Observable` works because the Observation macro plugin is shipped. This keeps the "builds with CLT only" property (ADR-001).

## ADR-012 One JSON settings file for app and CLI

`UserDefaults` would tie settings to the app's bundle identifier and make CLI access awkward. A versioned JSON file is readable by both, diffable, exportable, and migrated explicitly (`SettingsMigrator`). Values are merged over defaults key by key, so a bad value falls back instead of breaking the app.

## ADR-013 Atomic, collision-safe output

See ARCHITECTURE.md → Output commit. The important choice is `renamex_np(RENAME_EXCL)`: checking `fileExists` and then renaming would race with other writers.

## ADR-014 Lossless rotation for JPEG and HEIC

Rotating or flipping JPEG and HEIC rewrites only the EXIF orientation tag (verified after writing); pixels are not recompressed. Other formats are rotated in pixels. Viewers that ignore EXIF orientation are rare on current systems; users who need baked pixels can convert to PNG and back.

## ADR-015 Honest PDF → office conversions

| Edge | What Ringo does | Status |
|---|---|---|
| PDF → DOCX, EPUB, HTML, Markdown | Rebuilds paragraphs, headings and lists from line geometry and font sizes; scanned pages need OCR | implemented, fidelity `heuristic` |
| PDF → TXT | Text layer, or Vision OCR | implemented |
| PDF → PPTX | One slide per page, each a picture of the page | implemented, fidelity `image-only` |
| PDF → XLSX | Cells guessed from glyph gaps, one sheet per page | experimental |
| PDF → Pages | PDF → DOCX, then Apple Pages saves it | provider-dependent (Pages) |
| Editable slide reconstruction from PDF | Would need a layout engine Ringo does not have | technically infeasible with current providers |

The UI shows the fidelity on each wedge, `plan` prints the limitations, and results carry them.

## ADR-016 Explicit chains

Two-step routes (PPTX → PDF → PNG, PDF → DOCX → Pages, XLS → XLSX → TSV, DWG → DXF → PDF, HWP → DOCX → Markdown) are listed in `RingoEngine.chains`. Automatic multi-hop search would produce surprising, low-fidelity routes and an unauditable matrix.

## ADR-017 Native implementations where cheap and safe

Ringo implements, without external tools: ZIP read/write for OOXML/ODF/EPUB containers, XLSX/ODS/CSV/TSV, PPTX writing (pictures), EPUB 3 writing, a Markdown reader, subtitle conversion, WOFF 1.0, HWPX and HWP 5 text extraction, gzip streaming. Each one is covered by tests. Formats whose correct implementation is large (WOFF2, DOC/XLS/PPT binary, Pages, DWG) stay with external providers.

## Tradeoff: footprint vs. coverage

Measured on the development machine: 14 MB idle, 24 MB with the radial open, 0 CPU while idle. Coverage comes from lazy providers, so it costs nothing until used. Bundling engines would raise the download size, not the idle footprint, which is why ADR-007 chose discovery for licensing and size reasons rather than memory.

## Deferred and planned work

| Item | Status | Notes |
|---|---|---|
| Developer ID signing, notarization | planned | Needs an Apple Developer account |
| Homebrew cask / formula | planned | Needs a public release URL; template in TESTING.md |
| Conversion chains and saved pipelines in the UI | planned | The CLI `batch` covers scripted pipelines |
| Watched folders in the app | planned | `ringo watch` is implemented in the CLI |
| MCP server | planned | The CLI JSON contract is the integration point |
| OCR text layer on redacted PDFs | planned | ADR-009 |
| Image quality comparison preview | planned | |
| Video speed change, audio normalize, QR reading, collages (Tangerine extras) | planned | PARITY_MATRIX.md |
| Drag-and-hold invocation | planned | Drag + modifier is experimental today |
| Force Click / trackpad gestures in Finder | technically infeasible | ADR-004 |
| Faithful PDF → editable slides | technically infeasible | ADR-015 |
| RAR creation | out of scope | The brief requires input only |
