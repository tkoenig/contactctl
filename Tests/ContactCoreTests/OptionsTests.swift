import Foundation
import Testing
@testable import ContactCore

func photoFixture() throws -> URL {
    try #require(Bundle.module.url(forResource: "photo", withExtension: "png", subdirectory: "Fixtures"))
}

struct OptionsTests {
    @Test func parsesAllCreateFields() throws {
        let options = try CreateOptions(arguments: [
            "--given-name", "Ada", "--family-name", "Lovelace", "--organization", "Engines",
            "--job-title", "Programmer", "--street", "1 Main St\nSuite 2",
            "--city", "London", "--state", "London", "--postal-code", "SW1A 1AA", "--country", "UK",
            "--address-label", "work", "--url", "homepage=https://example.com/?a=b",
            "--url", "work=https://work.example.com", "--phone", "mobile=123", "--phone", "home=456",
            "--email", "work=ada@example.com", "--json"
        ])
        #expect(options.givenName == "Ada" && options.familyName == "Lovelace" && options.organization == "Engines")
        #expect(options.jobTitle == "Programmer")
        #expect(options.hasAddress && options.addressLabel == "work")
        #expect(options.street == "1 Main St\nSuite 2" && options.city == "London" && options.state == "London")
        #expect(options.postalCode == "SW1A 1AA" && options.country == "UK")
        #expect(options.urls.count == 2 && options.urls[0].value == "https://example.com/?a=b")
        #expect(options.phones.count == 2 && options.emails.count == 1 && options.json)
        let minimal = try CreateOptions(arguments: ["--organization", "Example"])
        #expect(!minimal.hasAddress && minimal.addressLabel == "home")
        #expect(try minimal.loadPhoto() == nil)
        #expect(try CreateOptions(arguments: ["--given-name", "Ada", "--city", "London"]).hasAddress)
    }

    @Test func photoValidation() throws {
        let fixture = try photoFixture()
        let options = try CreateOptions(arguments: ["--given-name", "Ada", "--photo", fixture.path])
        #expect(try options.loadPhoto() == Data(contentsOf: fixture))
        for invalid in [#filePath, "/nonexistent-contactctl-\(UUID().uuidString).png"] {
            let invalidOptions = try CreateOptions(arguments: ["--given-name", "Ada", "--photo", invalid])
            #expect(throws: (any Error).self) { try invalidOptions.loadPhoto() }
        }
    }

    @Test(arguments: [
        [], ["--job-title", "Programmer"], ["--given-name", "Ada", "--job-title"],
        ["--given-name", "Ada", "--street", "--json"], ["--given-name", " "],
        ["--given-name", "Ada", "--url", "https://example.com"], ["--given-name", "Ada", "--url", "=https://example.com"],
        ["--given-name", "Ada", "--url", "work="], ["--given-name", "Ada", "--url", "work= "],
        ["--given-name", "Ada", "--address-label", "work"], ["--given-name", "Ada", "--photo", "--json"],
        ["--given-name", "Ada", "--unknown"]
    ])
    func invalidCreateArguments(arguments: [String]) {
        #expect(throws: (any Error).self) { try CreateOptions(arguments: arguments) }
    }

    @Test(arguments: [
        [], ["--json"], ["--clear", "unknown"], ["--clear", "phone", "--phone", "work=123"],
        ["--photo", "file.png", "--clear", "photo"], ["--clear", "address", "--city", "Wien"],
        ["--phone", ""], ["--photo", ""], ["--address-label", ""], ["--job-title", "--json"]
    ])
    func invalidUpdateArguments(arguments: [String]) {
        #expect(throws: (any Error).self) { try CreateOptions(arguments: arguments, updating: true) }
    }
}
