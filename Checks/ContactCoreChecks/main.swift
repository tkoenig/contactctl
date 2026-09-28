import ContactCore
import Contacts
import Darwin
import Foundation

private var failures = 0

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

let person = ContactRecord(
    identifier: "test-id",
    givenName: "Ada",
    familyName: "Lovelace",
    organization: "Analytical Engines",
    phoneNumbers: [.init(label: "mobile", value: "+1 555 0100")],
    emailAddresses: [.init(label: "work", value: "ada@example.com")],
    jobTitle: "Programmer",
    postalAddresses: [.init(label: "work", street: "1 Main St\nSuite 2", city: "London", state: "", postalCode: "SW1A 1AA", country: "UK")],
    urlAddresses: [.init(label: "homepage", value: "https://example.com/?a=b")],
    hasPhoto: true
)
expect(person.displayName == "Ada Lovelace", "person display name")

let organization = ContactRecord(
    identifier: "test-id",
    givenName: "",
    familyName: "",
    organization: "Example Corp",
    phoneNumbers: [],
    emailAddresses: []
)
expect(organization.displayName == "Example Corp", "organization display name fallback")

do {
    let json = try ContactOutput.json(person)
    let decoded = try JSONDecoder().decode(ContactRecord.self, from: Data(json.utf8))
    expect(decoded == person, "JSON round trip")
} catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: JSON round trip threw \(error)\n".utf8))
}

let text = ContactOutput.text(person)
expect(text.contains("Job title: Programmer"), "text job title")
expect(text.contains("Address (work): 1 Main St\nSuite 2, London, SW1A 1AA, UK"), "text address")
expect(text.contains("URL (homepage): https://example.com/?a=b"), "text URL")
expect(text.contains("Photo: yes"), "text photo indicator")
expect(!ContactOutput.text(organization).contains("Photo:"), "no photo indicator when absent")

do {
    let options = try CreateOptions(arguments: [
        "--given-name", "Ada", "--family-name", "Lovelace", "--organization", "Engines",
        "--job-title", "Programmer", "--street", "1 Main St\nSuite 2",
        "--city", "London", "--state", "London", "--postal-code", "SW1A 1AA", "--country", "UK",
        "--address-label", "work", "--url", "homepage=https://example.com/?a=b",
        "--url", "work=https://work.example.com", "--phone", "mobile=123", "--phone", "home=456",
        "--email", "work=ada@example.com", "--json"
    ])
    expect(options.jobTitle == "Programmer", "parse job title")
    expect(options.hasAddress && options.addressLabel == "work", "parse address label")
    expect(options.street == "1 Main St\nSuite 2" && options.city == "London" && options.state == "London"
           && options.postalCode == "SW1A 1AA" && options.country == "UK", "parse address fields")
    expect(options.urls.count == 2 && options.urls[0].value == "https://example.com/?a=b", "repeatable URLs preserve equals")
    expect(options.phones.count == 2 && options.emails.count == 1 && options.json, "existing options")
    let minimal = try CreateOptions(arguments: ["--organization", "Example"])
    expect(!minimal.hasAddress && minimal.addressLabel == "home", "address defaults")
    let noPhoto = try minimal.loadPhoto()
    expect(noPhoto == nil, "no photo by default")
    let partial = try CreateOptions(arguments: ["--given-name", "Ada", "--city", "London"])
    expect(partial.hasAddress, "partial address supported")

    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/photo.png")
    let withPhoto = try CreateOptions(arguments: ["--given-name", "Ada", "--photo", fixture.path])
    let loadedPhoto = try withPhoto.loadPhoto()
    let expectedPhoto = try Data(contentsOf: fixture)
    expect(loadedPhoto == expectedPhoto, "valid photo loaded unchanged")
} catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: options/photo checks threw \(error)\n".utf8))
}

for invalid in [
    [], ["--job-title", "Programmer"], ["--given-name", "Ada", "--job-title"],
    ["--given-name", "Ada", "--street", "--json"], ["--given-name", " "],
    ["--given-name", "Ada", "--url", "https://example.com"],
    ["--given-name", "Ada", "--url", "=https://example.com"],
    ["--given-name", "Ada", "--url", "work="],
    ["--given-name", "Ada", "--url", "work= "],
    ["--given-name", "Ada", "--address-label", "work"],
    ["--given-name", "Ada", "--photo", "--json"],
    ["--given-name", "Ada", "--unknown"]
] {
    do {
        _ = try CreateOptions(arguments: invalid)
        expect(false, "reject invalid arguments: \(invalid)")
    } catch { /* expected */ }
}

for invalidPhoto in [#filePath, "/nonexistent-contactctl-\(UUID().uuidString).png"] {
    do {
        let options = try CreateOptions(arguments: ["--given-name", "Ada", "--photo", invalidPhoto])
        _ = try options.loadPhoto()
        expect(false, "reject unreadable/non-image photo")
    } catch { /* expected */ }
}

