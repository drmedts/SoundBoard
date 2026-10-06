import Foundation

enum SessionStoreError: Error {
    case encodingFailed(Error)
    case decodingFailed(Error)
}

/// Saves and loads `Session` files. Sessions reference sound files by path rather
/// than embedding them — see [[soundboard-architecture-decisions]].
enum SessionStore {
    static let fileExtension = "sbx"

    static func save(_ session: Session, to url: URL) throws {
        var session = session
        session.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw SessionStoreError.encodingFailed(error)
        }

        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> Session {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(Session.self, from: data)
        } catch {
            throw SessionStoreError.decodingFailed(error)
        }
    }
}
