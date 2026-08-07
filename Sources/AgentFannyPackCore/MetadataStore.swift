import Foundation

public protocol StateStoring {
    func load() throws -> PersistedState
    func save(_ state: PersistedState) throws
}

public struct MetadataStore: StateStoring {
    public static let maximumProfiles = 32
    public static let maximumSnapshotsPerProfile = 8
    public static let maximumSnapshotsTotal = 128

    public let fileURL: URL

    public init(fileURL: URL = MetadataStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("Agent Fanny Pack", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    public func load() throws -> PersistedState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return PersistedState() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.fannyPack.decode(PersistedState.self, from: data)
    }

    public func save(_ state: PersistedState) throws {
        let bounded = Self.bounded(state)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.fannyPack.encode(bounded)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public static func bounded(_ state: PersistedState) -> PersistedState {
        var result = state
        result.schemaVersion = PersistedState.currentSchemaVersion
        result.profiles = Array(result.profiles.prefix(maximumProfiles))
        let validIDs = Set(result.profiles.map(\.id))
        result.activeProfileBySurface = result.activeProfileBySurface.filter { validIDs.contains($0.value) }

        let persistable = result.snapshots.filter {
            validIDs.contains($0.profileID) && $0.source != .syntheticPreview
        }
        var counts: [String: Int] = [:]
        let newest = persistable.sorted { $0.fetchedAt > $1.fetchedAt }.filter { snapshot in
            let count = counts[snapshot.profileID, default: 0]
            guard count < maximumSnapshotsPerProfile else { return false }
            counts[snapshot.profileID] = count + 1
            return true
        }
        result.snapshots = Array(newest.prefix(maximumSnapshotsTotal))
        return result
    }
}

private extension JSONEncoder {
    static var fannyPack: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var fannyPack: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
