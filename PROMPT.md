# MASTER IMPLEMENTATION PROMPT — Native macOS Radial File Utility

> Status: Product specification and agent implementation brief. Do not interpret aspirational conversion support as proof of lossless or universally possible transformations. Implement capability detection and truthful error reporting.

## 0. Your role and deliverable

You are a senior macOS engineer, interaction designer, accessibility engineer, media conversion architect, and quality engineer. Design and implement a production-grade, fully local, native macOS file conversion and editing utility. This document is the source of truth. Start with feasibility audits, architecture and a conversion capability matrix; implement incrementally with tests. Do not silently drop any requirements. If a conversion requires an external provider, proprietary application, or lossy approximation, disclose this clearly in UI, CLI and documentation. Never fabricate conversion success. Use the skills inside `.agents` when building and use the global skill `unslop` when writing documentation. You will also take care of git end-to-end.

The product combines Tangerine's beautiful radial-menu, floating, drag-and-drop conversion aesthetic, Filee's breadth and customizability, and Raycast-like keyboard efficiency. Unlike mouse-first tools, it is first-class for trackpad and keyboard users. It must not require an ordinary standalone application window to perform conversions or tools. Settings can use a conventional native preferences window; conversion interaction must use the radial overlay.

## 1. Naming

The GUI app name and executable CLI name MUST be the same concise word (CLI lowercased).

- **Ringo** / `ringo` — short, playful, circular-menu association.

## 2. Non-negotiable product constraints

1. Conversion and file-tool invocation MUST use a floating radial menu, not a normal standalone application window.
2. Native macOS implementation: Swift, AppKit, SwiftUI where appropriate, Core Animation, native frameworks. **No Electron**, web-based UI shell, or heavy always-running runtime.
3. Very lightweight: target idle memory <30–50 MB where feasible, low CPU, negligible idle battery drain, lazy initialization, and no conversion subprocesses while idle. Measure, do not assert unverified figures.
4. Support the complete explicitly enumerated format catalog in §8, plus all *verified* Tangerine and Filee capabilities where feasible. Maintain an auditable feature-parity inventory. Do not conflate supported input/output formats with every possible directed pair of conversions.
5. Fully local and private. Never upload user files, filenames, previews, metadata, or conversion content. No required account, cloud processing, telemetry or network access for operations. Optional dependency installation may require network only when user explicitly requests it.
6. Full headless CLI for humans, scripts, and agents; same name as app and same conversion core. CLI must work when GUI is not running.
7. Keyboard, trackpad, and mouse must all be comfortable; no mouse-only essential action.
8. Native liquid-glass-inspired translucent radial visual design with user-adjustable opacity slider.
9. On successful conversion/edit, save output directly into the source file's directory by default; do not open a save dialog for ordinary operations.
10. Preserve originals by default; editing/redaction/compression should create a new sibling file unless user explicitly opts into overwrite. Atomic output writes and collision-safe naming are mandatory.

## 3. Definitive Finder interaction contract

### 3.1 Invocation

- User selects **one or multiple files in Finder**.
- User invokes a **customizable global shortcut**; radial menu appears **near the current cursor**, clamped to visible screen bounds and adjusted around notch, menu bar, Dock and screen edges.
- Default **conversion mode trigger: Shift**.
- Default **file tools mode trigger: Command (⌘)**.
- These defaults express user intent, but modifier-only global shortcuts are technically and ergonomically hazardous: Shift and Command are needed for selection, typing and standard OS shortcuts. The implementation MUST feasibility-test modifier-only invocation and provide a conflict-safe mechanism (e.g. configurable double-tap Shift / double-tap Command, modifier release, or modifier+key fallback), without hijacking ordinary key presses. Do not claim a lone Shift or Command key can safely be registered through normal global hotkey APIs. Present the exact gesture semantics clearly in settings and onboarding; retain Shift/Command as the conceptual default keys.
- File selection must be obtained reliably from Finder, not inferred from hovered pixels or cursor location. Use AppleScript/System Events, Finder scripting, an approved Finder integration or other documented macOS APIs as appropriate, and carefully scope automation permissions. Handle Finder not frontmost, Desktop selections, iCloud placeholders, aliases, symlinks, packages, directories, multiple Finder windows and empty selections. Avoid persistent polling.
- Support optional drag-with-modifier Tangerine-style invocation for mouse users, but prioritize keyboard-first Finder selection. Optional drag-and-hold (~300 ms) and Force Click / trackpad gestures are experimental enhancements only; do not make them prerequisites. Finder already owns some gestures and Force Click; public macOS APIs may not permit globally intercepting them reliably. Never break normal Finder drag-and-drop.

