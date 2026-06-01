import Foundation

public struct VaultValidationError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public func normalizedVaultField(_ value: String, name: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        throw VaultValidationError("\(name) cannot be empty.")
    }
    return normalized
}

public func parseSecretJSON(_ json: String) throws -> [String: Any] {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw VaultValidationError("Secret JSON cannot be empty.")
    }
    guard let data = trimmed.data(using: .utf8) else {
        throw VaultValidationError("Secret JSON must be valid UTF-8.")
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw VaultValidationError("Secret JSON is invalid: \(error.localizedDescription)")
    }

    guard let dictionary = object as? [String: Any] else {
        throw VaultValidationError("Secret JSON must be an object with key:value pairs.")
    }
    try validateSecretDictionary(dictionary)
    return dictionary
}

public func secretJSONData(_ dictionary: [String: Any], prettyPrinted: Bool = false) throws -> Data {
    try validateSecretDictionary(dictionary)
    var options: JSONSerialization.WritingOptions = [.sortedKeys]
    if prettyPrinted {
        options.insert(.prettyPrinted)
        if #available(macOS 10.13, *) {
            options.insert(.withoutEscapingSlashes)
        }
    }

    do {
        return try JSONSerialization.data(withJSONObject: dictionary, options: options)
    } catch {
        throw VaultValidationError("Could not encode secret JSON: \(error.localizedDescription)")
    }
}

public func secretJSONString(_ dictionary: [String: Any], prettyPrinted: Bool = false) throws -> String {
    guard let string = String(data: try secretJSONData(dictionary, prettyPrinted: prettyPrinted), encoding: .utf8) else {
        throw VaultValidationError("Could not encode secret JSON as UTF-8.")
    }
    return string
}

public func secretDictionary(from data: Data) throws -> [String: Any] {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw VaultValidationError("Stored secret JSON is invalid: \(error.localizedDescription)")
    }
    guard let dictionary = object as? [String: Any] else {
        throw VaultValidationError("Stored secret JSON is not an object.")
    }
    try validateSecretDictionary(dictionary)
    return dictionary
}

public func secretValueString(_ value: Any) throws -> String {
    if let string = value as? String {
        return string
    }
    if value is NSNull {
        return ""
    }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        return number.stringValue
    }
    throw VaultValidationError("Secret values must be strings, numbers, booleans, or null.")
}

public func shellExportLine(name: String, value: String) throws -> String {
    guard isValidEnvironmentName(name) else {
        throw VaultValidationError("Secret key '\(name)' is not a valid environment variable name.")
    }
    return "export \(name)=\(shellQuoted(value))"
}

private func validateSecretDictionary(_ dictionary: [String: Any]) throws {
    guard !dictionary.isEmpty else {
        throw VaultValidationError("Secret JSON must contain at least one key:value pair.")
    }

    for (key, value) in dictionary {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VaultValidationError("Secret JSON keys cannot be empty.")
        }
        _ = try secretValueString(value)
    }
}

private func isValidEnvironmentName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first else { return false }
    guard first == "_" || CharacterSet.letters.contains(first) else { return false }
    return name.unicodeScalars.dropFirst().allSatisfy { scalar in
        scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
    }
}

private func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
