import ArgumentParser

struct DeletePasswordCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-password",
        abstract: "Delete a stored password for an app username. Requires Touch ID or Apple Watch."
    )

    @Option(name: .long, help: "App or service name.")
    var app: String

    @Option(name: .long, help: "Username for the app or service.")
    var username: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var force: Bool = false

    func run() throws {
        let app = try normalizedCredentialField(app, name: "App")
        let username = try normalizedCredentialField(username, name: "Username")
        let store = try CredentialStore()

        _ = try store.credential(app: app, username: username)

        if !force {
            print("Delete password for '\(username)' on '\(app)'? This is irreversible. [y/N] ", terminator: "")
            let reply = readLine()?.lowercased() ?? ""
            guard reply == "y" || reply == "yes" else {
                print("Cancelled.")
                return
            }
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Delete password for \(username) on \(app)")
        try store.deletePassword(app: app, username: username)

        print("Password deleted for '\(username)' on '\(app)'.")
    }
}
