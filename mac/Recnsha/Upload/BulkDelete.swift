import Foundation

struct BulkDeleteResult: Equatable {
    var deleted: [String] = []
    /// Upload ID → error message.
    var failed: [String: String] = [:]
}

/// Deletes many uploads with the single-delete API.
enum BulkDelete {
    /// Deletes one upload at a time, carrying on after failures. An upload that is already gone counts as deleted.
    /// `progress` receives the number of uploads handled so far.
    static func run(ids: [String], using client: APIClient, progress: (Int) -> Void = { _ in }) async -> BulkDeleteResult {
        var result = BulkDeleteResult()
        for (index, id) in ids.enumerated() {
            do {
                try await client.delete(id: id)
                result.deleted.append(id)
            } catch APIError.server(status: 404, message: _) {
                result.deleted.append(id)
            } catch {
                result.failed[id] = error.localizedDescription
            }
            progress(index + 1)
        }
        return result
    }
}
