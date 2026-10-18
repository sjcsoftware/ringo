# Format matrix

Generated 2026-10-18 from the capability registry (`ringo capabilities --all --json`). Do not edit by hand; run `python3 scripts/gen-format-matrix.py <path-to-ringo>`.

**72 formats, 462 directed edges, 620 provider routes.** On the machine that generated this file, 429 edges could run; the rest need an optional provider listed in the row.

Reading the table: one row per directed edge (source → target). *Provider* is the route Ringo uses first; *Others* are fallbacks. *Fidelity* says what survives (see the legend). *Status* uses the vocabulary from PROMPT.md §15. *Here* is ✓ when the edge could run on the generating machine. *Tested* is ✓ when the automated suite converts real fixtures along that edge.

A format being readable and another being writable does **not** mean every pair converts. Only the rows below exist.

## Legend

| Fidelity | Meaning |
|---|---|
| `lossless` | Pixels, samples or text are kept exactly (container may change). |
| `remux` | Streams copied into a new container when compatible; otherwise re-encoded (reported per file). |
| `lossy` | Perceptual compression; quality setting applies. |
| `rasterized` | Vector or page content drawn into pixels. |
| `text-only` | Only text survives. |
| `approximate` | Text and styling survive; layout is approximated. |
| `heuristic` | Structure is guessed (paragraphs, headings, table cells); review the result. |
| `image-only` | Each page/slide becomes a picture; nothing is editable. |
| `packaging` | Archive packaging; bytes unchanged. |

## §8.1 Images

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| JPEG (`jpeg`) | .jpg, .jpeg, .jpe | both | ✓ | ✓ |  |
| PNG (`png`) | .png | both | ✓ | ✓ |  |
| WebP (`webp`) | .webp | both | ✓ | ✓ |  |
| HEIC (`heic`) | .heic, .heif | both | ✓ | ✓ |  |
| TIFF (`tiff`) | .tiff, .tif | both | ✓ | ✓ |  |
| AVIF (`avif`) | .avif | both | ✓ | ✓ |  |
| BMP (`bmp`) | .bmp | both | ✓ | ✓ |  |
| SVG (`svg`) | .svg | input-only | ✓ | — | Input only. Rasterized; Ringo never promises bitmap-to-vector output. |
| GIF (`gif`) | .gif | both | ✓ | ✓ | Listed under video export (§8.3); also accepted as image input. |
| Photoshop (`psd`) | .psd | input-only | ✓ | — | Flattened composite read via ImageIO. |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| avif → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels. |
| avif → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| avif → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| avif → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white. |
| avif → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| avif → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| avif → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| avif → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| bmp → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| bmp → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| bmp → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| bmp → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white. |
| bmp → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| bmp → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| bmp → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| bmp → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| gif → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| gif → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.; Animated sources keep only the first frame unless converted to GIF. |
| gif → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| gif → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white.; Animated sources keep only the first frame unless converted to GIF. |
| gif → **mov** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Animated GIF to video; transparency is flattened. |
| gif → **mp4** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Animated GIF to video; transparency is flattened. |
| gif → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| gif → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ | ✓ | Animated sources keep only the first frame unless converted to GIF. |
| gif → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| gif → **webm** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Animated GIF to video; transparency is flattened. |
| gif → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| heic → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| heic → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels. |
| heic → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| heic → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white. |
| heic → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| heic → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| heic → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| heic → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| jpeg → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| jpeg → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ | ✓ | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels. |
| jpeg → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| jpeg → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ | ✓ |  |
| jpeg → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| jpeg → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| jpeg → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| jpeg → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| png → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ | ✓ | Animated sources keep only the first frame unless converted to GIF. |
| png → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ | ✓ | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.; Animated sources keep only the first frame unless converted to GIF. |
| png → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ | ✓ | GIF is limited to 256 colors per frame. |
| png → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ | ✓ | Animated sources keep only the first frame unless converted to GIF. |
| png → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ | ✓ | JPEG has no transparency; transparent areas are filled with white.; Animated sources keep only the first frame unless converted to GIF. |
| png → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ | ✓ | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| png → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ | ✓ | Animated sources keep only the first frame unless converted to GIF. |
| png → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ | ✓ | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| psd → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.; Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame.; Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white.; Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set.; Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | Uses the flattened composite stored in the PSD; layers are not preserved. |
| psd → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| svg → **avif** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **bmp** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.; SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **gif** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | GIF is limited to 256 colors per frame.; SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **heic** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **jpeg** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white.; SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **pdf** | ImageIO (macOS) | librsvg | `rasterized` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set.; SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **png** | ImageIO (macOS) | ImageMagick, librsvg | `rasterized` | implemented | ✓ | ✓ | SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **tiff** | ImageIO (macOS) | ImageMagick | `rasterized` | implemented | ✓ |  | SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px). |
| svg → **webp** | ImageMagick |  | `rasterized` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept.; SVG is rasterized by ImageMagick's renderer. |
| tiff → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| tiff → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels. |
| tiff → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| tiff → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  |  |
| tiff → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white. |
| tiff → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| tiff → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  |  |
| tiff → **webp** | ImageMagick |  | `lossy` | provider-dependent | ✓ |  | Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept. |
| webp → **avif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| webp → **bmp** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.; Animated sources keep only the first frame unless converted to GIF. |
| webp → **gif** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | GIF is limited to 256 colors per frame. |
| webp → **heic** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| webp → **jpeg** | ImageIO (macOS) | ImageMagick | `lossy` | implemented | ✓ |  | JPEG has no transparency; transparent areas are filled with white.; Animated sources keep only the first frame unless converted to GIF. |
| webp → **pdf** | ImageIO (macOS) |  | `lossless` | implemented | ✓ |  | Each frame or page becomes one PDF page; page size follows the image unless --page-size is set. |
| webp → **png** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |
| webp → **tiff** | ImageIO (macOS) | ImageMagick | `lossless` | implemented | ✓ |  | Animated sources keep only the first frame unless converted to GIF. |

