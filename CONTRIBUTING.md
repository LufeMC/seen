# Contributing

Seen is a native macOS app. Use macOS 14 or later and Swift 6 or later.

1. Fork the repository.
2. Create a branch for one change.
3. Run `swift test`.
4. Run `bash scripts/build-app.sh`.
5. Check the affected flow in `dist/Seen.app`.
6. Open a pull request with the problem, change, and verification results.

Use synthetic content for tests and screenshots. Do not commit captures, history databases, API keys, signing certificates, or personal paths.
Provider tests must use mock responses by default. Do not require contributors to purchase API access.

Keep capture, search, and presentation code separate. Preserve local search when remote services fail.
Changes that send additional data require corresponding updates to Settings, the README, and the privacy document.

Use the existing colors, typography, keyboard behavior, and accessibility labels.
Check empty results, long queries, provider errors, and the minimum window size when changing search.

By submitting a contribution, you agree that it is available under the repository's MIT license.
