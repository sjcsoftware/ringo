# Releasing Ringo

Ringo's About pane queries `sjcsoftware/ringo` for the latest stable GitHub release. Sparkle installs the signed DMG described by the repository's `appcast.xml`. Keep both sources on the same release.

1. Update `RingoEngine.version`, README's download filename, and the changelog. Commit and merge the changes to `main` before packaging so `CFBundleVersion` (the Git commit count) increases.
2. Run `scripts/test.sh` and `scripts/package-dmg.sh`. The latter embeds and signs Sparkle and builds the DMG and SHA-256 checksum in `dist/`.
3. Run `python3 scripts/update-appcast.py dist/Ringo-<version>-arm64.dmg`. Sparkle's bundled `sign_update` reads the Ed25519 key from the macOS Keychain account `sjcsoftware.ringo`, signs the DMG, verifies the signature, and updates the feed. Do not generate a replacement key for an existing release line: installed apps trust the public key in `Resources/Info.plist`.
4. Create a draft GitHub release for `v<version>` targeting the merged commit, with the DMG and `.sha256` file attached. Include the changes and installation notes. Verify both uploaded assets.
5. Commit and push the signed appcast, point the draft release tag to that commit, and publish the release. Verify the public release and feed URLs.

The signing key was initially generated with Sparkle's `generate_keys --account sjcsoftware.ringo`. It stays in Keychain; securely back it up outside the repository. No private key belongs in Git, the app bundle, command arguments, or release assets.

The build is currently ad hoc signed and not notarized. This is separate from Sparkle's Ed25519 archive signature. Ad hoc builds require the library-validation exception to load the embedded framework because they have no Team ID. Set `RINGO_SIGN_IDENTITY` to a Developer ID identity to retain library validation when signing; notarization is a separate step. Users of versions before 1.2 must install one download manually to gain the updater. Keep automatic checks disabled unless the user explicitly enables them in a future UI.

For an installation smoke test, use a disposable copy of the release app with an older bundle version and a temporary local feed pointing to the signed DMG. Verify download, signature validation, installation and relaunch without replacing `/Applications/Ringo.app`.