## §8.2 Audio

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| MP3 (`mp3`) | .mp3 | both | ✓ | ✓ |  |
| M4A (`m4a`) | .m4a | both | ✓ | ✓ |  |
| WAV (`wav`) | .wav | both | ✓ | ✓ |  |
| FLAC (`flac`) | .flac | both | ✓ | ✓ |  |
| OGG (`ogg`) | .ogg, .oga | both | ✓ | ✓ | Ogg is a container. Output codec is Vorbis when an encoder is available. |
| Opus (`opus`) | .opus | both | ✓ | ✓ | Opus codec in an Ogg container. |
| AIFF (`aiff`) | .aiff, .aif, .aifc | both | ✓ | ✓ |  |
| WMA (`wma`) | .wma | both | ✓ | ✓ | Requires an FFmpeg build with the wmav2 encoder. |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| aiff → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| aiff → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| aiff → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| aiff → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| aiff → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| aiff → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| aiff → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| flac → **aiff** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| flac → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| flac → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| flac → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| flac → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| flac → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| flac → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| m4a → **aiff** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| m4a → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| m4a → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| m4a → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| m4a → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| m4a → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| m4a → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| mp3 → **aiff** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| mp3 → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| mp3 → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| mp3 → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| mp3 → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| mp3 → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| mp3 → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| ogg → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| ogg → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| ogg → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| ogg → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| ogg → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| ogg → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| ogg → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| opus → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| opus → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| opus → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| opus → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| opus → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| opus → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| opus → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Windows Media Audio 2 (wmav2), 192 kbps. |
| wav → **aiff** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ | ✓ | Lossless container; quality cannot exceed the source. |
| wav → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ | ✓ | Lossless container; quality cannot exceed the source. |
| wav → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ | ✓ | AAC in MPEG-4, 192 kbps by default. |
| wav → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ | ✓ | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| wav → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ | ✓ | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| wav → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ | ✓ | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| wav → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ | ✓ | Windows Media Audio 2 (wmav2), 192 kbps. |
| wma → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| wma → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |
| wma → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | AAC in MPEG-4, 192 kbps by default. |
| wma → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| wma → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| wma → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| wma → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Lossless container; quality cannot exceed the source. |

