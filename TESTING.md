# Testing

## Running

```bash
scripts/test.sh              # Swift Testing suite (Command Line Tools are enough)
scripts/offline-test.sh      # CLI conversions inside a sandbox that denies the network
scripts/build-app.sh         # release build; signs and verifies the bundle
```

`scripts/test.sh` builds the tests, retrying once on a Command Line Tools quirk ("plugin for module 'TestingMacros' not found" after a plain product build), then runs them without rebuilding. Media tests that need FFmpeg are skipped when it is not installed; CLI tests need the `ringo` binary that the test build produces.

## Suites

120 tests in 20 suites, about 3 seconds on an M2. Fixtures are generated at run time (images with alpha, EXIF and GPS; text-layer PDFs; WAV; ZIPs including malicious ones; spreadsheets; subtitles; HWPX), so the repository holds no binary fixtures.

| Suite | Covers |
|---|---|
| Format catalog and capability registry | Every §8 format exists; input-only formats are never targets; no identity edges; required directed edges exist; ranking and fallbacks; page selections |
| Content sniffing | Content beats extension; mislabeled files; ZIP container classification; empty and junk files |
| Atomic output commit and naming | Collision names; tool labels; source never replaced; explicit outputs; shared labels for multi-page output; 16 concurrent commits to one name; empty and wrong-format outputs rejected |
| Settings store | Defaults; v1 → v2 migration; unknown keys; newer schema refused; wrong types fall back; export/import; opacity clamp |
| Subprocess safety | No shell interpretation; timeout; cancellation; minimal environment |
| Image conversions | PNG → every native target; WebP with or without a provider; alpha kept or flattened with a warning; EXIF orientation baked for BMP; metadata stripping; SVG input only; animated GIF; mislabeled input; corrupt and empty files leave nothing behind; Unicode, spaces and shell metacharacters in names |
| PDF conversions | PNG and JPEG export of **all pages at 300 DPI** (2550 × 3300 px for Letter); DPI and page selection; text and Markdown extraction; DOCX/EPUB/PPTX/XLSX containers valid; scanned PDF warning and OCR |
| Documents | Markdown ↔ DOCX round trip; semantic HTML; PDF and EPUB from Markdown; RTF, RTFD, text clipping inputs; legacy encodings; HWPX text; HWP control-code decoding |
| Spreadsheets and subtitles | CSV → XLSX → ODS → CSV round trip with quoting and newlines; sheet selection; XLSX dates and formulas; PDF export; SRT ↔ VTT with BOM, CRLF, tags and entities |
| Fonts, 3D and archives | TTF ↔ WOFF; OBJ → STL; gzip round trip with stored name; ZIP → TAR.GZ → folder |
| Media | WAV → M4A/AIFF natively; WAV → MP3/FLAC/OGG/Opus/WMA (FFmpeg); MP3 from a silent video fails with `no_audio_track`; MKV remux; GIF; a missing provider gives `provider_missing` (exit 4) with the install command |
| Batch semantics | Multi-folder batch writes beside each source with per-file results and not-applicable entries; dry run writes nothing; iCloud placeholders refused |
| File tools | All six tool families available for JPEG and PDF; metadata strip keeps orientation and removes GPS and personal tags (checked in raw bytes); location-only strip; metadata edit; lossless JPEG rotation; orientation algebra; pixel rotate, flip, resize, crop; compression sizes, target size, growth refused; ZIP fallback; PDF page operations; PDF metadata strip; annotation (editable and flattened); PDF crop box; OOXML properties; trim and extract audio |
| Security: redaction | PDF: no text layer, no leaked strings or `/Font`/`/Metadata` in bytes, OCR finds none of the redacted terms while unredacted text stays readable; region redaction; no-match writes nothing; image redaction with OCR re-check |
| Security: archives | Zip-slip and absolute paths rejected (exit 8, nothing written); escaping symlinks removed; name validation; decompression bombs stopped (gzip and tar.gz) |
| Modifier double-tap recognizer | Double Shift and double Command fire; Shift-click, typing capitals, ⌘C/⌘V, chords, long holds and slow taps do not; triple tap fires once |
| Radial geometry | Angles, hub, wedge hits, forgiving margin |
| Radial keyboard model | 1–8 and Enter; arrows and Tab; Escape hierarchy (search → submenu → close); search across levels; paging; disabled items explain instead of running; scroll rotation |
| Radial menu builder | PNG targets in pinned order without SVG; seven tool families; mixed selections split by category; pinned wedges stay put with smart suggestions; the hub never shows file names |
| CLI contract | Real binary: versioned JSON envelope; exit codes 1, 2, 3, 5; globs and Unicode; discovery commands; NDJSON events; batch manifests; settings get/set validation; completion scripts |

## Acceptance checklist (PROMPT.md §13)

