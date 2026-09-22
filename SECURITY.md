# Security

Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/LufeMC/seen/security/advisories/new).
Do not include API keys, private screenshots, or a history database in a public issue.

Seen is an early release. Only the latest version receives fixes.
There is no independent security audit or response-time guarantee.

## Data boundaries

- Captures and recognized text remain in the local history folder unless you configure Jev search.
- With a saved key, search automatically sends candidate text and the query to the selected provider.
- Provider requests include app names and capture titles. They exclude images, source URLs, file paths, and internal capture identifiers.
- API keys use macOS Keychain. The app does not store keys in preferences or the history database.
- HTTP redirects are refused. Provider response bodies are not included in error messages.
- Captured text is untrusted input. Jev scores relevance; its response cannot run tools, open links, or execute code.
- The app accepts only finite relevance scores between zero and one for the expected capture identifiers.
- Open-page links permit HTTP and HTTPS only. A link is opened only when you select it.

The history folder has owner-only directory permissions. Its contents have no app-level encryption.
Use FileVault and an appropriate backup policy if your captures contain sensitive information.
Deletion does not guarantee removal from backups or forensic recovery tools.

Excluded apps are omitted from capture filters. Private browser windows are not detected automatically.
Pause recording before viewing information that must not enter your history.
See [Privacy](docs/privacy.md) for the complete data flow and retention rules.