## §8.3 Video

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| GIF (`gif`) | .gif | both | ✓ | ✓ | Listed under video export (§8.3); also accepted as image input. |
| MP4 (`mp4`) | .mp4, .m4v | both | ✓ | ✓ |  |
| MOV (`mov`) | .mov, .qt | both | ✓ | ✓ |  |
| MKV (`mkv`) | .mkv | both | ✓ | ✓ |  |
| WebM (`webm`) | .webm | both | ✓ | ✓ |  |
| AVI (`avi`) | .avi | both | ✓ | ✓ |  |
| WMV (`wmv`) | .wmv | both | ✓ | ✓ |  |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| avi → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| avi → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| avi → **gif** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| avi → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| avi → **mkv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MKV; otherwise video is re-encoded (H.264 + AAC).; HDR sources re-encoded to 8-bit codecs are not tone-mapped. |
| avi → **mov** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MOV; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| avi → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| avi → **mp4** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MP4; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| avi → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| avi → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| avi → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| avi → **webm** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WEBM; otherwise video is re-encoded (VP9 + Opus).; Subtitle and attachment streams are kept only for MKV targets. |
| avi → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |
| avi → **wmv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WMV; otherwise video is re-encoded (WMV2 + WMA2).; Subtitle and attachment streams are kept only for MKV targets. |
| mkv → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mkv → **avi** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit AVI; otherwise video is re-encoded (H.264 + MP3).; Subtitle and attachment streams are kept only for MKV targets. |
| mkv → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mkv → **gif** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| mkv → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| mkv → **mov** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MOV; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| mkv → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| mkv → **mp4** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MP4; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| mkv → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| mkv → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| mkv → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mkv → **webm** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WEBM; otherwise video is re-encoded (VP9 + Opus).; Subtitle and attachment streams are kept only for MKV targets. |
| mkv → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |
| mkv → **wmv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WMV; otherwise video is re-encoded (WMV2 + WMA2).; Subtitle and attachment streams are kept only for MKV targets. |
| mov → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mov → **avi** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit AVI; otherwise video is re-encoded (H.264 + MP3).; Subtitle and attachment streams are kept only for MKV targets. |
| mov → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mov → **gif** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| mov → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| mov → **mkv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MKV; otherwise video is re-encoded (H.264 + AAC).; HDR sources re-encoded to 8-bit codecs are not tone-mapped. |
| mov → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| mov → **mp4** | FFmpeg | AVFoundation (macOS) | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MP4; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| mov → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| mov → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| mov → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mov → **webm** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WEBM; otherwise video is re-encoded (VP9 + Opus).; Subtitle and attachment streams are kept only for MKV targets. |
| mov → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |
| mov → **wmv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WMV; otherwise video is re-encoded (WMV2 + WMA2).; Subtitle and attachment streams are kept only for MKV targets. |
| mp4 → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mp4 → **avi** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit AVI; otherwise video is re-encoded (H.264 + MP3).; Subtitle and attachment streams are kept only for MKV targets. |
| mp4 → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mp4 → **gif** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ | ✓ | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| mp4 → **m4a** | FFmpeg | AVFoundation (macOS) | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| mp4 → **mkv** | FFmpeg |  | `remux` | provider-dependent | ✓ | ✓ | Streams are copied when the codecs fit MKV; otherwise video is re-encoded (H.264 + AAC).; HDR sources re-encoded to 8-bit codecs are not tone-mapped. |
| mp4 → **mov** | FFmpeg | AVFoundation (macOS) | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MOV; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| mp4 → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ | ✓ | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| mp4 → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| mp4 → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| mp4 → **wav** | FFmpeg | AVFoundation (macOS) | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| mp4 → **webm** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WEBM; otherwise video is re-encoded (VP9 + Opus).; Subtitle and attachment streams are kept only for MKV targets. |
| mp4 → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |
| mp4 → **wmv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WMV; otherwise video is re-encoded (WMV2 + WMA2).; Subtitle and attachment streams are kept only for MKV targets. |
| webm → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| webm → **avi** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit AVI; otherwise video is re-encoded (H.264 + MP3).; Subtitle and attachment streams are kept only for MKV targets. |
| webm → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| webm → **gif** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| webm → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| webm → **mkv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MKV; otherwise video is re-encoded (H.264 + AAC).; HDR sources re-encoded to 8-bit codecs are not tone-mapped. |
| webm → **mov** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MOV; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| webm → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| webm → **mp4** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MP4; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| webm → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| webm → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| webm → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| webm → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |
| webm → **wmv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WMV; otherwise video is re-encoded (WMV2 + WMA2).; Subtitle and attachment streams are kept only for MKV targets. |
| wmv → **aiff** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| wmv → **avi** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit AVI; otherwise video is re-encoded (H.264 + MP3).; Subtitle and attachment streams are kept only for MKV targets. |
| wmv → **flac** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| wmv → **gif** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration). |
| wmv → **m4a** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; AAC in MPEG-4, 192 kbps by default. |
| wmv → **mkv** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MKV; otherwise video is re-encoded (H.264 + AAC).; HDR sources re-encoded to 8-bit codecs are not tone-mapped. |
| wmv → **mov** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MOV; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| wmv → **mp3** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; MP3 via LAME, 192 kbps by default (--audio-bitrate). |
| wmv → **mp4** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit MP4; otherwise video is re-encoded (H.264 + AAC).; Subtitle and attachment streams are kept only for MKV targets. |
| wmv → **ogg** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result). |
| wmv → **opus** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz. |
| wmv → **wav** | FFmpeg |  | `lossless` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Lossless container; quality cannot exceed the source. |
| wmv → **webm** | FFmpeg |  | `remux` | provider-dependent | ✓ |  | Streams are copied when the codecs fit WEBM; otherwise video is re-encoded (VP9 + Opus).; Subtitle and attachment streams are kept only for MKV targets. |
| wmv → **wma** | FFmpeg |  | `lossy` | provider-dependent | ✓ |  | Extracts the first audio track. Fails clearly when the video has no audio.; Windows Media Audio 2 (wmav2), 192 kbps. |