### 3.2 Radial persistence and dismissal

- Once shown, **the radial menu remains visible** until (a) the user chooses a valid output/tool action, (b) the user clicks somewhere outside the menu, or (c) the user explicitly dismisses via Escape. No automatic timeout, no disappearing merely because pointer moves, and no focus-loss disappearance except a deliberate outside click. Keyboard selection alone does not dismiss; pressing Enter confirms.
- Selecting an output by pointer click executes immediately. Keyboard navigation followed by Enter executes. Clicking elsewhere dismisses without modifying files.
- On success, output goes to the same directory as the source. For multi-file selection, each file is processed in its own original directory, with individually reported outcomes.
- After confirmation, dismiss radial overlay promptly; run conversions asynchronously; provide subtle nonblocking progress/notification feedback. Never freeze the menu while transcoding.
- Handle click-outside detection without swallowing clicks intended for other applications; test macOS input monitoring/Accessibility permissions, app activation, focus, and multi-display behavior. Do not globally intercept inputs unnecessarily.

### 3.3 Keyboard interaction

- Numeric `1`–`8` choose eight stable radial sectors when appropriate.
- Left/Right rotate selection; Up/Down navigate nested levels or categories; Enter confirms; Escape closes/goes back according to clear hierarchy; Tab may cycle focus.
- Typing a format (`webp`, `pdf`, `mp4`) immediately searches/highlights eligible targets **inside the radial interface**. Search is not a separate command-palette window. Backspace edits query; Escape first clears query or backs out, with documented semantics.
- Accessibility: VoiceOver labels and announcements, full keyboard control, reduced motion/transparency, high contrast, dynamic text/legible labels, predictable focus. Never rely on color alone.
- The menu prioritizes compatible operations. Unavailable conversions must be absent or visibly disabled with reason; never imply unsupported conversion is supported.

### 3.4 Trackpad and pointer interaction

- Minimal precision requirements: large hit targets, forgiving wedge geometry, pointer-angle selection with optional dwell, clear hover feedback, no tiny submenus.
- User can select files, trigger via keyboard, then choose wedge with trackpad tap/click. Also allow keyboard-only completion.
- Optional drag-and-hold, Force Click and multi-finger gestures must be opt-in, tested for macOS API limitations and conflicts. A keyboard shortcut is the guaranteed path.
- Optional mouse interaction: drag selected file while holding configurable modifier, radial appears and dropping over an eligible wedge converts. Implement only when safe and reliable; do not compromise Finder drag semantics.

## 4. Two radial modes

### 4.1 Convert mode — Shift default

Show contextual output formats based on the actual selected file type(s). For heterogeneous selections, offer common compatible operations, category-specific batches, or an explicit per-file action plan; do not silently skip unsupported inputs. Provide quick format selection and secondary radial pages for less common formats. Support mixed file selection gracefully.

### 4.2 File Tools mode — Command default

Benchmark Tangerine's six user-specified top-level tools and implement:

1. **Compress** — images/video/audio/PDF where supported; quality/size presets, lossless vs lossy distinctions, optional archive creation for arbitrary files, estimated size when reliably measurable.
2. **Edit Metadata** — view and edit supported EXIF/IPTC/XMP/media/document metadata, batch edits, privacy-stripping preset; expose field availability and preserve unsupported fields where possible.
3. **Edit** — contextual lightweight edits: rotate/flip/resize images, trim audio/video, reorder/rotate/delete PDF pages, etc.; avoid promising a full photo/video editor.
4. **Annotate** — native lightweight markup for images/PDF: text, shapes, arrows, highlighting, pen, signatures if feasible; produce non-destructive output. Use an overlay/sheet anchored to the radial interaction for parameter-rich workflows rather than making a conventional main application window.
5. **Crop** — image and PDF crop; video crop if provider supports it; explicit aspect ratios, bounds, non-destructive output.
6. **Redact** — **irreversible** privacy redaction where possible: flatten/remove original content, embedded OCR text, metadata, thumbnails and recoverable underlying PDF objects. A black visual overlay alone is NOT sufficient. Verify redaction by text extraction/object inspection; warn when guarantees cannot be made.

