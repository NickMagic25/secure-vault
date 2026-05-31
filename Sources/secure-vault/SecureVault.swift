import ArgumentParser

@main
struct SecureVault: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "secure-vault",
        abstract: "Encrypt and decrypt data using the Secure Enclave.",
        discussion: """
            Encrypted data can only be decrypted after authenticating with
            Touch ID or an Apple Watch. The private key never leaves the chip.
            """,
        version: "1.0.0",
        subcommands: [
            KeygenCommand.self,
            EncryptCommand.self,
            DecryptCommand.self,
            ListCommand.self,
            DeleteCommand.self,
        ]
    )
}