## §8.4 PDF

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| PDF (`pdf`) | .pdf | both | ✓ | ✓ |  |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| pdf → **docx** | PDFKit (macOS) |  | `heuristic` | implemented | ✓ | ✓ | Text is reflowed into an editable document with inferred headings and lists. Layout, images, columns and tables are NOT reproduced. Scanned PDFs need --ocr. |
| pdf → **epub** | PDFKit (macOS) | Calibre | `heuristic` | implemented | ✓ | ✓ | Reflowable text only; images and layout are dropped. |
| pdf → **heic** | PDFKit (macOS) |  | `rasterized` | implemented | ✓ |  | All pages by default at 300 DPI (adjust with --dpi, select with --pages). Multi-page output files are named <name>-p01, -p02 … |
| pdf → **html** | PDFKit (macOS) |  | `heuristic` | implemented | ✓ |  | Reflowed text with inferred headings and lists; layout, images and tables are not kept. |
| pdf → **jpeg** | PDFKit (macOS) |  | `rasterized` | implemented | ✓ | ✓ | All pages by default at 300 DPI (adjust with --dpi, select with --pages). Multi-page output files are named <name>-p01, -p02 …; JPEG compression is lossy. |
| pdf → **md** | PDFKit (macOS) |  | `heuristic` | implemented | ✓ | ✓ | Paragraphs, headings and lists are reconstructed from line positions and font sizes; tables, columns and images are not. |
| pdf → **pages** | Two-step route |  | `heuristic` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| pdf → **png** | PDFKit (macOS) |  | `rasterized` | implemented | ✓ | ✓ | All pages by default at 300 DPI (adjust with --dpi, select with --pages). Multi-page output files are named <name>-p01, -p02 … |
| pdf → **pptx** | PDFKit (macOS) |  | `image-only` | implemented | ✓ | ✓ | Each page becomes one slide containing a picture of the page (200 DPI). Nothing on the slides is editable text. |
| pdf → **tiff** | PDFKit (macOS) |  | `rasterized` | implemented | ✓ |  | All pages by default at 300 DPI (adjust with --dpi, select with --pages). Multi-page output files are named <name>-p01, -p02 … |
| pdf → **txt** | PDFKit (macOS) |  | `text-only` | implemented | ✓ | ✓ | Text layer only. Scanned pages need --ocr (local Vision OCR); without a text layer and without OCR the result is empty. |
| pdf → **xlsx** | PDFKit (macOS) |  | `heuristic` | experimental | ✓ | ✓ | Experimental: cells are guessed from text positions, one sheet per page. Merged cells, formulas and formatting are not recovered; review the result. |