For all six, create a detailed Tangerine benchmark inventory (actual UI, supported file classes, presets, limitations, speed, batch behavior) from verifiable primary sources or direct hands-on testing. Do not invent undocumented Tangerine behavior. Each tool should show a context-aware radial submenu or anchored native parameter surface, with a clear confirm/cancel path. Settings windows are allowed; a standalone converter/editor main window is not.

## 5. Visual language and interaction design

- **Liquid Glass** visual direction: frosted/translucent native material, restrained specular highlights, delicate rim/border lighting, subtle shadow, refined SF Symbols, clean typography, tasteful blur, macOS light/dark adaptation.
- Use NSPanel (borderless, floating, nonactivating if practical) and AppKit for windowing, SwiftUI for declarative content where it performs well, Core Animation for precise smooth transitions. Follow actual macOS SDK support and avoid falsely claiming a material is available on older OS versions.
- Central hub shows input icon/thumbnail, file count, current mode and selected action; avoid exposing sensitive filename text unnecessarily in persistent UI.
- Default eight radial segments around hub; adaptive category rings or paginated/nested radial menus for hundreds of formats. Geometry must account for labels, large targets, and edges.
- Example PNG primary choices: WebP, AVIF, JPEG, HEIC, TIFF, PDF, BMP, More. SVG is **input-only**, not a promised PNG→SVG conversion.
- Short spring animations, aiming for 120 Hz on capable displays but adapting to 60 Hz, low-power mode and Reduce Motion. Prioritize perceived responsiveness and instant appearance over elaborate effects.
- **Settings: opacity slider** with immediate live preview, clearly defined range (e.g. 20–100% visual opacity), with readable contrast safeguards; also blur strength/material choice if practical.
- Customization: radial sector count/layout, stable sector placement, favorite outputs, pinned operations, category ordering, format filtering, keyboard bindings, invocation gestures, output naming, output directory override, overwrite policy, quality/compression presets, animation speed, appearance, accessibility settings.
- Smart suggestions can rank frequently used formats, but **must not silently rearrange pinned wedges**, preserving muscle memory. Dynamic suggestions opt-in and deterministic.
- No Dock icon during normal background operation if configured; optional menu-bar item for settings, status, permissions and quitting. No intrusive splash screen or obligatory window.
- Progress: compact floating indicator or menu-bar status; completion notification optional; accessible error details, per-file summary, reveal-in-Finder action. Preview before conversion where inexpensive; optional quality comparison for images; never block initial menu render on previews or estimated sizes.

## 6. Architecture — single core, multiple frontends

```text
Finder selected files ── selection bridge ── global shortcut / gesture router
                                              │
                                              ▼
                                   Native Radial UI (AppKit/SwiftUI)
                                              │
CLI / scripts / agents ────────┐               │
                               ▼               ▼
                        Unified Application Service
                     (validation / planning / jobs)
                               │
                         Capability Registry
                               │
                     Conversion & Tool Engine
                               │
            ┌──────────────────┼───────────────────┐
            ▼                  ▼                   ▼
      Apple frameworks    bundled libraries    optional providers
      ImageIO/PDFKit      libarchive/FFmpeg    LibreOffice/Pandoc/
      AVFoundation etc.   etc.                Calibre/Blender etc.
                               │
                    atomic same-folder outputs
```

Use a Swift Package monorepo with clear modules (names illustrative):

