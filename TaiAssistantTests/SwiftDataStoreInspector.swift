import Foundation
import SQLite3

enum SwiftDataStoreInspector {
    struct Metadata: Equatable {
        let versionIdentifier: String?
        let entityNames: [String]
    }

    static func entityNames(at storeURL: URL) throws -> [String] {
        try metadata(at: storeURL).entityNames
    }

    static func metadata(at storeURL: URL) throws -> Metadata {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "SwiftDataStoreInspector", code: 1)
        }
        defer { sqlite3_close(database) }

        let entityNames = try queryStrings(
            database: database,
            sql: "SELECT Z_NAME FROM Z_PRIMARYKEY WHERE Z_ENT < 16000 ORDER BY Z_ENT ASC;"
        )

        let metadataRows = try queryStrings(
            database: database,
            sql: "SELECT hex(Z_PLIST) FROM Z_METADATA LIMIT 1;"
        )

        let versionIdentifier = metadataRows.first.flatMap(parseVersionIdentifier(fromHex:))
        return Metadata(versionIdentifier: versionIdentifier, entityNames: entityNames)
    }

    private static func queryStrings(database: OpaquePointer?, sql: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "SwiftDataStoreInspector", code: 2)
        }
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                values.append(String(cString: cString))
            }
        }
        return values
    }

    private static func parseVersionIdentifier(fromHex hex: String) -> String? {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: Data(bytes),
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        if let identifiers = plist["NSStoreModelVersionIdentifiers"] as? [String] {
            return identifiers.first
        }
        return nil
    }
}
