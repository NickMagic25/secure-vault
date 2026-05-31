import ArgumentParser

struct KeygenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keygen",
        abstract: "Generate a new Secure Enclave key pair protected by Touch ID or Apple Watch."
    )

    @Option(name: .shortAndLong, help: "Unique tag to identify this key.")
    var tag: String = "io.securevault.default"

    @Option(name: .shortAndLong, help: "Human-readable label (optional).")
    var label: String?

    func run() throws {
        _ = try SecureEnclaveManager.generateKey(tag: tag, label: label)
        print("Key generated.")
        print("  tag:   \(tag)")
        if let label { print("  label: \(label)") }
        print("")
        print("Decryption will require Touch ID or Apple Watch.")
    }
}
