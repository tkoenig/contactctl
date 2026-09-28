import Contacts
import Foundation

public enum ContactsAuthorization: String, Codable, Sendable {
    case notDetermined = "not determined"
    case restricted, denied, authorized, unknown

    public init(status: CNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        @unknown default: self = .unknown
        }
    }

    public var canAccess: Bool { self == .authorized }
}

/// Keeps framework objects inside one actor; callers only receive Sendable records.
public actor ContactsStore: ContactDeletionStore {
    private let store = CNContactStore()
    private let keys: [CNKeyDescriptor] = [
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

    public init() {}

    public static func authorizationStatus() -> ContactsAuthorization {
        ContactsAuthorization(status: CNContactStore.authorizationStatus(for: .contacts))
    }

    public func authorize() async throws -> Bool {
        switch Self.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
        default: return false
        }
    }

    private func ensureAccess() async throws {
        switch Self.authorizationStatus() {
        case .authorized: return
        case .notDetermined:
            guard try await authorize() else {
                throw StoreError("Contacts access was denied")
            }
        case .denied:
            throw StoreError("Contacts access is denied; enable it in System Settings > Privacy & Security > Contacts")
        case .restricted:
            throw StoreError("Contacts access is restricted by macOS")
        case .unknown:
            throw StoreError("Contacts access has an unsupported authorization state")
        }
    }

    public func search(query: String, limit: Int) async throws -> [ContactRecord] {
        try await ensureAccess()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = CNContact.predicateForContacts(matchingName: query)
        var matches = try store.unifiedContacts(matching: predicate, keysToFetch: keys).map { Self.record(from: $0) }
        let matcher = ContactSearch(query: query)
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        try store.enumerateContacts(with: request) { contact, _ in
            let candidate = Self.record(from: contact)
            if matcher.matches(candidate) { matches.append(candidate) }
        }
        return ContactSearch.sortedUnique(matches, limit: limit)
    }

    public func show(identifier: String) async throws -> ContactRecord {
        try await ensureAccess()
        return Self.record(from: try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys))
    }

    public func create(options: CreateOptions) async throws -> ContactRecord {
        let photo = try options.loadPhoto()
        try await ensureAccess()
        let contact = CNMutableContact()
        ContactMutation.apply(options, photo: photo, to: contact)
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return Self.record(from: contact, hasPhoto: photo != nil)
    }

    public func update(identifier: String, options: CreateOptions) async throws -> ContactRecord {
        let photo = try options.loadPhoto()
        try await ensureAccess()
        let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        guard let contact = existing.mutableCopy() as? CNMutableContact else {
            throw StoreError("could not obtain a mutable contact")
        }
        let hasPhoto = options.cleared.contains("photo") ? false : (photo != nil || existing.imageDataAvailable)
        ContactMutation.apply(options, photo: photo, to: contact)
        let request = CNSaveRequest()
        request.update(contact)
        try store.execute(request)
        return Self.record(from: contact, hasPhoto: hasPhoto)
    }

    public func delete(identifier: String) async throws {
        try await ensureAccess()
        let existing = try store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        guard let contact = existing.mutableCopy() as? CNMutableContact else {
            throw StoreError("could not obtain a mutable contact")
        }
        let request = CNSaveRequest()
        request.delete(contact)
        try store.execute(request)
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
}

private struct StoreError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
