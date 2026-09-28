import Foundation
import Testing
@testable import ContactCore

let examplePerson = ContactRecord(
    identifier: "test-id", givenName: "Ada", familyName: "Lovelace", organization: "Analytical Engines",
    phoneNumbers: [.init(label: "mobile", value: "+1 555 0100")],
    emailAddresses: [.init(label: "work", value: "ada@example.com")], jobTitle: "Programmer",
    postalAddresses: [.init(label: "work", street: "1 Main St\nSuite 2", city: "London", state: "", postalCode: "SW1A 1AA", country: "UK")],
    urlAddresses: [.init(label: "homepage", value: "https://example.com/?a=b")], hasPhoto: true
)
let exampleOrganization = ContactRecord(identifier: "org-id", givenName: "", familyName: "", organization: "Example Corp", phoneNumbers: [], emailAddresses: [])

struct RecordAndSearchTests {
    @Test func displayNamesAndOutput() throws {
        #expect(examplePerson.displayName == "Ada Lovelace")
        #expect(exampleOrganization.displayName == "Example Corp")
        let json = try ContactOutput.json(examplePerson)
        #expect(try JSONDecoder().decode(ContactRecord.self, from: Data(json.utf8)) == examplePerson)
        let text = ContactOutput.text(examplePerson)
        #expect(text.contains("Job title: Programmer"))
        #expect(text.contains("Address (work): 1 Main St\nSuite 2, London, SW1A 1AA, UK"))
        #expect(text.contains("URL (homepage): https://example.com/?a=b"))
        #expect(text.contains("Photo: yes"))
        #expect(!ContactOutput.text(exampleOrganization).contains("Photo:"))
    }

    @Test(arguments: ["ADA@EXAMPLE.COM", "@example.com", "analytical", "  Engines \n", "+1 (555) 0100", "555-0100"])
    func additionalFieldsMatch(query: String) {
        #expect(ContactSearch(query: query).matchesAdditionalFields(examplePerson))
    }

    @Test(arguments: ["1555010099", "Ada 555", "+()-", " \n ", "unknown"])
    func additionalFieldsDoNotMatch(query: String) {
        #expect(!ContactSearch(query: query).matchesAdditionalFields(examplePerson))
    }

    @Test func accentInsensitiveSearch() {
        let accented = ContactRecord(identifier: "accent", givenName: "Renée", familyName: "Müller",
                                    organization: "Café Société", phoneNumbers: [],
                                    emailAddresses: [.init(label: "work", value: "renée@example.com")])
        for query in ["RENEE", "Muller", "renee muller", "cafe", "societe", "renee@example.com"] {
            #expect(ContactSearch(query: query).matches(accented))
        }
        #expect(!ContactSearch(query: " ").matches(accented))
        #expect(!ContactSearch(query: "123").matchesAdditionalFields(exampleOrganization))
    }

    @Test func searchDeduplicationAndLimit() {
        let sameName = ContactRecord(identifier: "aaa-id", givenName: "Ada", familyName: "Lovelace",
                                    organization: "", phoneNumbers: [], emailAddresses: [])
        #expect(ContactSearch.sortedUnique([examplePerson, examplePerson, sameName], limit: 10) == [sameName, examplePerson])
        let zed = ContactRecord(identifier: "zed", givenName: "Zed", familyName: "", organization: "", phoneNumbers: [], emailAddresses: [])
        #expect(ContactSearch.sortedUnique([zed, examplePerson, examplePerson], limit: 1) == [examplePerson])
        #expect(ContactSearch.sortedUnique([], limit: 25).isEmpty)
        #expect(ContactSearch.sortedUnique([examplePerson], limit: 0).isEmpty)
    }
}
