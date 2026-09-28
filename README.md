# contactctl

A small native macOS CLI for searching, viewing, creating, updating, and deleting contacts through Apple's `CNContactStore` API.

## Privacy

`contactctl` communicates directly with the local macOS Contacts framework. It has no networking code and does not upload contact data. Read operations never modify Contacts; writes only happen through the explicit `create`, `update`, and `delete` commands. Deletion requires `--yes`.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools with Swift
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

The binary embeds an `NSContactsUsageDescription` so macOS can display a permission prompt. Rebuilding or moving an ad-hoc local executable can sometimes cause macOS to request permission again.

## Usage

```sh
contactctl status
contactctl authorize
contactctl search "Ada" --json
contactctl show <identifier> --json
```

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
  --job-title 'Grundstücksmanagerin' \
  --street 'Wagramer Straße 19' --city Wien --postal-code 1220 \
  --country AT --address-label work \
  --url 'homepage=www.apg.at'

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
contactctl show '<identifier>'
contactctl delete '<identifier>' --yes
```

Without `--yes`, deletion is rejected before accessing Contacts. `--json` returns `{"deleted":"<identifier>"}` after a successful save.

Not yet supported: multiple postal addresses on creation, selecting a specific address for update, birthdays, relationships, social profiles, and vCard import/export.

## Testing

```sh
make test
```

The automated tests use synthetic records and in-memory `CNMutableContact` objects. They check parsing, output, field preservation/replacement/clearing, photo handling, and the delete confirmation gate, without accessing the real Contacts store. Actual store saves/deletes are not exercised.