## §8.5 Documents

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| Word (DOCX) (`docx`) | .docx | both | ✓ | ✓ |  |
| Pages (`pages`) | .pages | both | ✓ | ✓ | Requires Apple Pages installed locally (AppleScript automation). |
| Markdown (`md`) | .md, .markdown | both | ✓ | ✓ |  |
| Plain Text (`txt`) | .txt, .text | both | ✓ | ✓ |  |
| EPUB (`epub`) | .epub | both | ✓ | ✓ |  |
| RTF (`rtf`) | .rtf | input-only | ✓ | — |  |
| RTFD (`rtfd`) | .rtfd | input-only | ✓ | — | RTFD is a package (directory). |
| Text Clipping (`textclipping`) | .textclipping | input-only | ✓ | — |  |
| HTML (`html`) | .html, .htm | export-only | ✓ | ✓ | Export target; also accepted as input. |
| OpenDocument Text (`odt`) | .odt | both | ✓ | ✓ |  |
| Word 97 (DOC) (`doc`) | .doc | input-only | ✓ | — |  |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| doc → **docx** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| doc → **epub** | macOS text system |  | `approximate` | implemented | ✓ |  | Single-chapter EPUB 3 with headings, paragraphs, lists and emphasis; images and styling are not included. |
| doc → **html** | macOS text system |  | `approximate` | implemented | ✓ |  |  |
| doc → **md** | macOS text system |  | `approximate` | implemented | ✓ |  | Headings are inferred from font size; bold, italic, links and lists are kept. Colors, fonts and tables from rich text are dropped. |
| doc → **odt** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| doc → **pdf** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| doc → **txt** | macOS text system |  | `text-only` | implemented | ✓ |  |  |
| docx → **epub** | Pandoc | Calibre, macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| docx → **html** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  |  |
| docx → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ | ✓ | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| docx → **odt** | macOS text system | LibreOffice, Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| docx → **pages** | Apple Pages & Keynote |  | `approximate` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| docx → **pdf** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| docx → **txt** | macOS text system | Pandoc | `text-only` | implemented | ✓ |  |  |
| epub → **docx** | Pandoc | Calibre, macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| epub → **html** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| epub → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| epub → **odt** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| epub → **pdf** | macOS text system | Calibre | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced.; EPUB images are dropped. |
| epub → **txt** | Pandoc | macOS text system | `text-only` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| html → **docx** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| html → **epub** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| html → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| html → **odt** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| html → **pdf** | macOS text system |  | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| html → **txt** | macOS text system | Pandoc | `text-only` | implemented | ✓ |  |  |
| md → **docx** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ | ✓ | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| md → **epub** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ | ✓ | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| md → **html** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ | ✓ | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| md → **odt** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| md → **pdf** | macOS text system |  | `approximate` | implemented | ✓ | ✓ | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced.; Markdown is read with Ringo's built-in reader (CommonMark subset). Install Pandoc for full CommonMark/GFM. |
| md → **txt** | Pandoc | macOS text system | `text-only` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| odt → **docx** | macOS text system | LibreOffice, Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| odt → **epub** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| odt → **html** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  |  |
| odt → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| odt → **pdf** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| odt → **txt** | macOS text system | Pandoc | `text-only` | implemented | ✓ |  |  |
| pages → **docx** | Apple Pages & Keynote | LibreOffice | `approximate` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| pages → **epub** | Apple Pages & Keynote |  | `approximate` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| pages → **html** | Two-step route |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| pages → **md** | Two-step route |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| pages → **odt** | LibreOffice |  | `approximate` | experimental | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| pages → **pdf** | Apple Pages & Keynote | LibreOffice | `lossless` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| pages → **txt** | Apple Pages & Keynote |  | `text-only` | provider-dependent | ✗ |  | Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files. |
| rtf → **docx** | macOS text system | LibreOffice, Pandoc | `approximate` | implemented | ✓ | ✓ | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| rtf → **epub** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access). |
| rtf → **html** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  |  |
| rtf → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| rtf → **odt** | macOS text system | LibreOffice, Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| rtf → **pdf** | macOS text system | LibreOffice | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| rtf → **txt** | macOS text system | Pandoc | `text-only` | implemented | ✓ |  |  |
| rtfd → **docx** | macOS text system |  | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| rtfd → **epub** | macOS text system |  | `approximate` | implemented | ✓ |  | Single-chapter EPUB 3 with headings, paragraphs, lists and emphasis; images and styling are not included. |
| rtfd → **html** | macOS text system |  | `approximate` | implemented | ✓ |  |  |
| rtfd → **md** | macOS text system |  | `approximate` | implemented | ✓ |  | Headings are inferred from font size; bold, italic, links and lists are kept. Colors, fonts and tables from rich text are dropped. |
| rtfd → **odt** | macOS text system |  | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| rtfd → **pdf** | macOS text system |  | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| rtfd → **txt** | macOS text system |  | `text-only` | implemented | ✓ | ✓ |  |
| textclipping → **docx** | macOS text system |  | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| textclipping → **epub** | macOS text system |  | `approximate` | implemented | ✓ |  | Single-chapter EPUB 3 with headings, paragraphs, lists and emphasis; images and styling are not included. |
| textclipping → **html** | macOS text system |  | `approximate` | implemented | ✓ |  |  |
| textclipping → **md** | macOS text system |  | `approximate` | implemented | ✓ | ✓ | Headings are inferred from font size; bold, italic, links and lists are kept. Colors, fonts and tables from rich text are dropped. |
| textclipping → **odt** | macOS text system |  | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| textclipping → **pdf** | macOS text system |  | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |
| textclipping → **txt** | macOS text system |  | `text-only` | implemented | ✓ |  |  |
| txt → **docx** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| txt → **epub** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; Plain text is read as Markdown. |
| txt → **html** | macOS text system | Pandoc | `lossless` | implemented | ✓ |  |  |
| txt → **md** | Pandoc | macOS text system | `approximate` | provider-dependent | ✓ |  | Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access).; GitHub-flavored Markdown; styling without a Markdown equivalent is dropped. |
| txt → **odt** | macOS text system | Pandoc | `approximate` | implemented | ✓ |  | Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not. |
| txt → **pdf** | macOS text system |  | `approximate` | implemented | ✓ |  | Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced. |

