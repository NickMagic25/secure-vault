import ArgumentParser
import Foundation

struct EncryptPasswordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encrypt-password",
        abstract: "Store an encrypted password for an app username. Requires Touch ID or Apple Watch."
    )

    @Option(name: .long, help: "App or service name.")
    var app: String

    @Option(name: .long, help: "Username for the app or service.")
    var username: String

    @Option(name: .long, help: "Password value. Prefer the prompt or --password-stdin to avoid shell history.")
    var password: String?

    @Flag(name: .long, help: "Read the password from stdin.")
    var passwordStdin: Bool = false

    @Option(name: .long, help: "Secure Enclave key tag to use. Created automatically if missing.")
    var tag: String = SecureEnclaveManager.defaultPasswordKeyTag

    func run() throws {
        let app = try normalizedCredentialField(app, name: "App")
        let username = try normalizedCredentialField(username, name: "Username")
        try validatePasswordInputOptions(password, passwordStdin: passwordStdin)

        let store = try CredentialStore()

        guard !store.credentialExists(app: app, username: username) else {
            throw CredentialStoreError.credentialAlreadyExists(app: app, username: username)
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Store password for \(username) on \(app)")

        let password = try readPasswordValue(password, passwordStdin: passwordStdin, prompt: "Password: ")
        _ = try SecureEnclaveManager.ensureKey(tag: tag, label: "Secure Vault password key")

        let ciphertext = try SecureEnclaveManager.encrypt(data: Data(password.utf8), tag: tag)
        try store.insert(
            CredentialRecord(
                app: app,
                username: username,
                keyTag: tag,
                ciphertext: ciphertext
            )
        )

        print("Password stored for '\(username)' on '\(app)'.")
    }
}
