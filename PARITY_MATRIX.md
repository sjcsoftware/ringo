# Parity matrix

What Tangerine and Filee claim, where the claim comes from, and what Ringo does about it. Counts from vendors are recorded as claims, not targets: Tangerine counts conversion *options* (source-target pairs offered in its menus) while Filee counts *formats*, so the two numbers measure different things and are not compared.

## Sources

| Id | Source | Accessed |
|---|---|---|
| T1 | Tangerine website, https://tangerineformac.com/ (states "All operations on this page are simulated") | 2026-10-18 |
| T2 | Tangerine on the Mac App Store, https://apps.apple.com/us/app/tangerine-file-converter/id6813034065 (version 2.0.1) | 2026-10-18 |
| T3 | MacGeneration review, https://www.macg.co/logiciels/2026/10/tangerine-un-convertisseur-de-fichiers-toujours-portee-de-main-sur-mac-311381 | 2026-10-18 |
| F1 | Filee website, https://filee.sh | 2026-10-18 |
| F2 | Filee on SourceForge, https://sourceforge.net/projects/filee/ (version 1.10.4) | 2026-10-18 |

No hands-on testing of Tangerine or Filee was done for this matrix; every row cites a vendor page or a review. Rows where sources disagree say so.

## Headline claims

| Claim | Source | Ringo |
|---|---|---|
| Tangerine: 275 conversion options, 26 advanced tools, 6 file actions | T1 | 462 directed edges in the registry, 429 runnable on the development machine (FORMAT_MATRIX.md). Not comparable to Tangerine's count. |
| Tangerine App Store page lists 30 unique formats | T2 | All of them are in Ringo's catalog |
| Filee: 244 formats in 17 categories, 136 working after install | F1 | 72 formats. Filee's SourceForge page says "180+ formats" (F2), so the figure varies by page and version. |

## Interaction

| Feature | Tangerine | Filee | Ringo | Status |
|---|---|---|---|---|
| Radial menu at the pointer | Shift while dragging a file opens a wheel (T1, T2, T3) | No; drag and drop window (F1, F2) | Radial at the pointer from the Finder selection | implemented |
| Tools wheel | ⌘ (T1); Option+Shift drag (T2, T3); sources differ by version | — | Double-tap ⌘ or ⌃⌘R | implemented |
| File actions wheel (AirDrop, Float, Copy, Move, Copy Path, Terminal) | Control (T1, T2 v2.0) | — | Not in scope of the brief | planned |
| Keyboard: arrows choose, Enter applies, Escape cancels | T1, T3 | — | Plus 1–8, Tab, in-ring search, submenus | implemented |
| Keyboard invocation without dragging | "Press Enter on a file to open the format menu" (T1, demo) | — | Double-tap or hotkey on the Finder selection | implemented |
| Drag a file and drop on a wedge | T1, T2 | Drag onto window (F1) | Experimental drag + modifier | experimental |
| Touch / hold before drag | T1 | — | Drag-and-hold | planned |
| Batch | Several compatible files at once (T2) | Parallel, failures isolated (F1) | Bounded concurrency, per-file results | implemented |
| Watched folders | — | Yes, app and CLI, move originals aside (F1) | `ringo watch --move-originals` | implemented (CLI); app: planned |
| CLI with JSON and exit codes | — | `filee` command, JSON, exit codes (F1) | `ringo`, schema ringo/1, fixed exit codes | implemented |
| Offline / no upload | T1, T2, T3 | F1, F2 | Network-denied test | implemented |
| Customizable shortcuts and quality | T3 | Presets (F1) | Settings for triggers, quality, presets, pinned wedges | implemented |

## Tangerine's six tool families (as named in the brief)

The brief names Compress, Edit Metadata, Edit, Annotate, Crop and Redact. Tangerine's pages list these tools (T2, T3); exact presets and UI were not published, so Ringo's presets are its own.