## §8.6 Slides

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| PowerPoint (PPTX) (`pptx`) | .pptx | both | ✓ | ✓ |  |
| PowerPoint 97 (PPT) (`ppt`) | .ppt | input-only | ✓ | — |  |
| Keynote (`key`) | .key | input-only | ✓ | — | Requires Keynote installed locally. |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| key → **jpeg** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| key → **pdf** | Apple Pages & Keynote | LibreOffice | `lossless` | provider-dependent | ✗ |  | Requires Apple Keynote (free on the Mac App Store). |
| key → **png** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| key → **pptx** | Apple Pages & Keynote | LibreOffice | `approximate` | provider-dependent | ✗ |  | Requires Apple Keynote (free on the Mac App Store). |
| ppt → **jpeg** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| ppt → **pdf** | Apple Pages & Keynote | LibreOffice | `approximate` | provider-dependent | ✗ |  | Requires Apple Keynote (free on the Mac App Store). |
| ppt → **png** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| ppt → **pptx** | LibreOffice |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| pptx → **jpeg** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| pptx → **pdf** | Apple Pages & Keynote | LibreOffice | `approximate` | provider-dependent | ✗ |  | Requires Apple Keynote (free on the Mac App Store). |
| pptx → **png** | Two-step route |  | `image-only` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |

## §8.7 Spreadsheets

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| Excel (XLSX) (`xlsx`) | .xlsx | both | ✓ | ✓ |  |
| OpenDocument Sheet (`ods`) | .ods | both | ✓ | ✓ |  |
| CSV (`csv`) | .csv | both | ✓ | ✓ |  |
| TSV (`tsv`) | .tsv, .tab | both | ✓ | ✓ |  |
| Excel 97 (XLS) (`xls`) | .xls | input-only | ✓ | — |  |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| csv → **ods** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ |  | Numbers are detected; values with leading zeros stay text. Input encoding is detected (UTF-8, UTF-16, legacy code pages). |
| csv → **pdf** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ | ✓ | Rendered by Ringo as a values-only grid on landscape A4 pages, every sheet, wide sheets split across pages. Excel print areas, styles and charts are not reproduced; LibreOffice gives higher fidelity when installed. |
| csv → **tsv** | Ringo spreadsheet engine |  | `lossless` | implemented | ✓ |  | UTF-8, RFC 4180 quoting, CRLF line endings. Dates are written as ISO 8601. |
| csv → **xlsx** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ | ✓ | Numbers are detected; values with leading zeros stay text. Input encoding is detected (UTF-8, UTF-16, legacy code pages). |
| ods → **csv** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ | ✓ | Writes the first sheet by default; --sheet <name\|number> picks one, --sheet all writes one file per sheet.; Formulas are exported as their last calculated values; formatting is dropped. |
| ods → **pdf** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ |  | Rendered by Ringo as a values-only grid on landscape A4 pages, every sheet, wide sheets split across pages. Excel print areas, styles and charts are not reproduced; LibreOffice gives higher fidelity when installed. |
| ods → **tsv** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ |  | Writes the first sheet by default; --sheet <name\|number> picks one, --sheet all writes one file per sheet.; Formulas are exported as their last calculated values; formatting is dropped. |
| ods → **xlsx** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ |  | Cell values only: formulas become values; styles, merged cells, charts and comments are not carried over. |
| tsv → **csv** | Ringo spreadsheet engine |  | `lossless` | implemented | ✓ |  | UTF-8, RFC 4180 quoting, CRLF line endings. Dates are written as ISO 8601. |
| tsv → **ods** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ |  | Numbers are detected; values with leading zeros stay text. Input encoding is detected (UTF-8, UTF-16, legacy code pages). |
| tsv → **pdf** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ |  | Rendered by Ringo as a values-only grid on landscape A4 pages, every sheet, wide sheets split across pages. Excel print areas, styles and charts are not reproduced; LibreOffice gives higher fidelity when installed. |
| tsv → **xlsx** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ |  | Numbers are detected; values with leading zeros stay text. Input encoding is detected (UTF-8, UTF-16, legacy code pages). |
| xls → **csv** | LibreOffice |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| xls → **ods** | Two-step route | LibreOffice | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| xls → **pdf** | LibreOffice |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| xls → **tsv** | Two-step route |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| xls → **xlsx** | LibreOffice |  | `approximate` | provider-dependent | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| xlsx → **csv** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ | ✓ | Writes the first sheet by default; --sheet <name\|number> picks one, --sheet all writes one file per sheet.; Formulas are exported as their last calculated values; formatting is dropped. |
| xlsx → **ods** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ | ✓ | Cell values only: formulas become values; styles, merged cells, charts and comments are not carried over. |
| xlsx → **pdf** | Ringo spreadsheet engine | LibreOffice | `approximate` | implemented | ✓ |  | Rendered by Ringo as a values-only grid on landscape A4 pages, every sheet, wide sheets split across pages. Excel print areas, styles and charts are not reproduced; LibreOffice gives higher fidelity when installed. |
| xlsx → **tsv** | Ringo spreadsheet engine |  | `approximate` | implemented | ✓ | ✓ | Writes the first sheet by default; --sheet <name\|number> picks one, --sheet all writes one file per sheet.; Formulas are exported as their last calculated values; formatting is dropped. |

