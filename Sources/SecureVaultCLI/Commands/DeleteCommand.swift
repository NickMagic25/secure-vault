import ArgumentParser
import SecureVaultCore

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Permanently delete a Secure Enclave key. Cannot be undone."
    )

    @Option(name: .shortAndLong, help: "Tag of the key to delete.")
    var tag: String

    @Flag(name: .shortAndLong, help: "Skip the confirmation prompt.")
    var force: Bool = false

    func run() throws {
        if !force {
            print("Delete key '\(tag)'? This is irreversible. [y/N] ", terminator: "")
            let reply = readLine()?.lowercased() ?? ""
            guard reply == "y" || reply == "yes" else {
                print("Cancelled.")
                return
            }
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        try SecureEnclaveManager.authenticate(reason: "Delete Secure Vault key \(tag)")
        try SecureEnclaveManager.deleteKey(tag: tag)
        print("Key '\(tag)' deleted.")
    }
}
