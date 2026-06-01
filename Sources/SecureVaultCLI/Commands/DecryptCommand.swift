import ArgumentParser
import Foundation
import SecureVaultCore

struct GetPasswordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-password",
        abstract: "Decrypt and print a stored password. Requires Touch ID or Apple Watch."
    )

    @Option(name: .long, help: "App or service name.")
    var app: String

    @Option(name: .long, help: "Username for the app or service.")
    var username: String

    func run() throws {
        let app = try normalizedCredentialField(app, name: "App")
        let username = try normalizedCredentialField(username, name: "Username")

        let record = try CredentialStore().credential(app: app, username: username)

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Reveal password for \(username) on \(app)"
        )

        guard let password = String(data: plaintext, encoding: .utf8) else {
            throw ValidationError("Stored password is not valid UTF-8.")
        }
        print(password, terminator: "")
    }
}
