#!/bin/zsh
# Runs the test suite with Xcode or the standalone Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
# Some Command Line Tools releases omit TestingMacros from Swift Build's plugin search path.
TEST_SWIFT_FLAGS=()
TESTING_PLUGIN="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" ]]; then
  TEST_SWIFT_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN")
fi
swift build --build-tests "${TEST_SWIFT_FLAGS[@]}" "$@"
# NSLog chatter from system text frameworks is filtered; test output is untouched.
swift test --skip-build "${TEST_SWIFT_FLAGS[@]}" "$@" 2>&1 | grep -vE "CoreText note|attributedStringScaled"
