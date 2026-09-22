# Interface decisions

Seen prioritizes a short path from a remembered question to its saved screen.
The history window provides a result list and source preview. The global shortcut opens a smaller search panel.
The panel activates Seen and assigns its native text field as the keyboard responder.
The panel expands when a preview opens. Images fill the available width and support scrolling and zoom.

A thumbnail grid was rejected because small captured text was difficult to compare.
A menu-only search was rejected because it restricted preview space.
The selected layout reuses the same result rows, image viewer, colors, and typography in both windows.

## Jev setup

The provider and API key belong in Settings. A saved key enables automatic Jev search.
The disclosure appears beside the save control. It describes the text sent to the provider and the local-only alternative.

A separate Jev search button was rejected because it added a step to each question.
Showing local results before Jev was rejected because the primary search order would change after the user started reading.
The selected flow waits for Jev and uses local results only when no key exists or the request fails.

The search field accepts full questions. The interface has no model selector, prompt editor, or chat transcript.
A compact status line reports evaluation progress and provider failures.

## App lifecycle

Command-Q hides Seen and retains recording and the global shortcut.
The menu labels this action **Keep Seen in Menu Bar**.
**Quit Seen Completely** remains available from the menu bar and with Option-Command-Q.

## Validation

Automated checks cover image sizing, independent quick-search state, automatic provider use, cancellation, and local fallback.
Public screenshots use fictional demo content. They do not include a user's capture history.
Live checks should cover typing, arrow navigation, previews, provider setup, and the shortcut after Command-Q.
VoiceOver and multiple physical displays remain separate validation requirements.

Seen runs as a menu bar app and does not appear in the Dock.
