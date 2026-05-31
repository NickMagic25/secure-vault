import ArgumentParser

@main
struct SecureVault: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "secure-vault",
        abstract: "Manage local app passwords and JSON secrets using the Secure Enclave.",
        discussion: """
            Passwords and JSON secrets are stored in a local SQLite vault after
            being encrypted with a Secure Enclave key. Reading, updating,
            deleting, and key deletion require Touch ID or Apple Watch
            authentication.
            """,
        version: "1.0.0",
        subcommands: [
            EncryptPasswordCommand.self,
            GetPasswordCommand.self,
            UpdatePasswordCommand.self,
            DeletePasswordCommand.self,
            MakeSecretCommand.self,
            UpdateSecretCommand.self,
            GetSecretCommand.self,
            DeleteSecretCommand.self,
            ApplySecretCommand.self,
            KeygenCommand.self,
            DeleteCommand.self,
        ]
    )
}
