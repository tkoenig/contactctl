import Contacts
import Foundation

/// Applies only explicitly supplied fields to an in-memory contact. Never accesses a store.
public enum ContactMutation {
    public static func apply(_ options: CreateOptions, photo: Data?, to contact: CNMutableContact) {
        if options.provided.contains("--given-name") { contact.givenName = options.givenName }
        if options.provided.contains("--family-name") { contact.familyName = options.familyName }
        if options.provided.contains("--organization") { contact.organizationName = options.organization }
        if options.provided.contains("--job-title") { contact.jobTitle = options.jobTitle }
        if options.provided.contains("--photo") { contact.imageData = photo }
        if options.cleared.contains("photo") { contact.imageData = nil }

        if options.provided.contains("--phone") {
            contact.phoneNumbers = options.phones.map {
                CNLabeledValue(label: label($0.label, phone: true), value: CNPhoneNumber(stringValue: $0.value))
            }
        }
        if options.provided.contains("--email") {
            contact.emailAddresses = options.emails.map {
                CNLabeledValue(label: label($0.label), value: $0.value as NSString)
            }
        }
        if options.provided.contains("--url") {
            contact.urlAddresses = options.urls.map {
                CNLabeledValue(label: $0.label.lowercased() == "homepage" ? CNLabelURLAddressHomePage : label($0.label),
                               value: $0.value as NSString)
            }
        }
        if options.cleared.contains("phone") { contact.phoneNumbers = [] }
        if options.cleared.contains("email") { contact.emailAddresses = [] }
        if options.cleared.contains("url") { contact.urlAddresses = [] }
        if options.cleared.contains("address") { contact.postalAddresses = [] }

        if !options.provided.isDisjoint(with: CreateOptions.addressFields) {
            // Patch the first address, preserving its other fields and all remaining addresses.
            var addresses = contact.postalAddresses
            let original = addresses.first
            let address = original?.value.mutableCopy() as? CNMutablePostalAddress ?? CNMutablePostalAddress()
            if options.provided.contains("--street") { address.street = options.street }
            if options.provided.contains("--city") { address.city = options.city }
            if options.provided.contains("--state") { address.state = options.state }
            if options.provided.contains("--postal-code") { address.postalCode = options.postalCode }
            if options.provided.contains("--country") {
                address.country = options.country
                // A previously stored ISO code must not contradict a newly supplied country.
                address.isoCountryCode = ""
            }
            let addressLabel = options.provided.contains("--address-label")
                ? label(options.addressLabel) : (original?.label ?? CNLabelHome)
            if let original {
                addresses[0] = original.settingLabel(addressLabel, value: address)
            } else {
                addresses.append(CNLabeledValue(label: addressLabel, value: address))
            }
            contact.postalAddresses = addresses
        }
    }

    private static func label(_ input: String, phone: Bool = false) -> String {
        switch input.lowercased() {
        case "home": return CNLabelHome
        case "work": return CNLabelWork
        case "other": return CNLabelOther
        case "mobile" where phone: return CNLabelPhoneNumberMobile
        case "iphone" where phone: return CNLabelPhoneNumberiPhone
        case "main" where phone: return CNLabelPhoneNumberMain
        default: return input
        }
    }
}

/// Only read-only previews may omit explicit confirmation.
public struct DeleteOptions: Sendable {
    public let identifier: String
    public let json: Bool
    public let dryRun: Bool

    public init(arguments: [String]) throws {
        guard let identifier = arguments.first, !identifier.hasPrefix("-"),
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              arguments.dropFirst().allSatisfy({ ["--yes", "--json", "--dry-run"].contains($0) }),
              (arguments.dropFirst().contains("--yes") || arguments.dropFirst().contains("--dry-run")) else {
            throw DeleteOptionsError()
        }
        self.identifier = identifier
        self.json = arguments.dropFirst().contains("--json")
        self.dryRun = arguments.dropFirst().contains("--dry-run")
    }
}

private struct DeleteOptionsError: LocalizedError {
    var errorDescription: String? { "usage: contactctl delete <identifier> (--yes | --dry-run) [--json] (--yes permanently deletes; --dry-run only previews)" }
}
