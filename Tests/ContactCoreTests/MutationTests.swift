import Contacts
import Foundation
import Testing
@testable import ContactCore

struct MutationTests {
    // Framework objects are in-memory only. No CNContactStore or authorization calls.
    @Test func patchPreservesOmittedFields() throws {
        let contact = CNMutableContact()
        contact.givenName = "Original"
        contact.familyName = "Person"
        contact.organizationName = "Company"
        contact.jobTitle = "Old title"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "123"))]
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "old@example.com" as NSString)]
        contact.urlAddresses = [CNLabeledValue(label: CNLabelHome, value: "https://old.example.com" as NSString)]
        let photo = try Data(contentsOf: photoFixture())
        contact.imageData = photo
        let address = CNMutablePostalAddress()
        address.street = "Old Street"
        address.city = "London"
        address.state = "Region"
        address.postalCode = "Old Code"
        address.country = "United Kingdom"
        address.isoCountryCode = "GB"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address),
                                   CNLabeledValue(label: CNLabelOther, value: CNPostalAddress())]
        let originalAddressID = contact.postalAddresses[0].identifier
        let secondAddress = contact.postalAddresses[1]
        let originalPhone = contact.phoneNumbers[0]
        let options = try CreateOptions(arguments: [
            "--job-title", "Engineer", "--street", "1 Example Street", "--city", "Wien",
            "--postal-code", "1010", "--country", "AT", "--address-label", "work",
            "--url", "homepage=https://example.com"
        ], updating: true)
        ContactMutation.apply(options, photo: nil, to: contact)
        #expect(contact.givenName == "Original" && contact.familyName == "Person" && contact.organizationName == "Company")
        #expect(contact.phoneNumbers[0] == originalPhone && contact.emailAddresses[0].value == "old@example.com")
        #expect(contact.imageData == photo)
        #expect(contact.jobTitle == "Engineer")
        #expect(contact.urlAddresses.count == 1 && contact.urlAddresses[0].value == "https://example.com")
        #expect(contact.urlAddresses[0].label == CNLabelURLAddressHomePage)
        #expect(contact.postalAddresses.count == 2 && contact.postalAddresses[1] == secondAddress)
        let patched = contact.postalAddresses[0]
        #expect(patched.identifier == originalAddressID && patched.label == CNLabelWork)
        #expect(patched.value.street == "1 Example Street" && patched.value.city == "Wien")
        #expect(patched.value.postalCode == "1010" && patched.value.country == "AT")
        #expect(patched.value.state == "Region" && patched.value.isoCountryCode.isEmpty)

        let clear = try CreateOptions(arguments: ["--street", "", "--job-title", "", "--clear", "phone",
            "--clear", "email", "--clear", "url", "--clear", "photo"], updating: true)
        ContactMutation.apply(clear, photo: nil, to: contact)
        #expect(contact.jobTitle.isEmpty && contact.postalAddresses[0].value.street.isEmpty)
        #expect(contact.postalAddresses[0].value.city == "Wien")
        #expect(contact.phoneNumbers.isEmpty && contact.emailAddresses.isEmpty && contact.urlAddresses.isEmpty)
        #expect(contact.imageData == nil)
    }

    @Test func replacesPhotoAndLists() throws {
        let contact = CNMutableContact()
        let fixture = try photoFixture()
        let options = try CreateOptions(arguments: ["--photo", fixture.path], updating: true)
        ContactMutation.apply(options, photo: try options.loadPhoto(), to: contact)
        #expect(try contact.imageData == Data(contentsOf: fixture))
        ContactMutation.apply(try CreateOptions(arguments: ["--city", "Vienna"], updating: true), photo: nil, to: contact)
        #expect(contact.postalAddresses.count == 1 && contact.postalAddresses[0].label == CNLabelHome)
        ContactMutation.apply(try CreateOptions(arguments: ["--clear", "address"], updating: true), photo: nil, to: contact)
        #expect(contact.postalAddresses.isEmpty)
        ContactMutation.apply(try CreateOptions(arguments: ["--phone", "work=456", "--phone", "mobile=789"], updating: true), photo: nil, to: contact)
        #expect(contact.phoneNumbers.count == 2 && contact.phoneNumbers[1].label == CNLabelPhoneNumberMobile)
        ContactMutation.apply(try CreateOptions(arguments: ["--phone", "home=100"], updating: true), photo: nil, to: contact)
        #expect(contact.phoneNumbers.count == 1 && contact.phoneNumbers[0].value.stringValue == "100")
    }

    @Test func sharedCreateMutation() throws {
        let contact = CNMutableContact()
        ContactMutation.apply(try CreateOptions(arguments: ["--given-name", "Ada", "--city", "London"]), photo: nil, to: contact)
        #expect(contact.givenName == "Ada" && contact.postalAddresses[0].value.city == "London")
    }
}
