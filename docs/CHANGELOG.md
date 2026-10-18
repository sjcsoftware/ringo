# Changelog

## 1.1.0

- Double Shift (Convert) and double Command (File Tools) open Ringo only when Finder is in front with files selected. Background Finder selections, empty selections, folders alone, missing files, and selection errors do not open or change Ringo's UI.
- Double taps always require Finder in front, including when the existing Finder preference is disabled. The preference now explicitly describes its scope: alternate key combinations.
- Finder selection is checked before the ring appears and checked again for focus changes after reading the selection. Mixed file/folder selections use only files.
- Added regression coverage for selection gating and updated shortcut documentation.

## 1.0.0

- Initial release with Finder conversion and file tools, radial menus, and the bundled CLI.
