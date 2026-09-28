import Foundation

public struct ContactValue: Codable, Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ContactAddress: Codable, Equatable, Sendable {
    public let label: String
    public let street: String
    public let city: String
    public let state: String
    public let postalCode: String
    public let country: String

    public init(label: String, street: String, city: String, state: String, postalCode: String, country: String) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}

public struct ContactRecord: Codable, Equatable, Sendable {
    public let identifier: String
    public let givenName: String
    public let familyName: String
    public let organization: String
    public let phoneNumbers: [ContactValue]
    public let emailAddresses: [ContactValue]
    public let jobTitle: String
    public let postalAddresses: [ContactAddress]
    public let urlAddresses: [ContactValue]
    public let hasPhoto: Bool

    public init(
        identifier: String,
        givenName: String,
        familyName: String,
        organization: String,
        phoneNumbers: [ContactValue],
        emailAddresses: [ContactValue],
        jobTitle: String = "",
        postalAddresses: [ContactAddress] = [],
        urlAddresses: [ContactValue] = [],
        hasPhoto: Bool = false
    ) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.jobTitle = jobTitle
        self.postalAddresses = postalAddresses
        self.urlAddresses = urlAddresses
        self.hasPhoto = hasPhoto
    }

    public var displayName: String {
        let personName = [givenName, familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !personName.isEmpty { return personName }
        if !organization.isEmpty { return organization }
        return "Unnamed contact"
    }
}

public enum ContactOutput {
    public static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func text(_ contact: ContactRecord) -> String {
        var lines = [contact.displayName, "  ID: \(contact.identifier)"]
        if !contact.organization.isEmpty && contact.organization != contact.displayName {
            lines.append("  Organization: \(contact.organization)")
        }
        if !contact.jobTitle.isEmpty { lines.append("  Job title: \(contact.jobTitle)") }
        lines += contact.phoneNumbers.map { "  Phone (\($0.label)): \($0.value)" }
        lines += contact.emailAddresses.map { "  Email (\($0.label)): \($0.value)" }
        lines += contact.urlAddresses.map { "  URL (\($0.label)): \($0.value)" }
        for address in contact.postalAddresses {
            let parts = [address.street, address.city, address.state, address.postalCode, address.country]
                .filter { !$0.isEmpty }
            lines.append("  Address (\(address.label)): \(parts.joined(separator: ", "))")
        }
        if contact.hasPhoto { lines.append("  Photo: yes") }
        return lines.joined(separator: "\n")
    }
}
