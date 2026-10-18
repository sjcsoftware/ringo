#!/usr/bin/env python3
"""Generates docs/FORMATS.md from the live capability registry (`ringo capabilities --all --json`).

Run after changing providers:  python3 scripts/gen-format-matrix.py dist/Ringo.app/Contents/Helpers/ringo
The "Here" column reflects the machine that generated the file; the "Tested" column lists edges the
automated suite exercises (keep TESTED in sync with Tests/RingoTests)."""
import json, subprocess, sys, datetime, collections

ringo = sys.argv[1] if len(sys.argv) > 1 else "ringo"
def run(*args):
    return json.loads(subprocess.run([ringo, *args, "--json"], capture_output=True, text=True, check=True).stdout)["data"]

caps = run("capabilities", "--all")
formats = run("formats")
providers = {p["id"]: p for p in run("providers")}
fmt = {f["id"]: f for f in formats}

TESTED = set("""png>jpeg png>heic png>tiff png>avif png>bmp png>gif png>pdf png>webp jpeg>bmp jpeg>heic svg>png gif>png
pdf>png pdf>jpeg pdf>txt pdf>md pdf>docx pdf>epub pdf>pptx pdf>xlsx md>docx md>html md>pdf md>epub docx>md rtf>docx rtfd>txt
textclipping>md hwpx>txt csv>xlsx xlsx>ods ods>csv xlsx>csv xlsx>tsv csv>pdf srt>vtt vtt>srt srt>txt ttf>woff woff>ttf obj>stl
gzip>folder zip>tgz tgz>folder zip>folder tar>folder wav>m4a wav>aiff wav>mp3 wav>flac wav>ogg wav>opus wav>wma mp4>mp3 mp4>mkv
mp4>gif""".split())

by_edge = collections.defaultdict(list)
for c in caps:
    by_edge[(c["from"], c["to"])].append(c)

def best(edge):
    cs = by_edge[edge]
    avail = [c for c in cs if c["available"] and not c.get("fallback")] or [c for c in cs if c["available"]]
    return (avail or cs)[0]

sections = [("8.1", "Images", "image"), ("8.2", "Audio", "audio"), ("8.3", "Video", "video"), ("8.4", "PDF", "pdf"),
            ("8.5", "Documents", "document"), ("8.6", "Slides", "slides"), ("8.7", "Spreadsheets", "spreadsheet"),
            ("8.8", "Subtitles", "subtitle"), ("8.9", "Archives", "archive")]
parity = [("3D models", "model3d"), ("Fonts", "font"), ("Hangul", "hwp"), ("CAD", "cad")]

out = []
w = out.append
total_edges = len(by_edge)
available = sum(1 for e in by_edge if any(c["available"] for c in by_edge[e]))
w("# Format matrix\n")
w(f"Generated {datetime.date.today().isoformat()} from the capability registry (`ringo capabilities --all --json`). "
  "Do not edit by hand; run `python3 scripts/gen-format-matrix.py <path-to-ringo>`.\n")
w(f"**{len(fmt)} formats, {total_edges} directed edges, {len(caps)} provider routes.** "
  f"On the machine that generated this file, {available} edges could run; the rest need an optional provider listed in the row.\n")
w("Reading the table: one row per directed edge (source → target). *Provider* is the route Ringo uses first; *Others* are fallbacks. "
  "*Fidelity* says what survives (see the legend). *Status* indicates support maturity. *Here* is ✓ when the edge could run "
  "on the generating machine. *Tested* is ✓ when the automated suite converts real fixtures along that edge.\n")
w("A format being readable and another being writable does **not** mean every pair converts. Only the rows below exist.\n")
w("## Legend\n")
w("| Fidelity | Meaning |\n|---|---|")
for k, v in [("lossless", "Pixels, samples or text are kept exactly (container may change)."), ("remux", "Streams copied into a new container when compatible; otherwise re-encoded (reported per file)."),
             ("lossy", "Perceptual compression; quality setting applies."), ("rasterized", "Vector or page content drawn into pixels."),
             ("text-only", "Only text survives."), ("approximate", "Text and styling survive; layout is approximated."),
             ("heuristic", "Structure is guessed (paragraphs, headings, table cells); review the result."),
             ("image-only", "Each page/slide becomes a picture; nothing is editable."), ("packaging", "Archive packaging; bytes unchanged.")]:
    w(f"| `{k}` | {v} |")
w("")

def edge_rows(src_ids):
    rows = []
    for (f, t) in sorted(by_edge):
        if f not in src_ids: continue
        b = best((f, t))
        others = sorted({c["providerName"] for c in by_edge[(f, t)]} - {b["providerName"]})
        here = "✓" if any(c["available"] for c in by_edge[(f, t)]) else "✗"
        tested = "✓" if f"{f}>{t}" in TESTED else ""
        lim = "; ".join(b.get("limitations", [])[:2]).replace("|", "\\|")
        need = "" if here == "✓" else (b.get("unavailableReason") or "").replace("|", "\\|")
        rows.append(f"| {f} → **{t}** | {b['providerName']} | {', '.join(others)} | `{b['fidelity']}` | {b['status']} | {here} | {tested} | {need or lim} |")
    return rows

def table(src_ids):
    rows = edge_rows(src_ids)
    if not rows:
        return ["_No conversion edges from these formats._", ""]
    return ["| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |", "|---|---|---|---|---|---|---|---|"] + rows + [""]

for sec, title, cat in sections:
    ids = [f["id"] for f in formats if f["category"] == cat or (sec == "8.3" and f["id"] == "gif")]
    w(f"## {title}\n")
    w("| Format | Extensions | Role | Readable | Writable | Notes |\n|---|---|---|---|---|---|")
    for i in ids:
        f = fmt[i]
        w(f"| {f['name']} (`{i}`) | {', '.join('.' + e for e in f['extensions'] if e)} | {f['role']} | {'✓' if f['readable'] else '—'} | {'✓' if f['writable'] else '—'} | {f.get('notes') or ''} |")
    w("")
    w(table(set(ids) - ({"gif"} if sec == "8.1" else set())) and "\n".join(table(set(i for i in ids if not (sec == '8.3' and i == 'gif')))))
w("## Additional formats\n")
w("Additional 3D, font, Hangul, and CAD routes. Some require optional providers or are experimental.\n")
for title, cat in parity:
    ids = [f["id"] for f in formats if f["category"] == cat]
    w(f"### {title}\n")
    w("\n".join(table(set(ids))))
w("## Folders and packaging\n")
w("Archive *creation* (ZIP, TAR, TAR.GZ, GZIP) is a file tool, not a conversion edge, because any file or folder can be packed. "
  "See `ringo archive` and the Archive wedge. Extraction appears above as `→ folder`.\n")
w("## Two-step routes\n")
w("Rows whose provider is *Two-step route* run through an intermediate format. They are declared explicitly in "
  "`Sources/RingoEngine/RingoEngine.swift`, and their fidelity is the weaker of the two steps.\n")
open("docs/FORMATS.md", "w").write("\n".join(out) + "\n")
print(f"wrote docs/FORMATS.md: {len(fmt)} formats, {total_edges} edges, {available} available here")
