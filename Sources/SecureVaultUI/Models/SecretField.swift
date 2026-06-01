import Foundation
import SecureVaultCore

struct SecretField: Equatable, Identifiable {
    let key: String
    let value: String

    var id: String { key }

    static func rows(from json: String) throws -> [SecretField] {
        let dictionary = try parseSecretJSON(json)
        let keys = dictionary.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        return try keys.map { key in
            SecretField(
                key: key,
                value: try secretValueString(dictionary[key] ?? NSNull())
            )
        }
    }
}
