# Changelog

## 0.1.0

Initial public release.

- Native macOS Contacts search, show, create, update, and confirmed deletion.
- Search names, emails, organizations, and formatting-normalized phone numbers; text matching ignores case and accents.
- Job titles, labeled phones/emails/URLs, postal addresses, and local contact photos.
- Partial updates with explicit field/list clearing.
- Read-only deletion previews with `--dry-run`; actual deletion always requires `--yes`.
- Text and JSON output, asynchronous authorization, and actor-isolated Contacts access.
- Swift Testing suites, CLI safety smoke checks, and macOS CI.
- MIT license and a source-build Homebrew formula in `tkoenig/tap`.
