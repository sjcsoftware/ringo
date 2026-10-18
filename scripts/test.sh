#!/bin/zsh
# Runs the test suite. Building tests first, then `swift test --skip-build`, avoids a Command Line
# Tools quirk where an earlier product build leaves the Testing macro plugin unloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-tests "$@"
# NSLog chatter from system text frameworks is filtered; test output is untouched.
swift test --skip-build "$@" 2>&1 | grep -vE "CoreText note|attributedStringScaled"
