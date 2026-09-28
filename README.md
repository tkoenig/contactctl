# contactctl

A small native macOS CLI for searching, viewing, creating, updating, and deleting contacts through Apple's `CNContactStore` API.

## Privacy

`contactctl` communicates directly with the local macOS Contacts framework. It has no networking code and does not upload contact data. Read operations never modify Contacts; writes only happen through the explicit `create`, `update`, and `delete` commands. Deletion requires `--yes`.

## Requirements

- macOS 13 or newer
- Swift 6 toolchain (Xcode 16+ or compatible Command Line Tools) for building
- Contacts permission when prompted
- No paid Apple Developer account

## Build

```sh
cd ~/Development/tkoenig/contactctl
make build
```

Run the development build:

```sh
.build/release/contactctl help
```

Optionally install it into `~/.local/bin`:

```sh
make install
```

The binary embeds an `NSContactsUsageDescription` so macOS can display a permission prompt. `make build` ad-hoc signs it with the `com.tkoenig.contactctl` identifier. Rebuilding or moving the executable can still cause macOS to request permission again.

### Homebrew

```sh
brew install tkoenig/tap/contactctl
```

The formula builds from source with Xcode 16+. Once installed, run `contactctl authorize` from your terminal to grant Contacts access. See [the publishing checklist](packaging/homebrew/README.md) for maintaining the tap.

## Usage

```sh
contactctl status
contactctl authorize
contactctl search "Ada" --json
contactctl search "@example.com"       # Email/domain substring
contactctl search '+44 (20) 1234'      # Phone substring, ignoring formatting
contactctl search "Analytical Engines" # Organization substring
contactctl show <identifier> --json
```

Search combines Apple's native name search with local name, email, and organization substring matching that ignores case and accents (for example, `Muller` matches `Müller`). Phone queries may contain digits, whitespace, `+`, parentheses, hyphens, dots, and slashes; formatting is removed before matching a digit substring. Country-code prefixes are not inferred (for example `0044` is not rewritten to `+44`). Results are deduplicated by unified contact identifier and sorted by display name before applying `--limit` (default 25). Additional-field search scans the locally accessible Contacts store, so large address books may take longer. No contact data leaves the machine.

Create a contact:

```sh
contactctl create \
  --given-name Ada \
  --family-name Lovelace \
  --job-title Programmer \
  --phone 'mobile=+44 20 1234 5678' \
  --email 'work=ada@example.com' \
  --street '1 Main Street' --city London --postal-code 'SW1A 1AA' \
  --country UK --address-label work \
  --url 'homepage=https://example.com' \
  --photo ~/Pictures/ada.jpg
```

Creation requires at least a given name, family name, or organization.

- `--job-title <title>` sets the job title.
- `--phone label=value`, `--email label=value`, and `--url label=value` are repeatable. URLs can use `homepage`, `home`, `work`, `other`, or a custom label.
- `--street`, `--city`, `--state`, `--postal-code`, and `--country` describe one postal address. All fields are optional; `--street` accepts multiline text. `--address-label` defaults to `home` and requires at least one address field. Repeating a scalar option replaces its previous value; it does not create another address.
- `--photo <path>` loads a local image (for example JPEG or PNG). Unreadable files and invalid images are rejected before requesting Contacts permission or saving the contact. Remote image URLs are not downloaded.

`search` and `show` include job titles, postal addresses, URLs, and photo availability. JSON adds `jobTitle`, `postalAddresses`, `urlAddresses`, and `hasPhoto`; image bytes are not included. Photos can be attached during creation or replaced on an existing contact, but cannot currently be exported.

## Updating contacts

Use the identifier returned by `search` or `show`:

```sh
contactctl update '<identifier>' \
  --job-title Engineer \
  --street '1 Example Street' --city Wien --postal-code 1010 \
  --country AT --address-label work \
  --url 'homepage=https://example.com'

contactctl update '<identifier>' --photo ~/Pictures/portrait.jpg
contactctl update '<identifier>' --job-title '' --clear photo
```

- Only supplied fields change. Omitted fields, including photos, are preserved.
- Scalar name, organization, title, and address fields accept `''` to clear their value.
- Supplying `--phone`, `--email`, or `--url` **replaces that entire list** with the supplied repeated values, rather than appending.
- Address options patch the **first postal address**, preserving omitted components and all other addresses. If no address exists, one is created. `--address-label` changes that first address's label; it is **not a selector**. With no label supplied, an existing label is preserved, or a new address defaults to `home`.
- Changing `--country` clears the old stored ISO country code to avoid inconsistent country metadata.
- `--clear phone|email|url|photo|address` removes the corresponding list/photo (all addresses for `address`). Repeat `--clear` for multiple fields. Combining clearing and setting the same field is rejected.
- `--json` returns the updated contact. `update` requires at least one field option or `--clear`.

## Deleting contacts

Inspect the identifier first. There is no CLI undo, and Contacts/iCloud may sync the deletion to other devices. Deleting a unified contact can affect its linked records.

```sh
contactctl delete '<identifier>' --dry-run
contactctl delete '<identifier>' --dry-run --json
contactctl delete '<identifier>' --yes
```

Actual deletion always requires `--yes`, including scripts/non-TTY use. Without `--yes` or `--dry-run`, the command is rejected before accessing Contacts. `--dry-run` only reads and displays the contact; it takes precedence even when combined with `--yes`. JSON previews return `{"dryRun":true,"wouldDelete":{...contact...}}`; successful actual deletions return `{"deleted":"<identifier>"}`. Previewing may request Contacts permission but does not write anything.

Not yet supported: multiple postal addresses on creation, selecting a specific address for update, birthdays, relationships, social profiles, and vCard import/export.

## Testing

```sh
make test # swift test --enable-code-coverage
make build
python3 scripts/smoke-test.py
```

Swift Testing suites use synthetic records, in-memory `CNMutableContact` objects, and a fake deletion store. They cover parsing, output, accent-insensitive search, phone matching, deduplication/sorting/limits, field preservation/replacement/clearing, photos, authorization-status mapping, and deletion safety (including dry-run with `--yes`). Neither the tests nor CLI smoke checks access the real Contacts store. Actual authorization dialogs, store saves/deletes, and Homebrew installs are not exercised by this suite.

GitHub Actions runs these checks on macOS. Framework access lives in the `ContactsStore` actor; authorization uses async continuations rather than blocking a thread. CLI routing only parses arguments and formats results.

## License

[MIT](LICENSE).
