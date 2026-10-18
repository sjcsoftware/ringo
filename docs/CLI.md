# ringo command reference

`ringo` is the command-line face of Ringo. It shares the conversion engine, capability registry and settings with Ringo.app and runs without the app. All operations are local; no command uses the network.

## Commands

| Command | Purpose |
|---|---|
| `ringo convert <files…> --to <format>` | Convert. Outputs go beside each source. |
| `ringo <files…> <format>` | Shorthand for `convert`. |
| `ringo plan <files…> --to <format>` | Provider, fidelity, limitations and output path, without converting. |
| `ringo formats` | Catalog: id, extensions, role (both, input-only, export-only), readable/writable. |
| `ringo capabilities [--from f] [--to f] [--all] [--available]` | Directed edges. Default: best provider per edge; `--all`: every provider. |
| `ringo inspect <file>` | Detected type (by content), targets, applicable tools. |
| `ringo tools` | Tool actions with parameters and CLI usage. |
| `ringo compress <files…> [--preset p] [--target-size 500KB]` | Presets: lossless, high, balanced, small, tiny. |
| `ringo metadata show <file>` | Fields grouped by source; sensitive ones flagged. |
| `ringo metadata strip <files…> [--location-only]` | Copy without metadata. |
| `ringo metadata set <files…> --field name=value …` | Copy with edited fields. |
| `ringo edit rotate\|flip\|resize\|trim\|extract-audio\|mute\|pdf\|merge …` | Lightweight edits. |
| `ringo crop <files…> --rect x,y,w,h \| --aspect 16:9 [--normalized] [--pages p]` | Images, PDF pages, video. |
| `ringo annotate <file> --spec marks.json [--flatten]` | Markup from a JSON spec. |
| `ringo redact <files…> [--text t]… [--pattern p]… [--regions r.json]` | Irreversible, verified redaction. |
| `ringo archive <files…> --format zip\|tar\|tgz\|gzip` | Pack. |
| `ringo extract <archives…>` | Safe extraction into a sibling folder. |
| `ringo watch <folder> --to <format> [--move-originals] [--once]` | Convert files as they arrive. |
| `ringo batch --manifest jobs.json` | Several commands, one combined report. |
| `ringo providers [list\|doctor]` | Installed tools and what missing ones would unlock. |
| `ringo settings show\|path\|get\|set\|reset\|export\|import` | Shared settings. |
| `ringo version` | Version and schema. |

`ringo <command> --help` documents every flag. `ringo --generate-completion-script zsh|bash|fish` prints completions.

### Common flags

| Flag | Meaning |
|---|---|
| `-o, --output <path>` | Exact output path (single input). Refuses to replace an existing file without `--overwrite`. |
| `--output-dir <dir>` | Write here instead of next to each source. |
| `--overwrite` | Replace an existing file at the chosen output name. Never replaces the source. |
| `--in-place` | Tools only: replace the source atomically. Not reversible. |
| `--dry-run` | Report planned outputs; write nothing. |
| `--jobs <n>` | Files processed at once (default 2). |
| `--json` | One JSON document on stdout. |
| `--events` | NDJSON progress on stderr. |
| `--no-network` | Accepted for scripts. Ringo never uses the network, so it changes nothing. |

Conversion flags: `--quality 1-100`, `--preset`, `--dpi` (default 300), `--pages 1-3,7`, `--sheet name|n|all`, `--page-size fit|a4|letter`, `--keep-timestamps`, `--fps`, `--max-width`, `--max-duration`, `--audio-bitrate`, `--provider <id>`, `--timeout <s>`, `--strip-metadata`, `--ocr` / `--no-ocr`.

### Inputs

- Several files, folders, `~` paths, Unicode and spaces all work. Quote a glob (`'*.png'`) to let Ringo expand it; unquoted globs are expanded by your shell as usual.
- Symlinks and Finder aliases are resolved; the output goes next to the resolved file.
- The type is detected from content. A PNG named `.jpg` is treated as PNG and reported with a warning.
- iCloud files that are not downloaded are refused with `cloud_placeholder`. Ringo does not download them.

## JSON output

Every command prints one envelope with `--json`:

```json
{
  "schema": "ringo/1",
  "schemaVersion": 1,
  "ringoVersion": "1.1.0",
  "command": "convert",
  "ok": true,
  "exitCode": 0,
  "summary": { "total": 1, "succeeded": 1, "failed": 0, "noChange": 0, "notApplicable": 0, "planned": 0 },
  "results": [
    {
      "input": "photo.png",
      "status": "succeeded",
      "operation": "convert",
      "target": "webp",
      "outputs": [ { "path": "/Users/me/Pictures/photo.webp", "url": "file:///Users/me/Pictures/photo.webp", "format": "webp", "bytes": 3121 } ],
      "provider": "imagemagick",
      "fidelity": "lossy",
      "lossy": true,
      "bytesIn": 4532,
      "bytesOut": 3121,
      "durationMs": 97,
      "warnings": [],
      "limitations": ["Encoded by libwebp through ImageMagick; quality 85 by default (--quality)."],
      "details": {}
    }
  ]
}
```