- `AppShell`: app lifecycle, status bar, preferences, permission/onboarding flow.
- `FinderBridge`: reliable Finder selection, file URLs, bookmarks/permissions, file coordination.
- `ShortcutService`: shortcut configuration, modifier tap recognition, conflicts, accessibility/input event policy.
- `RadialUI`: panel lifecycle, geometry, rendering, animation, pointer and keyboard interaction, search, VoiceOver.
- `Domain`: format identifiers, conversion edges, action types, capability constraints, typed errors.
- `CapabilityRegistry`: input/output pairs, availability, provider dependencies, installed provider discovery, quality and fidelity flags.
- `ConversionCore`: provider protocol, planning, execution, cancellation, progress, resource limits, temp files and output commits.
- `FileTools`: six action families and context-sensitive parameter schemas.
- `ProviderNative`: ImageIO, Core Image, AVFoundation, PDFKit, Quartz, Apple document APIs where legitimate.
- `ProviderExternal`: FFmpeg, ImageMagick, Pandoc, LibreOffice, Calibre, FontTools, Assimp/Blender and other carefully scoped tools when required; prefer reuse over reinventing codecs.
- `SettingsStore`: versioned settings, migration, defaults, import/export (JSON or TOML).
- `CLI`: Swift ArgumentParser, structured JSON and text output, exit codes, completion scripts.
- `Tests`: unit, integration, golden conversion fixtures, UI, performance, privacy and accessibility.

Conversion providers must implement capability discovery, input sniffing, output validation, execution, progress/cancellation, diagnostics, and deterministic errors. Capability metadata includes `sourceType`, `targetType`, `operation`, `provider`, `installed`, `fidelity`, `limitations`, `batchSupport`, `estimatedCost` and required permissions. Do not confuse extensions with verified MIME/UTType/content signatures. Provider priorities and fallback strategies should be explicit and user-configurable where useful.

The core must not import AppKit or depend on GUI lifecycle. CLI and GUI call the same application service, but can run as separate processes. Avoid an always-running privileged helper. Keep expensive engines out of memory until needed. Use sandbox/security-scoped bookmarks only where applicable; assess tradeoffs of sandboxing vs Finder automation, CLI and external providers. Never bypass macOS security prompts or silently request broad permissions.

## 7. Output semantics, batch and reliability

- Default destination: **same directory as each source**.
- Default naming: `<stem>.<target-ext>` if unused; on collision use stable, understandable suffixes such as `<stem> (converted).<ext>` or numbered variants. Tool actions should use `<stem> (compressed)`, `<stem> (redacted)` etc. Preserve original unless explicitly told otherwise.
- Never overwrite source by default even when input and output extensions match.
- Write to unique temporary sibling or secure temp location, fsync/validate where appropriate, atomically move into destination, clean up on failure/cancel. Handle insufficient disk space and cross-volume semantics.
- Metadata preservation/stripping policies must be explicit; orientation, ICC color profiles, alpha channel, animation, audio tracks, subtitles, timestamps and document layout need fidelity-aware handling.
- Batch: bounded concurrency, resource budget, cancellation, partial success reporting, no silent skips, deterministic ordering where user-visible, large file streaming, per-file progress.
- For operations with lossy conversion, indicate lossiness; provide quality presets and optional advanced settings.
- For cloud-placeholder files in Finder, request explicit consent before any download; do not pretend conversion is offline if input must first be hydrated from iCloud.
- Local privacy: no telemetry, network conversion, external upload, or hidden analytics. Verify third-party dependencies don't call home. Use secure subprocess invocation (no shell interpolation), timeouts and file size/resource limits.

## 8. REQUIRED format inventory — preserve exact user-specified scope

These are format families and directed conversion expectations; do not promise all pairwise conversions. Build a **directed matrix** with input/output availability, quality limitations, provider and tests for each meaningful edge. All explicitly listed items MUST appear in the registry and documentation, even if a particular edge is conditional on an optional provider. Maintain truthful capability status.

### 8.1 Images

- JPG / JPEG
- PNG
- WebP
- HEIC
- TIFF
- AVIF
- BMP
- PDF **export**
- SVG **input only** (SVG rasterization; not automatic bitmap-to-vector output)

Preserve transparency when supported; handle animation/multipage images explicitly, ICC profiles, EXIF and orientation. SVG may require a renderer; HEIC/AVIF support is OS/framework/provider dependent. PDF export from images should preserve aspect ratio and configurable page dimensions.

