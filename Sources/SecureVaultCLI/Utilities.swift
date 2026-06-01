import Foundation
import ArgumentParser
import Darwin
import SecureVaultCore

func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func normalizedCredentialField(_ value: String, name: String) throws -> String {
    try normalizedVaultField(value, name: name)
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

extension String {
    fileprivate func trimmingTrailingNewlines() -> String {
        var result = self
        while result.last == "\n" || result.last == "\r" {
            result.removeLast()
        }
        return result
    }
}