- `status`: `succeeded`, `failed`, `planned` (dry run), `no-change` (for example compression that would make the file bigger; nothing is written), `not-applicable` (the file cannot take this action).
- `fidelity`: `lossless`, `remux`, `lossy`, `rasterized`, `text-only`, `approximate`, `heuristic`, `image-only`, `packaging`.
- `warnings` are about this file (flattened transparency, extra sheets ignored). `limitations` are known limits of the route.
- `error`: `{ "code": "provider_missing", "message": "FFmpeg is required but not installed. Install it with `brew install ffmpeg`.", "exitCode": 4 }`.
- Discovery commands put their payload in `data` (an array of capabilities, formats, tools, plans, or a report object).
- Errors that happen before any file is processed (bad arguments) produce an envelope with `ok: false` and an `error` object.

Any change that breaks a consumer bumps `schemaVersion`.

### Progress events

With `--events`, one JSON object per line on stderr:

```json
{"schema":"ringo/1","event":"batch-start","message":"convert to png","total":3}
{"schema":"ringo/1","event":"start","input":"a.pdf","index":0,"total":3}
{"schema":"ringo/1","event":"progress","input":"a.pdf","fraction":0.5,"index":0,"total":3}
{"schema":"ringo/1","event":"finish","input":"a.pdf","message":"succeeded","index":0,"total":3}
{"schema":"ringo/1","event":"batch-finish","total":3}
```

stdout carries only results; stderr carries events, warnings and errors.

## Exit codes

| Code | Meaning | Error codes |
|---|---|---|
| 0 | Everything succeeded (or was planned, or needed no change) | |
| 1 | Some files failed, others succeeded | |
| 2 | Invalid arguments, unknown format | `invalid_argument`, `unknown_format` |
| 3 | Conversion or tool not supported for this input | `unsupported_conversion`, `unsupported_tool` |
| 4 | A required optional tool is not installed | `provider_missing` |
| 5 | Input problem | `input_not_found`, `input_unreadable`, `format_mismatch`, `cloud_placeholder`, `no_audio_track`, `permission_denied` |
| 6 | Output problem | `output_exists`, `output_write_failed`, `insufficient_space` |
| 7 | Cancelled or timed out | `cancelled`, `timed_out` |
| 8 | Safety check failed | `verification_failed`, `unsafe_archive` |
| 9 | An external tool failed | `provider_failed` |
| 10 | Bug in Ringo | `internal_error` |

When every file fails with the same code, the process exits with that code; mixed failures exit 1.

## Specs for annotate and redact

Coordinates are fractions of the image or page (0 to 1) measured from the top-left corner. PDF items take a zero-based `page`.

```json
{ "items": [
    { "kind": "arrow", "points": [{"x": 0.1, "y": 0.1}, {"x": 0.45, "y": 0.4}], "color": "#FF3B30", "lineWidth": 4 },
    { "kind": "rectangle", "rect": {"x": 0.5, "y": 0.5, "width": 0.3, "height": 0.2} },
    { "kind": "text", "points": [{"x": 0.1, "y": 0.8}], "text": "Check this", "fontSize": 32 },
    { "kind": "highlight", "points": [{"x": 0.2, "y": 0.3}, {"x": 0.6, "y": 0.3}] }
  ],
  "flatten": false }
```

Kinds: `pen`, `highlight`, `rectangle`, `ellipse`, `arrow`, `line`, `text`. Line width and font size are in points for a 1000-point long edge, so marks keep their proportions at any resolution.

Redaction regions:

```json
[ { "page": 0, "rect": {"x": 0.08, "y": 0.12, "width": 0.4, "height": 0.05}, "unit": "normalized" } ]
```

or a full spec: `{"regions": [...], "terms": ["Jane Doe"], "patterns": ["email", "phone"], "caseSensitive": false, "dpi": 200}`. Patterns: `email`, `phone`, `credit-card`, `ssn`, `url`, `ipv4`.

## Batch manifests

```json
{ "jobs": [
    { "args": ["convert", "a.png", "--to", "webp"] },
    { "args": ["compress", "b.pdf", "--preset", "small"] },
    { "args": ["redact", "c.pdf", "--pattern", "email"] }
  ],
  "stopOnError": false }
```

Each `args` is an ordinary command line without `ringo`. The batch prints one envelope with every file result.

## Agent workflows

Discover what is possible before acting:

```bash
ringo inspect upload.bin --json                 # real type, targets, tools
ringo capabilities --from pdf --available --json
ringo plan report.pdf --to docx --json          # fidelity: "heuristic" → warn your user
```

Convert and read back the produced paths:

```bash
ringo convert report.pdf --to png --dpi 150 --json | jq -r '.results[].outputs[].path'
```

Handle missing tools without guessing:

```bash
out=$(ringo convert talk.wav --to mp3 --json) || code=$?
if [ "${code:-0}" -eq 4 ]; then echo "$out" | jq -r '.results[0].error.message'; fi
```

Rules that keep automation safe: do not parse human output (use `--json`); treat `no-change` as success with nothing written; check `fidelity` and `limitations` before presenting a heuristic result as faithful; never pass `--in-place` unless the user asked to replace originals.