## §8.8 Subtitles

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| SubRip (SRT) (`srt`) | .srt | both | ✓ | ✓ |  |
| WebVTT (`vtt`) | .vtt | both | ✓ | ✓ |  |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| srt → **txt** | Ringo subtitle engine |  | `text-only` | implemented | ✓ | ✓ | Timing is dropped unless --keep-timestamps is used. |
| srt → **vtt** | Ringo subtitle engine |  | `lossless` | implemented | ✓ | ✓ | SRT formatting tags (<b>, <i>, <u>) are kept; <font> tags are removed. |
| vtt → **srt** | Ringo subtitle engine |  | `approximate` | implemented | ✓ | ✓ | VTT cue settings (position, alignment), regions, STYLE and NOTE blocks have no SRT equivalent and are dropped. |
| vtt → **txt** | Ringo subtitle engine |  | `text-only` | implemented | ✓ |  | Timing is dropped unless --keep-timestamps is used. |

## §8.9 Archives

| Format | Extensions | Role | Readable | Writable | Notes |
|---|---|---|---|---|---|
| ZIP (`zip`) | .zip | both | ✓ | ✓ |  |
| TAR (`tar`) | .tar | both | ✓ | ✓ |  |
| GZIP (`gzip`) | .gz, .gzip | both | ✓ | — | Compresses a single stream. Multiple files are packaged as .tar.gz. |
| TAR.GZ (`tgz`) | .tar.gz, .tgz | both | ✓ | ✓ |  |
| RAR (`rar`) | .rar | input-only | ✓ | — | Extraction only, through libarchive. Ringo never creates RAR files. |

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| gzip → **folder** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ | ✓ | Decompresses the single file inside the .gz next to it (named from the gzip header or the file name). |
| rar → **folder** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Extracted into a new sibling folder. Entries with absolute paths or '..' reject the archive; links pointing outside are removed; extraction stops past 20 GB.; RAR is read-only (libarchive supports RAR 4 and most RAR 5 archives; encrypted RAR is not supported). |
| rar → **tar** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| rar → **tgz** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| rar → **zip** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| tar → **folder** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ | ✓ | Extracted into a new sibling folder. Entries with absolute paths or '..' reject the archive; links pointing outside are removed; extraction stops past 20 GB. |
| tar → **tgz** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| tar → **zip** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| tgz → **folder** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ | ✓ | Extracted into a new sibling folder. Entries with absolute paths or '..' reject the archive; links pointing outside are removed; extraction stops past 20 GB. |
| tgz → **tar** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| tgz → **zip** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| zip → **folder** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ | ✓ | Extracted into a new sibling folder. Entries with absolute paths or '..' reject the archive; links pointing outside are removed; extraction stops past 20 GB. |
| zip → **tar** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ |  | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |
| zip → **tgz** | libarchive (macOS bsdtar) |  | `packaging` | implemented | ✓ | ✓ | Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored. |

## §8.10 Parity candidates

These come from the Filee/Tangerine benchmark (see PARITY_MATRIX.md). They are not part of the required catalog; their status is listed honestly.

### 3D models

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| abc → **obj** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| abc → **ply** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| abc → **stl** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| abc → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| abc → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| abc → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| dae → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| dae → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| dae → **obj** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| dae → **ply** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| dae → **stl** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **obj** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **ply** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| fbx → **stl** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| glb → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| glb → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| glb → **obj** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| glb → **ply** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| glb → **stl** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| gltf → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| gltf → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| gltf → **obj** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| gltf → **ply** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| gltf → **stl** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| obj → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| obj → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| obj → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| obj → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| obj → **ply** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| obj → **stl** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ | ✓ | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| obj → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| obj → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| obj → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| ply → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| ply → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| ply → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| ply → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| ply → **obj** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| ply → **stl** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| ply → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| ply → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| ply → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| stl → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| stl → **dae** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| stl → **glb** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| stl → **gltf** | Assimp |  | `approximate` | experimental | ✓ |  | Converted by Assimp; animation, skinning and some materials may not survive. |
| stl → **obj** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| stl → **ply** | Model I/O (macOS) | Assimp | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| stl → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| stl → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| stl → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usd → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usd → **obj** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usd → **ply** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| usd → **stl** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| usd → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usd → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usda → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usda → **obj** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usda → **ply** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| usda → **stl** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| usda → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usda → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdc → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdc → **obj** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdc → **ply** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| usdc → **stl** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| usdc → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdc → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdz → **abc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdz → **obj** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdz → **ply** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; Scene hierarchy is flattened. |
| usdz → **stl** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them.; STL stores triangles only: no colors, normals per vertex, UVs or materials. |
| usdz → **usd** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdz → **usda** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |
| usdz → **usdc** | Model I/O (macOS) |  | `approximate` | experimental | ✓ |  | Geometry is converted; materials, textures and animation survive only where both formats support them. |

