import ArgumentParser
import Foundation

struct MakeSecretCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "make-secret",
        abstract: "Store an encrypted JSON secret. Requires Touch ID or Apple Watch."
    )

    @Option(name: .long, help: "Secret name.")
    var name: String

    @Option(name: .long, help: "Secret JSON object with scalar key:value pairs.")
    var json: String?

    @Flag(name: .long, help: "Read the secret JSON from stdin.")
    var jsonStdin: Bool = false

    @Option(name: .long, help: "Read the secret JSON from a file.")
    var jsonFile: String?

    @Option(name: .long, help: "Secure Enclave key tag to use. Created automatically if missing.")
    var tag: String = SecureEnclaveManager.defaultPasswordKeyTag

    func run() throws {
        let name = try normalizedCredentialField(name, name: "Secret name")
        let secret = try parseSecretJSON(readJSONValue(json, jsonStdin: jsonStdin, jsonFile: jsonFile))
        let store = try CredentialStore()

        guard !store.secretExists(name: name) else {
            throw CredentialStoreError.secretAlreadyExists(name)
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Store secret \(name)")

        _ = try SecureEnclaveManager.ensureKey(tag: tag, label: "Secure Vault password and secret key")
        let ciphertext = try SecureEnclaveManager.encrypt(data: try secretJSONData(secret), tag: tag)
        try store.insertSecret(SecretRecord(name: name, keyTag: tag, ciphertext: ciphertext))

        print("Secret '\(name)' stored.")
    }
}

struct UpdateSecretCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-secret",
        abstract: "Merge JSON key:value updates into an existing secret. Requires Touch ID or Apple Watch only if the secret exists."
    )

    @Option(name: .long, help: "Secret name.")
    var name: String

    @Option(name: .long, help: "JSON object containing key:value pairs to update.")
    var json: String?

    @Flag(name: .long, help: "Read the update JSON from stdin.")
    var jsonStdin: Bool = false

    func run() throws {
        let name = try normalizedCredentialField(name, name: "Secret name")
        let updates = try parseSecretJSON(readJSONValue(json, jsonStdin: jsonStdin))
        let store = try CredentialStore()
        let record = try store.secret(name: name)

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Update secret \(name)"
        )

        var secret = try secretDictionary(from: plaintext)
        for (key, value) in updates {
            secret[key] = value
        }

        let ciphertext = try SecureEnclaveManager.encrypt(data: try secretJSONData(secret), tag: record.keyTag)
        try store.updateSecret(name: name, ciphertext: ciphertext)

        print("Secret '\(name)' updated.")
    }
}

struct GetSecretCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-secret",
        abstract: "Decrypt and print a secret JSON object or one key value. Requires Touch ID or Apple Watch only if the secret exists."
    )

    @Option(name: .long, help: "Secret name.")
    var name: String

    @Option(name: .long, help: "Specific key to print from the secret JSON.")
    var key: String?

    func run() throws {
        let name = try normalizedCredentialField(name, name: "Secret name")
        let key = try key.map { try normalizedCredentialField($0, name: "Secret key") }

        let record = try CredentialStore().secret(name: name)

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Reveal secret \(name)"
        )

        let secret = try secretDictionary(from: plaintext)
        if let key {
            guard let value = secret[key] else {
                throw ValidationError("Secret '\(name)' does not contain key '\(key)'.")
            }
            print(try secretValueString(value), terminator: "")
        } else {
            print(try secretJSONString(secret), terminator: "")
        }
    }
}

struct DeleteSecretCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-secret",
        abstract: "Delete an existing secret. Requires Touch ID or Apple Watch only if the secret exists."
    )

    @Option(name: .long, help: "Secret name.")
    var name: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var force: Bool = false

    func run() throws {
        let name = try normalizedCredentialField(name, name: "Secret name")
        let store = try CredentialStore()
        _ = try store.secret(name: name)

        if !force {
            print("Delete secret '\(name)'? This is irreversible. [y/N] ", terminator: "")
            let reply = readLine()?.lowercased() ?? ""
            guard reply == "y" || reply == "yes" else {
                print("Cancelled.")
                return
            }
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Delete secret \(name)")
        try store.deleteSecret(name: name)

        print("Secret '\(name)' deleted.")
    }
}

struct ApplySecretCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply-secret",
        abstract: "Decrypt a secret and print shell exports for each key:value pair. Requires Touch ID or Apple Watch only if the secret exists."
    )

    @Option(name: .long, help: "Secret name.")
    var name: String

    func run() throws {
        let name = try normalizedCredentialField(name, name: "Secret name")
        let record = try CredentialStore().secret(name: name)

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Apply secret \(name)"
        )

        let secret = try secretDictionary(from: plaintext)
        let lines = try secret.keys.sorted().map { key in
            try shellExportLine(name: key, value: secretValueString(secret[key]!))
        }
        print(lines.joined(separator: "\n"))
    }
}
