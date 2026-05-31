import Foundation
import ArgumentParser
import Darwin

func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func normalizedCredentialField(_ value: String, name: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        throw ValidationError("\(name) cannot be empty.")
    }
    return normalized
}

func readPasswordValue(_ password: String?, passwordStdin: Bool, prompt: String) throws -> String {
    try validatePasswordInputOptions(password, passwordStdin: passwordStdin)

    let value: String
    if let password {
        value = password
    } else if passwordStdin {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let string = String(data: input, encoding: .utf8) else {
            throw ValidationError("Password stdin must be valid UTF-8.")
        }
        value = string.trimmingTrailingNewlines()
    } else {
        guard let pointer = getpass(prompt) else {
            throw ValidationError("Could not read password.")
        }
        value = String(cString: pointer)
    }

    guard !value.isEmpty else {
        throw ValidationError("Password cannot be empty.")
    }
    return value
}

func validatePasswordInputOptions(_ password: String?, passwordStdin: Bool) throws {
    guard !(password != nil && passwordStdin) else {
        throw ValidationError("Use either --password or --password-stdin, not both.")
    }
    if let password, password.isEmpty {
        throw ValidationError("Password cannot be empty.")
    }
}

func readJSONValue(_ json: String?, jsonStdin: Bool) throws -> String {
    try readJSONValue(json, jsonStdin: jsonStdin, jsonFile: nil, allowJSONFile: false)
}

func readJSONValue(_ json: String?, jsonStdin: Bool, jsonFile: String?) throws -> String {
    try readJSONValue(json, jsonStdin: jsonStdin, jsonFile: jsonFile, allowJSONFile: true)
}

private func readJSONValue(_ json: String?, jsonStdin: Bool, jsonFile: String?, allowJSONFile: Bool) throws -> String {
    let providedSources = [
        json != nil,
        jsonStdin,
        allowJSONFile && jsonFile != nil,
    ].filter { $0 }.count

    guard providedSources <= 1 else {
        let choices = allowJSONFile ? "--json, --json-stdin, or --json-file" : "--json or --json-stdin"
        throw ValidationError("Use only one of \(choices).")
    }

    if let json {
        return json
    }

    if allowJSONFile, let jsonFile {
        let path = try normalizedCredentialField(jsonFile, name: "JSON file")
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ValidationError("Could not read JSON file '\(path)': \(error.localizedDescription)")
        }
    }

    if jsonStdin {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let string = String(data: input, encoding: .utf8) else {
            throw ValidationError("Secret JSON stdin must be valid UTF-8.")
        }
        return string
    }

    let choices = allowJSONFile ? "--json, --json-stdin, or --json-file" : "--json or --json-stdin"
    throw ValidationError("Provide secret JSON with \(choices).")
}

func parseSecretJSON(_ json: String) throws -> [String: Any] {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ValidationError("Secret JSON cannot be empty.")
    }
    guard let data = trimmed.data(using: .utf8) else {
        throw ValidationError("Secret JSON must be valid UTF-8.")
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ValidationError("Secret JSON is invalid: \(error.localizedDescription)")
    }

    guard let dictionary = object as? [String: Any] else {
        throw ValidationError("Secret JSON must be an object with key:value pairs.")
    }
    try validateSecretDictionary(dictionary)
    return dictionary
}

func secretJSONData(_ dictionary: [String: Any]) throws -> Data {
    try validateSecretDictionary(dictionary)
    do {
        return try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
    } catch {
        throw ValidationError("Could not encode secret JSON: \(error.localizedDescription)")
    }
}

func secretJSONString(_ dictionary: [String: Any]) throws -> String {
    guard let string = String(data: try secretJSONData(dictionary), encoding: .utf8) else {
        throw ValidationError("Could not encode secret JSON as UTF-8.")
    }
    return string
}

func secretDictionary(from data: Data) throws -> [String: Any] {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ValidationError("Stored secret JSON is invalid: \(error.localizedDescription)")
    }
    guard let dictionary = object as? [String: Any] else {
        throw ValidationError("Stored secret JSON is not an object.")
    }
    try validateSecretDictionary(dictionary)
    return dictionary
}

func secretValueString(_ value: Any) throws -> String {
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
    throw ValidationError("Secret values must be strings, numbers, booleans, or null.")
}

func shellExportLine(name: String, value: String) throws -> String {
    guard isValidEnvironmentName(name) else {
        throw ValidationError("Secret key '\(name)' is not a valid environment variable name.")
    }
    return "export \(name)=\(shellQuoted(value))"
}

private func validateSecretDictionary(_ dictionary: [String: Any]) throws {
    guard !dictionary.isEmpty else {
        throw ValidationError("Secret JSON must contain at least one key:value pair.")
    }

    for (key, value) in dictionary {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Secret JSON keys cannot be empty.")
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

extension String {
    fileprivate func trimmingTrailingNewlines() -> String {
        var result = self
        while result.last == "\n" || result.last == "\r" {
            result.removeLast()
        }
        return result
    }
}
