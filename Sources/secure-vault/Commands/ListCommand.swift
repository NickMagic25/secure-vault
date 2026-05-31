import ArgumentParser
import Foundation

struct UpdatePasswordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-password",
        abstract: "Replace a stored password for an app username. Requires Touch ID or Apple Watch."
    )

    @Option(name: .long, help: "App or service name.")
    var app: String

    @Option(name: .long, help: "Username for the app or service.")
    var username: String

    @Option(name: .long, help: "New password value. Prefer the prompt or --password-stdin to avoid shell history.")
    var password: String?

    @Flag(name: .long, help: "Read the new password from stdin.")
    var passwordStdin: Bool = false

    func run() throws {
        let app = try normalizedCredentialField(app, name: "App")
        let username = try normalizedCredentialField(username, name: "Username")
        try validatePasswordInputOptions(password, passwordStdin: passwordStdin)

        let store = try CredentialStore()
        let record = try store.credential(app: app, username: username)

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Update password for \(username) on \(app)")

        let password = try readPasswordValue(password, passwordStdin: passwordStdin, prompt: "New password: ")
        let ciphertext = try SecureEnclaveManager.encrypt(data: Data(password.utf8), tag: record.keyTag)
        try store.updatePassword(app: app, username: username, ciphertext: ciphertext)

        print("Password updated for '\(username)' on '\(app)'.")
    }
}
