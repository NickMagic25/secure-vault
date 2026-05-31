import ArgumentParser

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all Secure Enclave keys stored in the keychain."
    )

    func run() throws {
        let keys = try SecureEnclaveManager.listKeys()
        if keys.isEmpty {
            print("No Secure Enclave keys found.")
            return
        }
        print("Secure Enclave keys:")
        for key in keys {
            let suffix = key.label.map { "  (\($0))" } ?? ""
            print("  * \(key.tag)\(suffix)")
        }
    }
}