### 8.2 Audio

- MP3
- M4A
- WAV
- FLAC
- OGG
- Opus
- AIFF
- WMA

Expose codec/container distinctions (e.g. Ogg/Opus), bitrate/sample rate/channels, tags and lossless-vs-lossy caveats. WMA and some codecs require optional FFmpeg builds with appropriate licensing.

### 8.3 Video

- MP4
- MOV
- MKV
- WebM
- AVI
- WMV
- GIF
- MP3 **export** (audio extraction)

Video conversion is container + codec selection, not extension renaming. Handle variable frame rate, rotation, subtitles, multiple audio streams, HDR, alpha and hardware acceleration limitations. GIF export needs frame rate, resolution, palette and duration controls. MP3 export must fail clearly when no audio track exists.

### 8.4 PDF

PDF input →
- DOCX
- PAGES
- PPTX
- XLSX
- JPG
- PNG
- EPUB
- TXT
- MD / Markdown

- **All pages** must be supported, with **300 DPI** default for raster image export (user-adjustable).
- PDF→editable Office/Pages/EPUB/Markdown is inherently difficult and may be lossy or impossible for scanned/complex PDFs. Use optional OCR, layout reconstruction, LibreOffice or specialist engines where technically feasible; mark fidelity and prerequisites honestly. Pages output may require Apple Pages automation and an installed copy; there is no general-purpose public Pages writing API. Do not advertise faithful PDF→PAGES or PDF→XLSX as guaranteed.
- PDF image export must support multipage output naming and 300 DPI rasterization.

### 8.5 Documents

- DOCX
- PAGES
- Markdown / MD
- TXT
- EPUB
- RTF **input**
- RTFD **input**
- macOS text clippings **input**
- HTML **export**

Support meaningful document conversion paths with documented fidelity. Pages input/output may require local Apple Pages automation; RTFD and text clippings need native macOS handling. HTML export must be local. Treat embedded assets and complex formatting carefully.

### 8.6 Slides

- PPT / PPTX **input**, with **PPT input only** for legacy PPT
- PDF **export**
- JPG **export**
- PNG **export**
- PDF → PPTX **import/conversion**

Preserve slide order and one-image-per-slide export. PDF→PPTX should distinguish placing each PDF page as an image vs reconstructing editable slide objects; do not claim the latter without a verified engine. PowerPoint/Keynote/LibreOffice providers may be needed; never assume installed.

### 8.7 Spreadsheets

- XLSX
- ODS
- CSV
- TSV
- PDF **export**
- XLS **input only**

Define sheet selection, multi-sheet output behavior, delimiters/encodings, formulas vs values, date formats, locale, merged cells and layout fidelity. XLSX/ODS→CSV/TSV is inherently sheet-dependent; surface the choice or documented default. PDF export may require LibreOffice or a native renderer.

### 8.8 Subtitles

- SRT
- VTT
- TXT **export**

Handle timestamp semantics, multiline cues, styling differences, encoding and BOM. TXT export drops timing by definition unless a timestamped-text preset is chosen.

### 8.9 Archives

- ZIP
- TAR
- GZIP
- RAR **input only**

Distinguish archive packaging from compression; GZIP normally compresses one stream, while TAR+GZIP packages multiple files. RAR extraction requires a compatible legal decoder/provider; no RAR creation requirement. Prevent zip-slip/path traversal, symlink escapes, decompression bombs and unsafe overwrite on extraction. Archive extraction should default to a sibling folder and respect same-directory semantics.

### 8.10 Filee parity and extra formats

Previous exploration mentioned Filee advertising 244 formats and support across images, audio/video, PDF, Office, EPUB, HWP/HWPX, archives, fonts, CAD and 3D models, plus batch and watched folders. Tangerine was described as advertising 275 conversion **options**; these numbers measure different things and MUST NOT be compared as identical counts. Treat both figures as claims requiring current verification, not as acceptance criteria. Create a `PARITY_MATRIX.md` listing every **verified** Tangerine and Filee feature/conversion, its evidence, priority, provider, status and test coverage. Include HWP/HWPX, fonts, CAD/3D and watched folders as parity candidates if confirmed; never omit them silently, but do not invent unsupported conversions. The explicitly enumerated catalog above has priority over unverified marketing counts.

