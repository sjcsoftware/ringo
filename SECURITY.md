# Security and privacy

## Local-only policy

- No conversion, tool, discovery or settings operation opens a network connection. There is no telemetry, crash upload, analytics, account, license check or update check.
- Pandoc always runs with `--sandbox`, so a document cannot make it fetch a remote image or read other local files.
- FFmpeg inputs and outputs are passed as `file:` URLs; no other protocol is used.
- ImageMagick paths carry an explicit coder prefix (`PNG:/path`), so a file name can never be interpreted as a URL or a special coder.
- LibreOffice runs with a throwaway profile inside the job directory.
- `scripts/offline-test.sh` runs conversions and tools inside a sandbox profile that denies all network access and checks that the sandbox really blocks `curl`.
- Ringo does not download optional tools. Settings → Providers shows install commands for the user to run.
- iCloud placeholders are refused. Ringo does not trigger downloads, and does not present a file as processed offline when its content is not on the Mac.

## Permissions

| Permission | Scope | Notes |
|---|---|---|
| Automation → Finder | One script: `get selection` | Usage string in Info.plist says so. Required. |
| Accessibility | Observe modifier/key timing for double-tap triggers | Optional. Ringo never logs, stores or reads typed characters; key events only reset the tap detector. |
| Automation → Pages / Keynote | Open, export, close | Only for conversions that need those apps. |

Ringo does not use an event tap, does not consume or modify events, and does not request Screen Recording, Full Disk Access or Input Monitoring.

## Subprocesses

- Executables are run with `Process` and an argument array. No shell, no string interpolation of file names.
- Input paths are absolute, so they never begin with `-`. Tools that accept `--` get it before positional paths.
- The environment is rebuilt from scratch: `HOME`, `USER`, `TMPDIR`, locale and a fixed `PATH`. Proxy variables and `DYLD_*` injection do not pass through.
- Every conversion and tool subprocess has a timeout (default 30 minutes, `--timeout`) and is terminated on cancellation, then killed after 3 seconds. Version and encoder probes run once and are cached.
- Captured output is capped (8 MB per stream).
- AppleScript for Pages and Keynote receives paths as `argv`; the script text is constant.

## Output safety

- Originals are never modified unless `--in-place` is given on the command line. The app has no in-place mode.
- Outputs are written in a private directory on the destination volume, checked (exists, non-empty, content signature matches the target format), `fsync`ed, and moved with `renamex_np(RENAME_EXCL)`. An existing file is never replaced unless `--overwrite` is given, and the source is never replaced even then.
- Failed or cancelled jobs leave nothing behind.

## Archive extraction

Threats: path traversal (zip-slip), absolute paths, symlink escapes, special files, decompression bombs, overwriting existing files.

1. Entry names are listed first. Any absolute path, `~` path, `..` component or control character rejects the whole archive (`unsafe_archive`, exit 8). More than 200,000 entries is rejected.
2. Extraction uses macOS's libarchive (`/usr/bin/bsdtar`) without `-P`, which also refuses to follow symlinks while writing, into a fresh private directory, with `--no-same-owner`.
3. A watchdog measures the extracted size while bsdtar runs and stops it past the limit: the smaller of 20 GB and free space minus 1 GB. The size is checked again when extraction ends.
4. Afterwards, symlinks that point outside the folder (or anywhere absolute) and special files (devices, FIFOs) are removed, with a warning.
5. The result moves next to the archive as a new folder with a collision-safe name. It is never merged into an existing folder.
6. Gzip decompression streams with the same byte limit.
7. Encrypted archives are refused with a clear message; Ringo never asks for passwords.

Tests create traversal, absolute-path, escaping-symlink and bomb archives and check each defense.

## Redaction threat model

Goal: text and images under a redaction box cannot be recovered from the output by copy/paste, text extraction, reading the PDF objects, removing annotations, or OCR.

A black rectangle drawn on top of a PDF is not enough: the text underneath stays in the content stream. Ringo therefore:

1. Finds targets: user regions, exact terms and patterns (email, phone, card number, SSN, URL, IPv4) through PDFKit's text layer; scanned pages are searched with on-device Vision OCR.
2. Renders every page to a bitmap (200 DPI by default, adjustable) and paints opaque boxes, padded by 1.5 pt, into the pixels.
3. Builds a new PDF containing only those page images. No text, fonts, annotations, links, form fields, attachments, JavaScript, XMP or document info from the original survive.
4. Verifies before saving: no extractable text on any page; no `/Font`, `/Annots`, `/AcroForm`, `/EmbeddedFile`, `/JavaScript` or `/Metadata` in the file; when terms or patterns were used, an OCR re-scan of the output finds none of them. Any failure aborts with `verification_failed` and writes nothing.
5. Images: boxes are burned into the pixels; the output is a new file with no EXIF, GPS, XMP or embedded thumbnail; text targets are found and re-checked with OCR.

Limits, stated in the UI and CLI:

- The output is an image-only PDF: text is no longer selectable or searchable.
- Text matching depends on the PDF's text layer or on OCR quality. Text that OCR cannot read (stylized, tiny, rotated) may be missed by the term search; the region tool covers those cases.
- If nothing matches, nothing is written and the result says so, rather than producing a "redacted" copy that changed nothing.
- PDF crop is not redaction: it hides content but leaves it in the file, and the crop panel says so.

## Metadata

`metadata strip` removes EXIF, GPS, IPTC, XMP and TIFF descriptive tags from images while copying the encoded image data unchanged (no recompression), keeping only the orientation tag so the photo still displays upright. For PDFs it rebuilds pages without the document info dictionary, XMP, annotations, links and forms. For audio and video it drops container and stream tags and chapters. For DOCX/XLSX/PPTX it blanks core, app and custom properties; tracked changes and comments in the body are not touched, and the result says so.

## Licenses of optional tools

Ringo bundles none of them. FFmpeg builds may be LGPL or GPL and may include patent-encumbered codecs; Pandoc, Calibre, LibreDWG and GPL builds of FFmpeg are GPL; LibreOffice is MPL; ImageMagick uses its own Apache-style license. Because they are separate programs the user installs and Ringo runs as subprocesses, their licenses do not apply to Ringo's code. A future distribution that bundles any of them must ship their license texts and, for GPL tools, corresponding source.

## Reporting

Ringo has no network presence. Report vulnerabilities to the repository owner privately.
