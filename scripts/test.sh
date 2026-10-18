#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, a test build that follows a plain
# product build sometimes fails with "plugin for module 'TestingMacros' not found"; an immediate
# second build succeeds, so build once more on failure, then run without rebuilding.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-tests "$@" >/dev/null 2>&1 || swift build --build-tests "$@"
# NSLog chatter from system text frameworks is filtered; test output is untouched.
swift test --skip-build "$@" 2>&1 | grep -vE "CoreText note|attributedStringScaled"