| # | Criterion | Evidence | Result |
|---|---|---|---|
| 1 | Finder single selection → shortcut → radial → keyboard → Enter → sibling output | Engine path automated (image and PDF suites); radial model tests for keys; radial rendered and driven by `RINGO_DEBUG_PRESENT` / `RINGO_DEBUG_KEYS` | Engine and UI verified separately. The live Finder path needs the Automation consent prompt, which only a person can approve: **manual run pending** |
| 2 | Multi-selection → outputs in each source folder, per-file results | `multiDirectoryBatchWritesBesideEachSource` | pass |
| 3 | Tools shortcut → six tools available contextually → sibling output | `sixToolsAreContextuallyAvailable`, `toolsMenuHasSevenFamilies`, tool suites | pass (engine and menu); live trigger manual |
| 4 | Menu persists until action, outside click or Escape | `persistenceAndEscapeHierarchy`; outside-click monitor is passive (code review) | model pass; outside click manual |
| 5 | Trackpad-only and keyboard-only paths | Geometry and keyboard model suites; scroll rotation | pass (logic); hands-on manual |
| 6 | Opacity slider updates preview and menu, text readable | Settings preview uses the same `RadialView`; label plates below 60 % | implemented; visual check manual |
| 7 | GUI and CLI share registry and results | Both call `RingoEngine.makeService()`; menu builder tests use the registry | pass (by construction) |
| 8 | CLI runs with GUI closed, valid versioned JSON | CLI contract suite runs the binary with no app | pass |
| 9 | Offline operation | `scripts/offline-test.sh` (13 operations, network blocked, curl check) | pass |
| 10 | PDF → JPG/PNG all pages at 300 DPI | `allPagesAt300DPI` | pass |
| 11 | Input-only formats never offered as outputs | `inputOnlyFormatsAreNeverTargets`, `svgIsRasterizedButNeverATarget`, CLI exit 3 test | pass |
| 12 | Redacted content not trivially recoverable | Redaction suite (extraction, raw bytes, OCR) | pass |
| 13 | Missing providers → precise, actionable errors | `missingProviderIsReportedPrecisely`, `wavToNativeTargets` | pass |
| 14 | Shortcuts don't interfere with Shift selection, ⌘ shortcuts, typing | Recognizer suite | pass (logic); hands-on manual |
| 15 | No Electron, no heavy daemon, measured footprint | Native Swift only; measurements below | pass |

### Manual checklist for a release

Run on a Mac where you can grant permissions:

1. Launch `build/Ringo.app`, complete onboarding, allow Finder automation and Accessibility.
2. In Finder select one PNG, double-tap ⇧, press `2`, Return. Expect `<name>.avif` beside it and the progress panel.
3. Select files in two folders, double-tap ⇧, type `jpeg`, Return. Expect one JPEG in each folder.
4. Double-tap ⌘ on a PDF: Compress → Balanced; Redact → Find Text…; Crop → Custom… with arrow keys.
5. With the radial open, click another app's window: the radial closes and the click lands in that window.
6. Shift-click several files in Finder, press ⌘C and type capitals in a text field: the radial must not open.
7. Move the opacity slider in Settings → Radial Menu and open the radial over a busy window.
8. Repeat 2 with only the trackpad (two-finger scroll to choose, tap to run) and only the keyboard.
9. Turn on VoiceOver and confirm wedges and results are announced.

## Measurements

Development machine: MacBook Air (Mac14,2), Apple M2, 16 GB, macOS 27.0.1; release build.

| Metric | Value | How |
|---|---|---|
| Idle memory | 14 MB physical footprint | `footprint <pid>` 8 s after launch |
| Idle CPU | 0.00 s over 30 s | `ps -o time` before and after |
| Threads at idle | 3 | `ps -M` |
| Memory with radial open | 24 MB | `footprint`, radial showing two files |
| CPU with radial open, untouched | 0.01 s over 20 s | `ps -o time` |
| Radial hot path, warm | 24–44 ms from trigger to a committed frame with the menu populated (1–4 files) | `RINGO_DEBUG_TIMING`, three runs each |
| Radial, first use after launch | 110 ms with cached probes, 150–210 ms on a first-ever run | same; the app warms the capability table 2 s after launch |
| CLI start | 20 ms, 12 MB max RSS (`ringo version`) | `/usr/bin/time -l` |

Not measured: battery impact over hours, Intel Macs, macOS 14 and 15 (the deployment target is macOS 14; Liquid Glass falls back to frosted material before macOS 26).

## Compatibility

| | Status |
|---|---|
| macOS 27 (Apple silicon) | Built and tested |
| macOS 26 | Expected to work (same APIs); not tested |
| macOS 14–15 | Deployment target; frosted glass instead of Liquid Glass; not tested |
| Intel Macs | Builds for the host architecture only; universal build: planned |

## Homebrew cask (template for a release)

```ruby
cask "ringo" do
  version "1.0.0"
  sha256 "<sha256 of the release zip>"
  url "https://<release host>/Ringo-#{version}.zip"
  name "Ringo"
  desc "Radial-menu file conversion for Finder, with a matching CLI"
  depends_on macos: ">= :sonoma"
  app "Ringo.app"
  binary "#{appdir}/Ringo.app/Contents/Helpers/ringo"
end
```
