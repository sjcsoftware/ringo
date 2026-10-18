#!/bin/zsh
# Acceptance 9: conversions and tools work with all network access denied.
# Runs the CLI inside a sandbox profile that denies network*, over freshly generated fixtures.
# Any attempt to open a socket fails inside the sandbox, so a conversion that needed the network
# would fail here instead of passing silently.
set -euo pipefail
cd "$(dirname "$0")/.."
RINGO="${RINGO:-$(swift build -c release --show-bin-path)/ringo}"
[[ -x "$RINGO" ]] || swift build -c release --product ringo >/dev/null
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ringo-offline.XXXXXX")"
PROFILE="$WORK/deny-network.sb"
cat > "$PROFILE" <<'SB'
(version 1)
(allow default)
(deny network*)
SB
export RINGO_SETTINGS="$WORK/settings.json"
cd "$WORK"
# Fixtures (generated outside the sandbox is fine; they are local files).
printf '# Offline\n\nHello **world**.\n\n- a\n- b\n' > note.md
printf '1\n00:00:01,000 --> 00:00:02,000\nHi\n' > subs.srt
printf 'a,b\n1,2\n' > table.csv
"$RINGO" convert note.md --to pdf >/dev/null
sips -s format png /System/Library/Desktop\ Pictures/*.heic --out photo.png >/dev/null 2>&1 || \
  python3 -c "import zlib,struct;w=h=8;raw=b''.join(b'\x00'+b'\xff\x00\x00'*w for _ in range(h));c=lambda t,d:struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d));open('photo.png','wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+c(b'IDAT',zlib.compress(raw))+c(b'IEND',b''))"

run() {
  if sandbox-exec -f "$PROFILE" "$RINGO" "$@" --json > out.json 2> err.log; then
    printf '  ✓ %s\n' "$*"
  else
    printf '  ✗ %s\n' "$*"; cat err.log; python3 -c "import json;d=json.load(open('out.json'));[print('    ',r.get('error')) for r in d.get('results',[])]" 2>/dev/null || cat out.json
    FAILED=1
  fi
}
FAILED=0
echo "Running under a deny-network sandbox:"
run convert photo.png --to jpeg
run convert photo.png --to heic
run convert note.md --to docx
run convert note.md --to epub
run convert note.pdf --to png --dpi 72
run convert note.pdf --to txt
run convert table.csv --to xlsx
run convert subs.srt --to vtt
run metadata strip photo.png
run redact note.pdf --text Hello
run archive note.md table.csv --format zip
run extract Archive.zip
if command -v ffmpeg >/dev/null; then
  ffmpeg -v error -f lavfi -i sine=duration=1 tone.wav
  run convert tone.wav --to mp3
fi
# Sanity check that the sandbox really blocks the network.
if sandbox-exec -f "$PROFILE" /usr/bin/curl -s -m 3 https://example.com >/dev/null 2>&1; then
  echo "  ! network was NOT blocked; test is inconclusive"; FAILED=1
else
  echo "  ✓ network is blocked inside the sandbox (curl failed as expected)"
fi
rm -rf "$WORK"
exit $FAILED
