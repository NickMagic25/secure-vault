import ArgumentParser

struct KeygenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keygen",
        abstract: "Generate a new Secure Enclave key pair protected by Touch ID or Apple Watch."
    )

    @Option(name: .shortAndLong, help: "Unique tag to identify this key.")
    var tag: String = SecureEnclaveManager.defaultPasswordKeyTag

    @Option(name: .shortAndLong, help: "Human-readable label (optional).")
    var label: String?

    func run() throws {
        let keyLabel = label ?? "Secure Vault password key"
        _ = try SecureEnclaveManager.generateKey(tag: tag, label: keyLabel)
        print("Key generated.")
        print("  tag:   \(tag)")
        print("  label: \(keyLabel)")
        print("")
        print("Password access will require Touch ID or Apple Watch.")
    }
}