## 9. File tools — detailed requirements

For each of Compress, Edit Metadata, Edit, Annotate, Crop and Redact:

- Provide an eligible file-type matrix, native/external provider mapping, parameter schema, default presets, radial flow, keyboard flow, CLI commands, batch semantics, non-destructive output naming, tests, and failure cases.
- Prefer lightweight quick actions for the first ring; advanced parameters can appear in a nested ring or compact anchored inspector/panel (not a separate full converter window).
- Compression should separate archive compression, lossy transcoding and lossless optimization. Report before/after sizes and whether quality changed.
- Metadata edit should support metadata inspection, removal and selective edits with warnings for formats/providers that cannot safely rewrite metadata.
- Edit should include image rotate/flip/resize, media trim where available, PDF page operations; expand only with tested capabilities.
- Annotate should support image/PDF markup with editable staging until confirmed; preserve source and ensure flattened/exported output is correct.
- Crop should allow aspect ratio presets and visual bounds, with precise keyboard controls.
- Redact must prioritize security: remove underlying recoverable content and associated metadata, not merely obscure pixels; include tests that attempt extraction/recovery from redacted outputs.

## 10. CLI contract — first-class agent interface

Use the same short executable name as the GUI application. Examples use `<app>` as placeholder; adapt syntax consistently after choosing the final name:

```bash
<app> convert image.png --to webp
<app> convert document.docx --to pdf
<app> convert video.mov --to mp4
<app> convert '*.png' --to avif --quality 85
<app> formats --json
<app> capabilities --json
<app> inspect image.png --json
<app> plan document.pdf --to pptx --json
<app> tools --json
<app> compress image.png --preset balanced --json
<app> metadata show image.jpg --json
<app> metadata strip image.jpg --json
<app> edit rotate image.png --degrees 90 --json
<app> crop image.png --rect 0,0,800,600 --json
<app> redact document.pdf --regions regions.json --json
<app> batch --manifest jobs.json --json
<app> providers doctor --json
```

- Also consider ergonomic shorthand `<app> image.png webp` as an alias, but prefer unambiguous canonical subcommands.
- Headless, no GUI dependency, no user interaction unless explicitly requested. Flags for `--output`, `--output-dir`, `--overwrite`, `--dry-run`, `--preset`, `--quality`, `--pages`, `--provider`, `--timeout`, `--jobs`, `--no-network` and `--json` where relevant.
- JSON schema version, stable machine-readable errors, progress events (NDJSON on stdout or stderr by documented convention), deterministic exit codes, file URL/path output, per-file results, warnings, provenance/provider and fidelity fields.
- Agent-friendly capability discovery: exact directed conversion edges and tools, prerequisites, parameter schemas, installed providers, whether operation is lossy, and why unsupported.
- Proper stdout/stderr separation, shell quoting, glob handling, Unicode filenames, spaces, non-ASCII paths and symlinks. Never interpolate untrusted filenames into shell commands.
- Provide `--help`, shell completions, CLI reference and agent integration examples. MCP server optional future layer, not a substitute for the CLI.

## 11. Settings and preferences

- Native settings window allowed (only settings, not conversion workflow).
- General: launch at login, menu-bar icon, notifications, Finder selection behavior, update policy, local-only policy.
- Shortcuts: Shift conversion and Command file-tools defaults with safe modifier-only gesture semantics, customization, conflict checker, alternate key combinations, mouse drag gesture and experimental trackpad gestures.
- Radial: opacity slider/live preview, blur/material, light/dark, radius, segment count, icon size, labels, order, pinned formats, favorites, nested categories, animations, reduce-motion handling.
- Conversion: providers, quality presets, fidelity warnings, format filtering, dynamic suggestions opt-in, batch concurrency, default DPI 300 for PDF image export, output directory same-as-source by default, naming/collision policy, metadata policy.
- Tools: compression presets, metadata strip presets, editing defaults, annotation styling, crop presets, redaction safety preferences.
- Advanced: CLI installation path, dependency doctor, configuration export/import, log level, reset defaults, diagnostic report without sensitive file content.
- Persist settings with a versioned schema and migrations. Settings must affect GUI and CLI consistently where appropriate; CLI flags override defaults without mutating them.

