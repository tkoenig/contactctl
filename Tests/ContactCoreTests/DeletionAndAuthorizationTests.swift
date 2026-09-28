import Contacts
import Testing
@testable import ContactCore

private actor FakeDeletionStore: ContactDeletionStore {
    var reads: [String] = []
    var deletes: [String] = []
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }

    func show(identifier: String) throws -> ContactRecord {
        reads.append(identifier)
        if fail { throw FakeError.failed }
        return examplePerson
    }
    func delete(identifier: String) throws {
        deletes.append(identifier)
        if fail { throw FakeError.failed }
    }
    enum FakeError: Error { case failed }
}

struct DeletionAndAuthorizationTests {
    @Test(arguments: [[], ["id"], ["id", "--json"], ["--yes"], ["", "--yes"],
                      ["id", "second-id", "--yes"], ["id", "--force"], ["id", "--dry-run", "--bogus"]])
    func rejectsUnsafeDelete(arguments: [String]) {
        #expect(throws: (any Error).self) { try DeleteOptions(arguments: arguments) }
    }

    @Test(arguments: [["test-id", "--dry-run"], ["test-id", "--yes", "--dry-run", "--json"]])
    func previewNeverDeletes(arguments: [String]) async throws {
        let store = FakeDeletionStore()
        let result = try await ContactDeletion.perform(DeleteOptions(arguments: arguments), using: store)
        #expect(result == .preview(examplePerson))
        #expect(await store.reads == ["test-id"])
        #expect(await store.deletes.isEmpty)
    }

    @Test func confirmedDelete() async throws {
        let store = FakeDeletionStore()
        let options = try DeleteOptions(arguments: ["test-id", "--yes", "--json"])
        #expect(options.json && !options.dryRun)
        #expect(try await ContactDeletion.perform(options, using: store) == .deleted("test-id"))
        #expect(await store.reads.isEmpty)
        #expect(await store.deletes == ["test-id"])
    }

    @Test func previewErrorDoesNotDelete() async throws {
        let store = FakeDeletionStore(fail: true)
        let options = try DeleteOptions(arguments: ["test-id", "--dry-run", "--yes"])
        await #expect(throws: FakeDeletionStore.FakeError.self) {
            try await ContactDeletion.perform(options, using: store)
        }
        #expect(await store.deletes.isEmpty)
    }

    @Test func deletionErrorPropagates() async throws {
        let options = try DeleteOptions(arguments: ["test-id", "--yes"])
        await #expect(throws: FakeDeletionStore.FakeError.self) {
            try await ContactDeletion.perform(options, using: FakeDeletionStore(fail: true))
        }
    }

    @Test func authorizationMappingWithoutRequestingAccess() {
        #expect(ContactsAuthorization(status: .authorized).canAccess)
        #expect(!ContactsAuthorization(status: .denied).canAccess)
        #expect(ContactsAuthorization(status: .restricted) == .restricted)
        #expect(ContactsAuthorization(status: .notDetermined) == .notDetermined)
    }
}
