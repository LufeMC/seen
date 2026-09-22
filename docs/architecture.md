# Architecture

Seen has no backend and no third-party Swift package dependencies.

| Layer | Main files | Responsibility |
| --- | --- | --- |
| Capture | `CaptureEngine.swift` | ScreenCaptureKit display and independent-window capture |
| Recognition | `ImageIndexer` in `CaptureEngine.swift` | Vision OCR, image sizing, deduplication, and persistence |
| Storage | `MemoryStore.swift` | SQLite FTS5 search, filtering, retention, and deletion |
| Evaluation | `JevClient.swift` | Bounded requests, provider contracts, response validation, and relevance ordering |
| App state | `AppModel.swift` | Recording lifecycle, search state, preferences, and provider selection |
| Quick search | `QuickSearch.swift`, `PanelSearchField.swift` | Global hotkey, floating panel, keyboard focus, and independent results |
| Interface | `HistoryView.swift`, `ImageViewer.swift`, `DesignSystem.swift` | History, readable image previews, and shared presentation |
| Credentials | `JevSettings.swift` | Keychain operations and provider setup |

## Search sequence

1. Normalize the question for local candidate retrieval.
2. Apply app and date filters.
3. If no key is configured, show local results.
4. If a key is configured, wait for the typing delay.
5. Select up to 24 local matches and fill remaining candidate slots with recent captures.
6. Send up to 32 unique candidates to Jev.
7. Validate all expected scores and order candidates by relevance.
8. If the request fails, show local results and a failure message.

Jev is the primary result source when configured. Local candidates are not shown before its response.
Changing a query cancels the pending request and invalidates its result. Capture refreshes do not resend the same question.
A new query, filter change, or credential change permits a new request. Requests have timeouts and no automatic retries.
The local fallback remains available during provider outages.

The TypeSafe adapter uses `noul` questions and scores. The Vercel adapter uses `boolean` questions and `probability` scores.
Both adapters reject unexpected identifiers, missing answers, incorrect types, non-finite values, and scores outside zero to one.
The response only changes result order. It cannot execute instructions from captured text.

## macOS behavior

The Carbon hotkey remains registered while the process runs. Command-Q hides visible windows and leaves the process active.
A complete quit unregisters the hotkey and stops recording. System logout and shutdown can still terminate the app.

The app retains its original module name and bundle identifier for compatibility.
The `--demo` option creates a temporary store with fictional content and disables provider calls.

Seen runs as a menu bar app and does not appear in the Dock.
