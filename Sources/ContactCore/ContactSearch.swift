import Foundation

/// Local matches supplement (rather than replace) the system's name search.
public struct ContactSearch {
    private let query: String
    private let phoneDigits: String?

    public init(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = Self.digits(in: self.query)
        let phoneCharacters = CharacterSet(charactersIn: "0123456789+()-./").union(.whitespacesAndNewlines)
        self.phoneDigits = !digits.isEmpty && self.query.unicodeScalars.allSatisfy(phoneCharacters.contains)
            ? digits : nil
    }

    public func matches(_ contact: ContactRecord) -> Bool {
        guard !query.isEmpty else { return false }
        let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return contains(name) || matchesAdditionalFields(contact)
    }

    private func contains(_ value: String) -> Bool {
        value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public func matchesAdditionalFields(_ contact: ContactRecord) -> Bool {
        guard !query.isEmpty else { return false }
        if contains(contact.organization) { return true }
        if contact.emailAddresses.contains(where: { contains($0.value) }) { return true }
        guard let phoneDigits else { return false }
        return contact.phoneNumbers.contains { Self.digits(in: $0.value).contains(phoneDigits) }
    }

    /// One result per unified identifier, deterministically sorted before limiting.
    public static func sortedUnique(_ matches: [ContactRecord], limit: Int) -> [ContactRecord] {
        var unique: [String: ContactRecord] = [:]
        for contact in matches where unique[contact.identifier] == nil {
            unique[contact.identifier] = contact
        }
        return Array(unique.values.sorted {
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return comparison == .orderedSame ? $0.identifier < $1.identifier : comparison == .orderedAscending
        }.prefix(max(0, limit)))
    }

    private static func digits(in value: String) -> String {
        String(value.filter { $0.isASCII && $0.isNumber })
    }
}
