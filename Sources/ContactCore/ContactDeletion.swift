public protocol ContactDeletionStore: Sendable {
    func show(identifier: String) async throws -> ContactRecord
    func delete(identifier: String) async throws
}

public enum ContactDeletionResult: Equatable, Sendable {
    case preview(ContactRecord)
    case deleted(String)
}

public enum ContactDeletion {
    /// Dry-run always wins, even if --yes was also supplied.
    public static func perform(_ options: DeleteOptions, using store: any ContactDeletionStore) async throws -> ContactDeletionResult {
        if options.dryRun {
            return .preview(try await store.show(identifier: options.identifier))
        }
        // DeleteOptions can only be constructed without dry-run when --yes was supplied.
        try await store.delete(identifier: options.identifier)
        return .deleted(options.identifier)
    }
}
