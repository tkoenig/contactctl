import ContactCore
import Contacts
import Darwin
import Foundation

private enum CLIError: LocalizedError {
    case usage(String)
    case permission(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .permission(let message), .notFound(let message): message
        }
    }
}

private final class AccessResult: @unchecked Sendable {
    var granted = false
    var error: Error?
}

@main
@MainActor
struct ContactCLI {
    private static let store = CNContactStore()
    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor
    ]

    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("contactctl: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        let rest = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "version", "--version":
            print("contactctl 0.1.0")
        case "status":
            print(authorizationDescription(CNContactStore.authorizationStatus(for: .contacts)))
        case "authorize", "auth":
            let granted = try requestAccess()
            print(granted ? "authorized" : "denied")
            if !granted { exit(2) }
        case "search":
            try search(rest)
        case "show":
            try show(rest)
        case "create":
            try create(rest)
        case "update":
            try update(rest)
        case "delete":
            try delete(rest)
        default:
            throw CLIError.usage("unknown command '\(command)'; run 'contactctl help'")
        }
    }

    private static func search(_ arguments: [String]) throws {
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
                    throw CLIError.usage("--limit requires a positive integer")
                }
                limit = value
            default:
                guard !arguments[index].hasPrefix("-"), query == nil else {
                    throw CLIError.usage("usage: contactctl search <query> [--limit N] [--json]")
                }
                query = arguments[index]
            }
            index += 1
        }

        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.usage("usage: contactctl search <query> [--limit N] [--json]")
        }
        try ensureAccess()

        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            .prefix(limit)
            .map { record(from: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        if json {
            print(try ContactOutput.json(contacts))
        } else if contacts.isEmpty {
            print("No contacts found.")
        } else {
            print(contacts.map(ContactOutput.text).joined(separator: "\n\n"))
        }
    }

    private static func show(_ arguments: [String]) throws {
        let json = arguments.contains("--json")
        let positionals = arguments.filter { !$0.hasPrefix("-") }
        guard positionals.count == 1, arguments.allSatisfy({ $0 == "--json" || !$0.hasPrefix("-") }) else {
            throw CLIError.usage("usage: contactctl show <identifier> [--json]")
        }
        try ensureAccess()

        do {
            let contact = try store.unifiedContact(withIdentifier: positionals[0], keysToFetch: keys)
            let result = record(from: contact)
            print(json ? try ContactOutput.json(result) : ContactOutput.text(result))
        } catch {
            throw CLIError.notFound("contact '\(positionals[0])' was not found")
        }
    }

    private static func create(_ arguments: [String]) throws {
        let options = try CreateOptions(arguments: arguments)
        let photo = try options.loadPhoto()
        try ensureAccess()

        let contact = CNMutableContact()
        ContactMutation.apply(options, photo: photo, to: contact)

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)

        let result = record(from: contact, hasPhoto: photo != nil)
        print(options.json ? try ContactOutput.json(result) : ContactOutput.text(result))
    }

    private static func update(_ arguments: [String]) throws {
        guard let identifier = arguments.first, !identifier.hasPrefix("-"),
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.usage("usage: contactctl update <identifier> [field options] [--json]")
        }
        let options = try CreateOptions(arguments: Array(arguments.dropFirst()), updating: true)
        let photo = try options.loadPhoto()
        try ensureAccess()

        let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        guard let contact = existing.mutableCopy() as? CNMutableContact else {
            throw CLIError.usage("could not obtain a mutable contact")
        }
        let hasPhoto = options.cleared.contains("photo") ? false : (photo != nil || existing.imageDataAvailable)
        ContactMutation.apply(options, photo: photo, to: contact)
        let request = CNSaveRequest()
        request.update(contact)
        try store.execute(request)

        let result = record(from: contact, hasPhoto: hasPhoto)
        print(options.json ? try ContactOutput.json(result) : ContactOutput.text(result))
    }

    private static func delete(_ arguments: [String]) throws {
        let options = try DeleteOptions(arguments: arguments)
        try ensureAccess()
        let existing = try store.unifiedContact(withIdentifier: options.identifier, keysToFetch: [
            CNContactIdentifierKey as CNKeyDescriptor
        ])
        guard let contact = existing.mutableCopy() as? CNMutableContact else {
            throw CLIError.usage("could not obtain a mutable contact")
        }
        let request = CNSaveRequest()
        request.delete(contact)
        try store.execute(request)
        if options.json {
            print(try ContactOutput.json(["deleted": options.identifier]))
        } else {
            print("Deleted contact '\(options.identifier)'.")
        }
    }

    private static func record(from contact: CNContact, hasPhoto: Bool? = nil) -> ContactRecord {
        ContactRecord(
            identifier: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            organization: contact.organizationName,
            phoneNumbers: contact.phoneNumbers.map {
                ContactValue(label: localizedLabel($0.label), value: $0.value.stringValue)
            },
            emailAddresses: contact.emailAddresses.map {
                ContactValue(label: localizedLabel($0.label), value: $0.value as String)
            },
            jobTitle: contact.jobTitle,
            postalAddresses: contact.postalAddresses.map {
                ContactAddress(label: localizedLabel($0.label), street: $0.value.street,
                               city: $0.value.city, state: $0.value.state,
                               postalCode: $0.value.postalCode, country: $0.value.country)
            },
            urlAddresses: contact.urlAddresses.map {
                ContactValue(label: localizedLabel($0.label), value: $0.value as String)
            },
            hasPhoto: hasPhoto ?? contact.imageDataAvailable
        )
    }

    private static func localizedLabel(_ label: String?) -> String {
        guard let label else { return "other" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    private static func ensureAccess() throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return
        case .notDetermined:
            guard try requestAccess() else {
                throw CLIError.permission("Contacts access was denied")
            }
        case .denied:
            throw CLIError.permission("Contacts access is denied; enable it in System Settings > Privacy & Security > Contacts")
        case .restricted:
            throw CLIError.permission("Contacts access is restricted by macOS")
        @unknown default:
            throw CLIError.permission("Contacts access has an unsupported authorization state")
        }
    }

    private static func requestAccess() throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = AccessResult()
        store.requestAccess(for: .contacts) { granted, error in
            result.granted = granted
            result.error = error
            semaphore.signal()
        }
        semaphore.wait()
        if let error = result.error { throw error }
        return result.granted
    }

    private static func authorizationDescription(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private static func printHelp() {
        print("""
        Usage: contactctl <command> [options]

        Commands:
          status                         Show Contacts authorization status
          authorize                      Request Contacts authorization
          search <query> [--limit N]     Search contacts by name
          show <identifier>              Show one contact
          create [options]               Create a contact
          update <identifier> [options]  Update only supplied fields
          delete <identifier> --yes      Permanently delete a contact

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

        Example:
          contactctl create --given-name Ada --family-name Lovelace \\
            --phone 'mobile=+44 20 1234 5678' --email 'work=ada@example.com'
        """)
    }
}