## 12. Performance, privacy and accessibility targets

- Idle target <30–50 MB if feasible; establish baseline by macOS version and build configuration. Idle CPU ~0%, no background file scans or polling, no heavy subprocesses until requested.
- Radial should appear perceptually instantly; target <100 ms for hot path on representative Apple Silicon after warm-up, measured with instrumentation. Do not block appearance on thumbnails, Finder automation or format probing; show lightweight loading/empty state if needed.
- Lazy load conversion backends, reuse safe providers, cap memory and concurrent encodes, support cancellation.
- Local-only processing, opt-in dependency downloads, no analytics/telemetry, no silent network requests. Document third-party licenses and their redistribution implications (especially FFmpeg builds, GPL/AGPL providers and codecs).
- Full keyboard navigation, VoiceOver, reduced transparency/motion, high contrast, color-blind safe cues, readable opacity bounds and target sizes.
- App signing/notarization, hardened runtime and entitlements assessed against actual Finder automation, CLI, external binaries and permissions. Handle Accessibility/Automation consent transparently; never request more than necessary.

## 13. Testing and acceptance criteria

Build a fixture-based test suite with representative samples for every catalog item and every implemented directed conversion edge. Include corrupt/mislabeled files, zero-byte files, huge files, multi-page PDFs, multiple slide/sheet documents, animated images, VFR/HDR video, metadata/ICC, multilingual paths, permission errors, sandboxed directories, file collisions, canceled jobs, unsupported conversions and missing providers.

Critical end-to-end acceptance cases:

1. Finder single selection → conversion shortcut → cursor-adjacent radial → keyboard selection → Enter → new sibling output.
2. Finder multi-selection → shortcut → compatible format → outputs in **each source directory**, originals preserved, per-file results.
3. Finder selection → file-tools shortcut → all six tool entries available contextually → action → sibling output.
4. Menu persists indefinitely until valid action, outside click, or Escape; outside click passes through appropriately.
5. Trackpad-only navigation is practical without drag precision; keyboard-only path is complete.
6. Opacity slider updates glass radial preview and live menu, while text remains readable.
7. GUI and CLI use identical capability registry and conversion results.
8. CLI runs with GUI closed and outputs valid versioned JSON.
9. Offline operation verified by network-denial test; no unexpected connections.
10. PDF→JPG/PNG processes all pages at 300 DPI by default.
11. Input-only SVG, PPT, XLS, RTF/RTFD/clippings and RAR do not erroneously appear as output promises.
12. Redaction tests prove text/content is not trivially recoverable from output.
13. Missing optional providers result in precise actionable errors, not crashes or false success.
14. Radial keyboard shortcut implementation does not interfere with normal Shift selection, Command shortcuts, typing, or Finder operations.
15. No Electron, no persistent heavyweight conversion daemon, and measured idle footprint/battery behavior.

## 14. Implementation sequence — agent execution plan

**Phase 0 — research and feasibility.** Inspect official Tangerine and Filee product/docs/repositories (where accessible); produce a source-backed feature parity inventory, directed format matrix and provider/license matrix. Verify current macOS SDK, Finder selection APIs, global modifier-key detection, click-outside event behavior, accessibility/automation entitlements and compatibility target. Identify technically impossible/unreliable paths before coding. Document assumptions and decisions.

**Phase 1 — architecture skeleton.** Create Swift package modules, shared domain types, capability registry, provider interface, output planner, settings store, typed errors and structured logging. Establish CI, fixtures and tests. Choose app/CLI name after collision checks.

**Phase 2 — Finder + radial MVP.** Build background native app, menu bar/settings, selection bridge, conflict-safe Shift/Command triggers, cursor-adjacent floating radial, persistence/dismissal, pointer and keyboard controls, opacity slider and accessible visual design. Test multi-monitor, Finder selection and focus behavior.

