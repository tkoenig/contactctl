import Foundation
import ImageIO

public struct CreateOptions: Sendable {
    public var givenName = ""
    public var familyName = ""
    public var organization = ""
    public var jobTitle = ""
    public var street = ""
    public var city = ""
    public var state = ""
    public var postalCode = ""
    public var country = ""
    public var addressLabel = "home"
    public var phones: [ContactValue] = []
    public var emails: [ContactValue] = []
    public var urls: [ContactValue] = []
    public var photoPath: String?
    public var json = false
    public private(set) var provided: Set<String> = []
    public private(set) var cleared: Set<String> = []

    public static let addressFields: Set<String> = ["--street", "--city", "--state", "--postal-code", "--country", "--address-label"]

    public var hasAddress: Bool {
        [street, city, state, postalCode, country].contains { !$0.isEmpty }
    }

    public init(arguments: [String], updating: Bool = false) throws {
        var index = 0
        let scalarOptions: Set<String> = ["--given-name", "--family-name", "--organization", "--job-title", "--street", "--city", "--state", "--postal-code", "--country"]
        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw CreateOptionsError("\(option) requires a value")
            }
            let value = arguments[index + 1]
            guard (updating && scalarOptions.contains(option) && value.isEmpty)
                    || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CreateOptionsError("\(option) requires a non-empty value (update scalar fields accept an empty string to clear)")
            }
            return value
        }
        while index < arguments.count {
            let option = arguments[index]
            if option == "--json" {
                json = true
                index += 1
                continue
            }
            if option == "--clear", updating {
                let field = try value(after: option)
                guard ["phone", "email", "url", "photo", "address"].contains(field) else {
                    throw CreateOptionsError("--clear expects phone, email, url, photo, or address")
                }
                cleared.insert(field)
                index += 2
                continue
            }
            provided.insert(option)
            switch option {
            case "--given-name": givenName = try value(after: option)
            case "--family-name": familyName = try value(after: option)
            case "--organization": organization = try value(after: option)
            case "--job-title": jobTitle = try value(after: option)
            case "--street": street = try value(after: option)
            case "--city": city = try value(after: option)
            case "--state": state = try value(after: option)
            case "--postal-code": postalCode = try value(after: option)
            case "--country": country = try value(after: option)
            case "--address-label": addressLabel = try value(after: option)
            case "--phone": phones.append(try Self.labeledValue(value(after: option), option: option))
            case "--email": emails.append(try Self.labeledValue(value(after: option), option: option))
            case "--url": urls.append(try Self.labeledValue(value(after: option), option: option))
            case "--photo": photoPath = try value(after: option)
            default: throw CreateOptionsError("unknown \(updating ? "update" : "create") option '\(option)'; run 'contactctl help'")
            }
            index += 2
        }
        if updating {
            guard !provided.isEmpty || !cleared.isEmpty else {
                throw CreateOptionsError("update requires at least one field option or --clear")
            }
            for field in cleared {
                let conflicts = field == "address"
                    ? !provided.isDisjoint(with: Self.addressFields)
                    : provided.contains("--\(field)")
                if conflicts { throw CreateOptionsError("--clear \(field) cannot be combined with options setting that field") }
            }
        } else {
            guard !givenName.isEmpty || !familyName.isEmpty || !organization.isEmpty else {
                throw CreateOptionsError("create requires --given-name, --family-name, or --organization")
            }
            if provided.contains("--address-label") && !hasAddress {
                throw CreateOptionsError("--address-label requires at least one address field")
            }
        }
    }

    private static func labeledValue(_ input: String, option: String) throws -> ContactValue {
        guard let separator = input.firstIndex(of: "=") else {
            throw CreateOptionsError("\(option) must use label=value")
        }
        let label = String(input[..<separator])
        let value = String(input[input.index(after: separator)...])
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreateOptionsError("\(option) label and value cannot be empty")
        }
        return ContactValue(label: label, value: value)
    }

    /// Validate before requesting Contacts permission or saving anything.
    public func loadPhoto() throws -> Data? {
        guard let photoPath else { return nil }
        let path = (photoPath as NSString).expandingTildeInPath
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CreateOptionsError("cannot read --photo '\(photoPath)': \(error.localizedDescription)")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CreateOptionsError("--photo must be a readable image (for example JPEG or PNG)")
        }
        return data
    }
}

private struct CreateOptionsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
