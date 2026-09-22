# Release checklist

1. Run `swift test` on macOS.
2. Quit the running app completely.
3. Build with `bash scripts/build-app.sh`.
4. Verify the app signature with `codesign --verify --deep --strict dist/Seen.app`.
5. Test capture permission, recording, search, and pause.
6. Test quick search after Command-Q hides Seen.
7. Test both provider routes with fictional text and your own keys.
8. Remove test keys after the provider checks.
9. Review staged files for secrets, private captures, and personal paths.
10. Confirm that GitHub Actions passes.
11. Tag the reviewed commit.
12. Publish release notes with known limits.

The initial release distributes source code. It does not include a notarized app installer.
Before distributing a public macOS binary, use Developer ID signing and Apple notarization.
Do not publish a personal development certificate or tell users to disable Gatekeeper.

Capture public screenshots with `--demo`. Review every image before publication.
Do not use real capture history as a release asset.
