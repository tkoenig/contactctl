import ContactCore
import Darwin
import Foundation

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main
struct ContactCLI {
    private static let store = ContactsStore()

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("contactctl: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        let rest = Array(arguments.dropFirst())
        if rest == ["--help"] || rest == ["-h"] {
            printHelp()
            return
        }
        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "version", "--version":
            print("contactctl 0.1.0")
        case "status":
            print(ContactsStore.authorizationStatus().rawValue)
        case "authorize", "auth":
            let granted = try await store.authorize()
            print(granted ? "authorized" : "denied")
            if !granted { exit(2) }
        case "search":
            try await search(rest)
        case "show":
            try await show(rest)
        case "create":
            let options = try CreateOptions(arguments: rest)
            let result = try await store.create(options: options)
            try printRecord(result, json: options.json)
        case "update":
            try await update(rest)
        case "delete":
            try await delete(rest)
        default:
            throw CLIError("unknown command '\(command)'; run 'contactctl help'")
        }
    }

    private static func search(_ arguments: [String]) async throws {
        var query: String?
        var json = false
        var limit = 25
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
            case "--limit":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
                    throw CLIError("--limit requires a positive integer")
                }
                limit = value
            default:
                guard !arguments[index].hasPrefix("-"), query == nil else {
                    throw CLIError("usage: contactctl search <query> [--limit N] [--json]")
                }
                query = arguments[index]
            }
            index += 1
        }
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError("usage: contactctl search <query> [--limit N] [--json]")
        }
        let contacts = try await store.search(query: query, limit: limit)
        if json {
            print(try ContactOutput.json(contacts))
        } else if contacts.isEmpty {
            print("No contacts found.")
        } else {
            print(contacts.map(ContactOutput.text).joined(separator: "\n\n"))
        }
    }

    private static func show(_ arguments: [String]) async throws {
        let json = arguments.contains("--json")
        let positionals = arguments.filter { !$0.hasPrefix("-") }
        guard positionals.count == 1,
              !positionals[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              arguments.allSatisfy({ $0 == "--json" || !$0.hasPrefix("-") }) else {
            throw CLIError("usage: contactctl show <identifier> [--json]")
        }
        // Preserve actual permission/fetch/output errors rather than reporting all as not-found.
        let result = try await store.show(identifier: positionals[0])
        try printRecord(result, json: json)
    }

    private static func update(_ arguments: [String]) async throws {
        guard let identifier = arguments.first, !identifier.hasPrefix("-"),
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError("usage: contactctl update <identifier> [field options] [--json]")
        }
        let options = try CreateOptions(arguments: Array(arguments.dropFirst()), updating: true)
        let result = try await store.update(identifier: identifier, options: options)
        try printRecord(result, json: options.json)
    }

    private static func delete(_ arguments: [String]) async throws {
        let options = try DeleteOptions(arguments: arguments)
        switch try await ContactDeletion.perform(options, using: store) {
        case .preview(let contact):
            if options.json {
                print(try ContactOutput.json(DeletePreview(dryRun: true, wouldDelete: contact)))
            } else {
                print("Would delete (dry run; no changes):\n\(ContactOutput.text(contact))")
            }
        case .deleted(let identifier):
            if options.json {
                print(try ContactOutput.json(["deleted": identifier]))
            } else {
                print("Deleted contact '\(identifier)'.")
            }
        }
    }

    private struct DeletePreview: Encodable {
        let dryRun: Bool
        let wouldDelete: ContactRecord
    }

    private static func printRecord(_ record: ContactRecord, json: Bool) throws {
        print(json ? try ContactOutput.json(record) : ContactOutput.text(record))
    }

    private static func printHelp() {
        print("""
        Usage: contactctl <command> [options]

        Commands:
          status                         Show Contacts authorization status
          authorize                      Request Contacts authorization
          search <query> [--limit N]      Search name, email, phone, or organization
          show <identifier>              Show one contact
          create [options]               Create a contact
          update <identifier> [options]  Update only supplied fields
          delete <identifier> --yes      Permanently delete a contact
          delete <identifier> --dry-run  Preview deletion without changing anything

        Search:
          Text matching ignores case and accents; phone matching ignores formatting.
          Matches are deduplicated and sorted by name before --limit (default 25).

        Output options:
          --json                         Emit structured JSON

        Create/update options:
          --given-name <name>
          --family-name <name>
          --organization <name>
          --job-title <title>
          --street <street>              Create/patch first address; multiline allowed
          --city <city>
          --state <state-or-region>
          --postal-code <code>
          --country <country>
          --address-label <label>        Default: home
          --url <label=value>            Repeatable (homepage, home, work, other)
          --photo <path>                 Local image file (e.g. JPEG or PNG)
          --phone <label=value>          Repeatable (home, work, mobile, iPhone, main)
          --email <label=value>          Repeatable (home, work, other)

        Update semantics:
          Omitted fields are preserved; scalar fields accept "" to clear.
          --phone/--email/--url replace their entire list when supplied.
          Address fields patch the first address; other addresses are preserved.
          --address-label changes that first address's label (not a selector).
          --clear <field>                Update only; repeatable:
                                         phone, email, url, photo, address
          Do not combine --clear with options setting the same field.

        Delete semantics:
          --yes is required for actual deletion, even in scripts/non-TTY use.
          --dry-run is read-only and takes precedence over --yes.

        Example:
          contactctl create --given-name Ada --family-name Lovelace \\
            --phone 'mobile=+44 20 1234 5678' --email 'work=ada@example.com'
        """)
    }
}