**Phase 3 — native conversions + CLI.** Implement high-quality common image formats, PDF image export at 300 DPI, basic audio/video paths, archives and text/subtitles where available. Add headless CLI with capability discovery, batch, JSON, dry-run and diagnostics. Confirm shared engine parity.

**Phase 4 — advanced providers.** Integrate optional FFmpeg, LibreOffice, Pandoc, Calibre and other vetted local providers. Add document/slides/spreadsheet/PDF reconstruction paths with honest fidelity labels. Implement user-specified full format inventory and verified Filee/Tangerine parity matrix progressively.

**Phase 5 — six file tools.** Implement Compress, Edit Metadata, Edit, Annotate, Crop and Redact with safe defaults and contextual radial parameter UI. Security-test redaction and archive extraction.

**Phase 6 — polish, performance and distribution.** Add animation/appearance tuning, stable customization, keyboard search, optional smart suggestions, accessibility, performance profiling, dependency doctor, signing/notarization, Homebrew distribution, privacy/security audits and thorough documentation.

**Phase 7 — optional enhancements.** Drag-and-hold, Force Click or trackpad gestures if viable; conversion chains and saved pipelines (e.g. MOV→MP4→compressed MP4, DOCX→PDF→optimized PDF), watched folders, richer previews, MCP server and extended Filee parity including HWP/HWPX, CAD/3D and fonts if supported by reliable providers. None of these should delay correctness of the primary workflow.

## 15. Required repository documentation and agent behavior

Produce/maintain:

- `README.md` — value proposition, screenshots, install, privacy, basic workflow, CLI examples.
- `ARCHITECTURE.md` — module boundaries, process model, event handling, provider protocol, permissions and data flow.
- `FORMAT_MATRIX.md` — all formats above, directed edges, dependencies, fidelity, status, tests.
- `PARITY_MATRIX.md` — sourced Tangerine/Filee benchmark, including six tools and candidate extras.
- `DESIGN.md` — radial geometry, liquid-glass design tokens, opacity, animations, keyboard/trackpad behavior, accessibility.
- `CLI.md` — command schema, JSON schema, exit codes and agent workflows.
- `SECURITY.md` — local-only policy, metadata/privacy, archive extraction, redaction threat model, subprocess safety.
- `DECISIONS.md` — ADRs, feasibility constraints, unavoidable tradeoffs and explicitly deferred features.
- `TESTING.md` — fixtures, acceptance checklist, measured performance and compatibility matrix.

Agent working rules:

1. Do not omit requirements because they are difficult. Mark them `implemented`, `planned`, `provider-dependent`, `experimental`, or `technically infeasible` with evidence.
2. Never confuse broad input/output format listings with universal pairwise conversion or guaranteed semantic preservation.
3. Favor public macOS APIs and stable user interaction over brittle input hooks.
4. Never ship unsafe redaction or archive extraction.
5. Build and test small vertical slices; keep CLI operational throughout.
6. Explicitly report tradeoffs among tiny idle footprint, extensive conversion coverage and bundled dependencies; prefer optional lazy providers.
7. Preserve the user's finalized interaction contract: Finder select → Shift/Command-mode trigger → persistent cursor-adjacent radial → click/Enter → same-folder output.
8. Keep the UI entirely native, elegant, fast and accessible; avoid Electron or generic webview shells.
9. Do not require network access for actual conversions.
10. Do not claim parity or performance until measured/verified.

## 16. Final product vision

An invisible-until-needed, native, liquid-glass **radial command palette for file conversion and file tools**, not a conventional converter with a decorative radial menu. Keyboard/trackpad users are first-class. Shift enters conversion; Command enters file tools; both configurable and implemented safely. A persistent radial menu appears near the cursor, supports pointer, numbers, arrows and typing, and executes only when clicked or confirmed with Enter. Outputs are written automatically beside originals. Hundreds of format capabilities are provided through an auditable, modular, entirely local conversion core. The same short-named CLI gives agents full headless, discoverable, structured access. User customization is extensive, but performance, privacy, predictability, conversion truthfulness and data safety are never sacrificed.
