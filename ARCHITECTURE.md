# Architecture

Ringo is one Swift package with two frontends, the menu bar app and the `ringo` CLI, over one engine. Both frontends build the same `RingoService` through `RingoEngine.makeService()`, so a conversion offered in the radial menu is exactly a conversion the CLI can run, with the same provider, naming and result.

```text
Finder selection ── FinderBridge ──┐        double-tap / hotkey ── Shortcuts
                                   ▼                                  │
                         RadialController (NSPanel + SwiftUI) ◀───────┘
                                   │ RadialAction
                                   ▼
ringo CLI ──────────────▶ RingoService  (validation, planning, jobs, output commit)
                                   │
                         CapabilityRegistry  (directed edges × providers, availability)
                                   │
          ┌────────────────────────┼─────────────────────────┐
          ▼                        ▼                         ▼
   Native providers         System providers          Optional providers
   ImageIO, PDFKit,         libarchive (bsdtar)       FFmpeg, ImageMagick, Pandoc,
   Cocoa text, AVFoundation,                          LibreOffice, Pages/Keynote,
   Model I/O, Vision, …                               Calibre, librsvg, …
                                   │
                    temp file on the same volume → fsync → renamex_np(RENAME_EXCL)
```

## Modules

| Module | Responsibility | Imports AppKit? |
|---|---|---|
| `RingoDomain` | Format catalog, fidelity and status vocabulary, tool operations, typed errors, JSON result schema | No |
| `RingoSettings` | Versioned settings shared by app and CLI, migrations, defaults merge | No |
| `RingoCore` | Provider protocol, capability registry, content sniffing, input resolution, subprocess runner, output commit, application service, ZIP/gzip, PDF rasterizer, chain provider | No |
| `RingoNative` | Apple-framework providers: images, PDF, documents, spreadsheets, subtitles, media, 3D, fonts, Hangul | Yes (text system and PDFKit; no app lifecycle) |
| `RingoExternal` | Optional tools, discovered lazily; libarchive provider and safe extraction | No |
| `RingoTools` | The file tools: compress, metadata, edit, annotate, crop, redact, archive | Yes (PDFKit annotations) |
| `RingoEngine` | Composition root: registers providers, chains and tools | Re-exports |
| `RingoCLI` → `ringo` | ArgumentParser commands, JSON envelope, exit codes, batch, watch | No |
| `RingoFinderBridge` | Reads the Finder selection with one scoped Apple Event | Yes |
| `RingoShortcuts` | Double-tap recognizer (pure logic), event monitors, Carbon hotkeys | Yes |
| `RingoRadialUI` | Radial model, geometry, SwiftUI view, panel controller, inspectors, job center, progress HUD | Yes |
| `RingoApp` → `Ringo.app` | App delegate, menu bar item, settings window, onboarding | Yes |

The rule from the brief, "the core must not import AppKit", holds for Domain, Settings and Core. The native providers link AppKit for two framework APIs that live there on macOS (`NSAttributedString` document readers and writers, `PDFKit` annotations), never for `NSApplication`, which is why the CLI runs them headless.

## Process model

- **Ringo.app** is an `LSUIElement` agent: no Dock icon and no main window. It holds no conversion engine state between jobs. At idle it uses about 14 MB and no CPU (see [TESTING.md](TESTING.md)).
- **ringo** is a separate, short-lived process. It reads the same settings file, builds the same registry and exits. It never talks to the app.
- **External tools** run as child processes only during a job, with an argv array (no shell), a minimal environment and a timeout. Nothing runs between jobs.
- There is no daemon, helper tool, XPC service or privileged component.

## Event handling (app)

1. `ShortcutService` watches `flagsChanged`, `keyDown` and mouse-down events with passive NSEvent monitors and feeds them to `ModifierTapRecognizer`. Monitors observe only; they never consume or alter events. Carbon `RegisterEventHotKey` handles the fallback chords.
2. On a trigger, `AppDelegate.invoke` shows the radial at the pointer immediately, in a loading state, then reads the Finder selection on the next run-loop turn so Apple Events never delay the menu.
3. Inputs are resolved and sniffed off the main thread; `RadialMenuBuilder` turns them plus the registry into wedges.
4. The radial panel is a borderless, non-activating `NSPanel` that becomes key without activating Ringo, so Finder stays frontmost while the panel receives keystrokes. `RadialPanel.sendEvent` routes keys, clicks, hover and scroll into `RadialModel`.
5. A click outside is seen by a passive global monitor that dismisses the panel. The click still reaches the app under the pointer.
6. A chosen action goes to `JobCenter`, which runs it on a detached task. Progress events update the HUD; results arrive per file.

