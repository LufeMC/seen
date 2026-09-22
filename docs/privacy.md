# Privacy and data handling

## Capture and local storage

Seen captures connected displays and available app windows through ScreenCaptureKit.
Apple Vision recognizes text locally. SQLite stores text, app names, titles, timestamps, image paths, and optional page URLs.
JPEG images remain in the history directory. Seen records no audio.

Recording starts by default when the app opens. The menu bar shows its recording state.
Command-Q hides the app and keeps recording active. Select **Quit Seen Completely** to end the process.

Seen excludes itself and several password managers by default. Settings provide an editable exclusion list.
Private browsing is not detected automatically. Display captures can contain information from several apps.
Do not rely on the exclusion list as a guarantee that sensitive information cannot appear in another app or notification.

## Optional Jev requests

Without a saved API key, search uses the local text index and sends no provider requests.
Saving a key enables automatic Jev search. After typing stops, Seen sends the query and candidate text to the selected provider.

Each request can include:

- Up to 500 query characters.
- Up to 32 candidate captures.
- Up to 100 app-name characters per candidate.
- Up to 200 title characters per candidate.
- Up to 1,600 recognized-text characters per candidate.

The request excludes screenshots, saved URLs, file paths, original capture IDs, and timestamps.
Truncated text can still contain sensitive information. Removing a key stops future requests; it cannot recall previous requests.
An in-flight request can reach the provider before cancellation completes.

TypeSafe requests go directly to `api.typesafe.ai`. Vercel requests go to `ai-gateway.vercel.sh` and use its Jev provider route.
Provider retention, processing, and billing policies apply. Seen does not claim zero provider retention.

Keys use macOS Keychain with device-only storage. Each provider has a separate entry.
There is no shared project key, developer proxy, telemetry endpoint, or account registration.

## Retention and deletion

The default retention period is seven days. Settings also offer one or thirty days.
History is limited to 5,000 captures. Each display image and window image counts separately.
Pruning runs at startup and after new captures. The oldest captures are removed first.

The storage directory has owner-only permissions. The app does not encrypt its database or images.
Deletion removes image files and database records. It does not guarantee removal from backups or forensic recovery tools.
The latest capture-status file contains window metadata and failure counts.

## Public reports

Use fictional content in public screenshots and bug reports.
Do not attach your history directory, capture-status file, API key, or unreviewed diagnostic output.
Report vulnerabilities through the private channel described in [Security](../SECURITY.md).