### Fonts

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| otf → **woff** | Ringo WOFF engine |  | `lossless` | implemented | ✓ |  | Tables are zlib-compressed; glyphs are unchanged. |
| otf → **woff2** | woff2 tools |  | `lossless` | provider-dependent | ✗ |  | Requires the woff2 tools. Install them with `brew install woff2`. |
| ttf → **woff** | Ringo WOFF engine |  | `lossless` | implemented | ✓ | ✓ | Tables are zlib-compressed; glyphs are unchanged. |
| ttf → **woff2** | woff2 tools |  | `lossless` | provider-dependent | ✗ |  | Requires the woff2 tools. Install them with `brew install woff2`. |
| woff → **otf** | Ringo WOFF engine |  | `lossless` | implemented | ✓ |  | Fails if the WOFF wraps TrueType outlines (convert to TTF instead). |
| woff → **ttf** | Ringo WOFF engine |  | `lossless` | implemented | ✓ | ✓ | Fails if the WOFF wraps CFF outlines (convert to OTF instead). |
| woff2 → **otf** | woff2 tools |  | `lossless` | provider-dependent | ✗ |  | Requires the woff2 tools. Install them with `brew install woff2`. |
| woff2 → **ttf** | woff2 tools |  | `lossless` | provider-dependent | ✗ |  | Requires the woff2 tools. Install them with `brew install woff2`. |

### Hangul

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| hwp → **docx** | Ringo Hangul reader | LibreOffice | `approximate` | experimental | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed.; Binary HWP 5.0 only; password- or distribution-protected documents are refused. |
| hwp → **epub** | Ringo Hangul reader |  | `approximate` | experimental | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed.; Binary HWP 5.0 only; password- or distribution-protected documents are refused. |
| hwp → **html** | Ringo Hangul reader |  | `approximate` | experimental | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed.; Binary HWP 5.0 only; password- or distribution-protected documents are refused. |
| hwp → **md** | Two-step route | Ringo Hangul reader | `approximate` | experimental | ✓ |  | Converted through DOCX. |
| hwp → **odt** | LibreOffice |  | `approximate` | experimental | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |
| hwp → **pdf** | Ringo Hangul reader | LibreOffice | `approximate` | experimental | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed.; Binary HWP 5.0 only; password- or distribution-protected documents are refused. |
| hwp → **txt** | Two-step route | Ringo Hangul reader | `text-only` | experimental | ✓ |  | Converted through DOCX. |
| hwpx → **docx** | Ringo Hangul reader |  | `approximate` | implemented | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |
| hwpx → **epub** | Ringo Hangul reader |  | `approximate` | implemented | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |
| hwpx → **html** | Ringo Hangul reader |  | `approximate` | implemented | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |
| hwpx → **md** | Ringo Hangul reader |  | `approximate` | implemented | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |
| hwpx → **pdf** | Ringo Hangul reader |  | `approximate` | implemented | ✓ |  | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |
| hwpx → **txt** | Ringo Hangul reader |  | `text-only` | implemented | ✓ | ✓ | Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed. |

### CAD

| Edge | Provider | Others | Fidelity | Status | Here | Tested | Notes / requirement |
|---|---|---|---|---|---|---|---|
| dwg → **dxf** | LibreDWG |  | `approximate` | experimental | ✗ |  | Requires LibreDWG. Install it with `brew install libredwg`. |
| dwg → **pdf** | Two-step route |  | `approximate` | experimental | ✗ |  | Requires LibreDWG. Install it with `brew install libredwg`. |
| dxf → **pdf** | LibreOffice |  | `approximate` | experimental | ✗ |  | Requires LibreOffice. Install it with `brew install --cask libreoffice` (about 1 GB). |

## Folders and packaging

Archive *creation* (ZIP, TAR, TAR.GZ, GZIP) is a file tool, not a conversion edge, because any file or folder can be packed. See `ringo archive` and the Archive wedge. Extraction appears above as `→ folder`.

## Two-step routes

Rows whose provider is *Two-step route* run through an intermediate format. They are declared explicitly in `Sources/RingoEngine/RingoEngine.swift`, and their fidelity is the weaker of the two steps.