## Provider protocol

```swift
protocol ConversionProvider {
    var id: ProviderID { get }
    var edges: [EdgeSpec] { get }                       // directed edges with fidelity, status, limitations
    func status() -> ProviderStatus                     // installed? version, path, license, install hint
    func availability(of: EdgeSpec) -> (Bool, String?)  // can this edge run now? why not?
    func convert(_: ConversionRequest, context: JobContext) async throws -> ProviderOutcome
    var isOptional: Bool { get }                        // user-installed tool → "provider-dependent"
}
```

- **Discovery is lazy.** Constructing a provider does nothing. `availability` checks for a binary with a `stat`; FFmpeg's encoder list is probed once and cached on disk by the binary's path, size and modification date.
- **Ranking.** For each edge the registry picks the first available provider in priority order. Users can reorder providers in settings. Edges marked `fallback` (for example the native Markdown reader when Pandoc is installed) rank after non-fallback edges unless the user ranks that provider first.
- **Chains.** `ChainProvider` runs explicit two-step routes such as PPTX → PDF → PNG. Chains are declared in `RingoEngine.chains`, never discovered, so the matrix stays auditable.
- **Outcomes.** A provider writes into a private work directory and returns `ProducedFile`s with a format and an optional name suffix (`-p01`, `-Sheet2`). It never chooses the final path.

## Output commit

`OutputCommitter` owns every write to the user's folders:

1. The work directory comes from `FileManager.url(for: .itemReplacementDirectory, appropriateFor: destination)`, which is on the destination's volume.
2. Each produced file is checked: it exists, is not empty, and its content signature matches the target format. A provider that claims success with a wrong or empty file fails the job (`verification_failed`).
3. The file is `fsync`ed and moved with `renamex_np(..., RENAME_EXCL)`. If another process took the name in the meantime the rename fails and the next free name is tried, so nothing is overwritten by a race.
4. Names: `<stem>.<ext>`; on collision `<stem> (converted).<ext>`, `<stem> (converted 2).<ext>`. Tools always label: `<stem> (compressed).<ext>`. Multi-file outputs share one free label. The source path is never a target, even with `--overwrite`.
5. The work directory is removed whether the job succeeds, fails or is cancelled.

## Data flow for one conversion

```text
path → InputFile.resolve (alias/symlink resolution, iCloud placeholder check, content sniffing)
     → RingoService.plan (registry.best: provider, fidelity, limitations, planned path)
     → provider.convert (work dir, timeout, progress callback, cancellation)
     → OutputCommitter.commit (validate, fsync, exclusive rename)
     → FileResult (status, outputs, provider, fidelity, bytes, warnings, limitations, error)
```

Batches use bounded concurrency (default 2, `--jobs`) and keep results in input order. Files that cannot take the requested action are reported as `not-applicable`, never dropped.

## Permissions

| Permission | Who | Why | When asked |
|---|---|---|---|
| Automation → Finder | App | Read the selection | First invocation; can be tested from onboarding |
| Accessibility | App | See other apps' modifier keys for double-tap triggers | Only when the user clicks "Allow…" |
| Automation → Pages/Keynote | App or CLI | Export through those apps | Only for conversions that need them |

The app is not sandboxed and uses the hardened runtime with the Apple Events entitlement. [DECISIONS.md](DECISIONS.md) (ADR-006) explains why.

## Settings

`~/Library/Application Support/Ringo/settings.json` (override with `RINGO_SETTINGS`). It is versioned (`schemaVersion`), migrated step by step, merged over defaults key by key so unknown or mistyped keys fall back instead of failing, and refused when written by a newer schema. CLI flags override settings for one run without changing the file.