| Tool | Tangerine evidence | Ringo | Status |
|---|---|---|---|
| Compress | Images, video, audio, PDFs; "or target an exact file size" (T2) | Presets lossless→tiny for images, PDF, audio, video; target size for images; ZIP for other files; refuses results that grow | implemented |
| Edit Metadata | "Read and edit metadata, or remove it completely" (T2); remove metadata (T3) | Show (sensitive fields flagged), remove all, remove location, edit fields for images, PDF, media; OOXML properties | implemented |
| Edit | Trim, crop, speed, split, join, snapshots for video; normalize, trim, bleep, channels for audio; merge, split, reorganize PDFs (T2, T3) | Rotate, flip, resize; trim; extract audio; remove audio; PDF rotate, delete, extract, reorder, reverse, split; merge PDFs and images | implemented; speed, join, snapshots, normalize, bleep, channels: planned |
| Annotate | "Crop, adjust, annotate, and redact photos" (T2); annotate image (T3) | Pen, highlighter, rectangle, ellipse, arrow, line, text on images and PDFs; editable PDF annotations or flattened | implemented; "adjust" (color/exposure): planned |
| Crop | Photos, video (T2, T3) | Images, PDF pages (crop box), video; aspect presets; visual editor with keyboard nudging | implemented |
| Redact | Photos (T2); PDF redaction on a product listing | PDFs and images, by area, text or pattern; flattened and verified | implemented |

## Other Tangerine tools

| Tool | Source | Status |
|---|---|---|
| Read QR codes | T2, T3 | planned (Vision can detect barcodes) |
| Build PDFs from images | T2 | implemented (`edit merge`, image → PDF) |
| Collages from images | T2 | planned |
| Video speed change | T2, T3 | planned |
| Extract audio from video | T3 | implemented |

## Formats

Tangerine format lists (T1, T2) are fully covered by the brief's catalog, which Ringo implements; see FORMAT_MATRIX.md. Differences between sources: T3 lists SVG among image *outputs*; T1 says SVG is input only. Ringo follows the brief: SVG is input only.

Filee categories (F1):

| Category | Filee claim | Ringo | Status |
|---|---|---|---|
| Images (36, incl. PSD, RAW) | F1 | 9 formats plus PSD input; camera RAW not cataloged | implemented; RAW: planned (ImageIO decodes many RAW formats) |
| Vector graphics (12: SVG, EMF, WMF, AI, EPS) | F1 | SVG input | SVG implemented; others planned |
| PDF | F1 | Full PDF set from the brief | implemented |
| Documents (23: DOCX, DOC, ODT …) | F1 | DOCX, DOC (input), ODT, RTF, RTFD, Pages, MD, TXT, EPUB, HTML, clippings | implemented |
| HWP / HWPX without Hancom Office | F1, F2 | Native text extraction from HWPX and HWP 5 to TXT, MD, HTML, DOCX, PDF, EPUB; LibreOffice for layout | HWPX implemented; HWP experimental |
| Spreadsheets (13), presentations (11) | F1 | XLSX, ODS, CSV, TSV, XLS; PPTX, PPT, Keynote | implemented / provider-dependent |
| Text & markup (14), data (6) | F1 | Markdown, TXT, HTML | partly; JSON/XML/YAML: planned |
| E-books & comics (24) | F1 | EPUB native; others through Calibre for EPUB routes | EPUB implemented; MOBI/AZW/CBZ: planned |
| Video (22), audio (30), subtitles (9) | F1 | 6 video, 8 audio, 2 subtitle formats | implemented / provider-dependent |
| Archives (28, incl. 7Z, RAR) | F1 | ZIP, TAR, TAR.GZ, GZIP, RAR input | implemented; 7Z input: planned (libarchive reads it) |
| CAD (DWG, DXF) | F1 | DWG → DXF (LibreDWG), DXF → PDF (LibreOffice), DWG → PDF chain | experimental, provider-dependent |
| 3D (6: GLB, STL, OBJ …) | F1 | OBJ, STL, PLY, USD/USDA/USDC/USDZ, ABC native; GLB, glTF, FBX, DAE via Assimp | experimental |
| Fonts (5: TTF, OTF, WOFF, WOFF2) | F1 | TTF/OTF ↔ WOFF native; WOFF2 via woff2 tools | implemented / provider-dependent |
| Office files without Microsoft Office or LibreOffice | F1 | DOCX, XLSX, ODS, CSV native; DOC/XLS/PPT and PPTX rendering need LibreOffice or Apple apps | partly |
| Merge output into one PDF or ZIP | F1 | `edit merge`, `archive` | implemented |