// In-memory Contacts objects only: no CNContactStore or authorization requests.
do {
    let contact = CNMutableContact()
    contact.givenName = "Original"
    contact.familyName = "Person"
    contact.organizationName = "Company"
    contact.jobTitle = "Old title"
    contact.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "123"))]
    contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "old@example.com" as NSString)]
    contact.urlAddresses = [CNLabeledValue(label: CNLabelHome, value: "https://old.example.com" as NSString)]
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/photo.png")
    let photo = try Data(contentsOf: fixture)
    contact.imageData = photo
    let address = CNMutablePostalAddress()
    address.street = "Old Street"
    address.city = "London"
    address.state = "Region"
    address.postalCode = "Old Code"
    address.country = "United Kingdom"
    address.isoCountryCode = "GB"
    contact.postalAddresses = [
        CNLabeledValue(label: CNLabelHome, value: address),
        CNLabeledValue(label: CNLabelOther, value: CNPostalAddress())
    ]
    let originalAddressID = contact.postalAddresses[0].identifier
    let secondAddress = contact.postalAddresses[1]
    let originalPhone = contact.phoneNumbers[0]
    let update = try CreateOptions(arguments: [
        "--job-title", "Grundstücksmanagerin", "--street", "Wagramer Straße 19",
        "--city", "Wien", "--postal-code", "1220", "--country", "AT", "--address-label", "work",
        "--url", "homepage=www.apg.at"
    ], updating: true)
    ContactMutation.apply(update, photo: nil, to: contact)
    expect(contact.givenName == "Original" && contact.familyName == "Person" && contact.organizationName == "Company", "update preserves names/org")
    expect(contact.phoneNumbers[0] == originalPhone && contact.emailAddresses.count == 1, "update preserves omitted lists")
    expect(contact.imageData == photo, "update preserves omitted photo")
    expect(contact.jobTitle == "Grundstücksmanagerin", "update title")
    expect(contact.urlAddresses.count == 1 && contact.urlAddresses[0].value == "www.apg.at"
           && contact.urlAddresses[0].label == CNLabelURLAddressHomePage, "update replaces URL list")
    expect(contact.postalAddresses.count == 2 && contact.postalAddresses[1] == secondAddress, "update preserves additional addresses")
    let patched = contact.postalAddresses[0]
    expect(patched.identifier == originalAddressID && patched.label == CNLabelWork, "patch preserves address identity and changes label")
    expect(patched.value.street == "Wagramer Straße 19" && patched.value.city == "Wien"
           && patched.value.postalCode == "1220" && patched.value.country == "AT", "patch address fields")
    expect(patched.value.state == "Region" && patched.value.isoCountryCode.isEmpty, "preserve omitted address fields; clear stale ISO code")

    let clear = try CreateOptions(arguments: ["--street", "", "--job-title", "", "--clear", "phone",
        "--clear", "email", "--clear", "url", "--clear", "photo"], updating: true)
    ContactMutation.apply(clear, photo: nil, to: contact)
    expect(contact.jobTitle.isEmpty && contact.postalAddresses[0].value.street.isEmpty, "empty update scalar clears")
    expect(contact.postalAddresses[0].value.city == "Wien", "scalar clear preserves other address fields")
    expect(contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty && contact.urlAddresses.isEmpty
           && contact.imageData == nil, "clear collections and photo")
    let photoOptions = try CreateOptions(arguments: ["--photo", fixture.path], updating: true)
    ContactMutation.apply(photoOptions, photo: try photoOptions.loadPhoto(), to: contact)
    expect(contact.imageData == photo, "attach photo to existing contact")
    ContactMutation.apply(try CreateOptions(arguments: ["--clear", "address"], updating: true), photo: nil, to: contact)
    expect(contact.postalAddresses.isEmpty, "clear all addresses")
    ContactMutation.apply(try CreateOptions(arguments: ["--city", "Vienna"], updating: true), photo: nil, to: contact)
    expect(contact.postalAddresses.count == 1 && contact.postalAddresses[0].label == CNLabelHome, "update creates missing address")
    ContactMutation.apply(try CreateOptions(arguments: ["--phone", "work=456", "--phone", "mobile=789"], updating: true), photo: nil, to: contact)
    expect(contact.phoneNumbers.count == 2 && contact.phoneNumbers[1].label == CNLabelPhoneNumberMobile, "update replaces phone list")

    let created = CNMutableContact()
    ContactMutation.apply(try CreateOptions(arguments: ["--given-name", "Ada", "--city", "London"]), photo: nil, to: created)
    expect(created.givenName == "Ada" && created.postalAddresses[0].value.city == "London", "shared create mutation")
    let deletion = try DeleteOptions(arguments: ["synthetic-id", "--yes", "--json"])
    expect(deletion.identifier == "synthetic-id" && deletion.json, "confirmed delete parsing")
} catch {
    failures += 1
    FileHandle.standardError.write(Data("FAIL: mutation checks threw \(error)\n".utf8))
}

for invalid in [[], ["--json"], ["--clear", "unknown"], ["--clear", "phone", "--phone", "work=123"],
                ["--photo", "file.png", "--clear", "photo"], ["--clear", "address", "--city", "Wien"],
                ["--phone", ""], ["--photo", ""], ["--address-label", ""], ["--job-title", "--json"]] {
    do {
        _ = try CreateOptions(arguments: invalid, updating: true)
        expect(false, "reject invalid update: \(invalid)")
    } catch { /* expected */ }
}
for invalid in [[], ["synthetic-id"], ["synthetic-id", "--json"], ["--yes"], ["", "--yes"],
                ["synthetic-id", "second-id", "--yes"], ["synthetic-id", "--force"]] {
    do {
        _ = try DeleteOptions(arguments: invalid)
        expect(false, "reject unsafe delete: \(invalid)")
    } catch { /* expected */ }
}

if failures == 0 {
    print("All synthetic checks passed.")
} else {
    exit(1)
}
