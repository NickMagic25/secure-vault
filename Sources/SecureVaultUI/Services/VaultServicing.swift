import Foundation
import SecureVaultCore

public protocol VaultServicing {
    func loadItems() throws -> [VaultItem]
    func createPassword(app: String, username: String, password: String) throws
    func revealPassword(app: String, username: String) throws -> String
    func updatePassword(app: String, username: String, password: String) throws
    func deletePassword(app: String, username: String) throws
    func createSecret(name: String, json: String) throws
    func revealSecretJSON(name: String) throws -> String
    func revealSecretEnvironmentFile(name: String) throws -> String
    func updateSecret(name: String, json: String) throws
    func deleteSecret(name: String) throws
}

public final class LiveVaultService: VaultServicing {
    private let databaseURL: URL
    private let defaultKeyTag: String

    public init(
        databaseURL: URL = CredentialStore.defaultDatabaseURL,
        defaultKeyTag: String = SecureEnclaveManager.defaultPasswordKeyTag
    ) {
        self.databaseURL = databaseURL
        self.defaultKeyTag = defaultKeyTag
    }

    public func loadItems() throws -> [VaultItem] {
        let store = try makeStore()
        let passwords = try store.listCredentials().map(VaultItem.init(password:))
        let secrets = try store.listSecrets().map(VaultItem.init(secret:))

        return (passwords + secrets).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .password
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public func createPassword(app: String, username: String, password: String) throws {
        let app = try normalizedVaultField(app, name: "App")
        let username = try normalizedVaultField(username, name: "Username")
        guard !password.isEmpty else { throw VaultValidationError("Password cannot be empty.") }

        let store = try makeStore()
        guard !store.credentialExists(app: app, username: username) else {
            throw CredentialStoreError.credentialAlreadyExists(app: app, username: username)
        }

        try SecureEnclaveManager.authenticate(reason: "Store password for \(username) on \(app)")
        _ = try SecureEnclaveManager.ensureKey(tag: defaultKeyTag, label: "Secure Vault password key")
        let ciphertext = try SecureEnclaveManager.encrypt(data: Data(password.utf8), tag: defaultKeyTag)
        try store.insert(
            CredentialRecord(
                app: app,
                username: username,
                keyTag: defaultKeyTag,
                ciphertext: ciphertext
            )
        )
    }

    public func revealPassword(app: String, username: String) throws -> String {
        let app = try normalizedVaultField(app, name: "App")
        let username = try normalizedVaultField(username, name: "Username")
        let record = try makeStore().credential(app: app, username: username)
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Reveal password for \(username) on \(app)"
        )

        guard let password = String(data: plaintext, encoding: .utf8) else {
            throw VaultValidationError("Stored password is not valid UTF-8.")
        }
        return password
    }

    public func updatePassword(app: String, username: String, password: String) throws {
        let app = try normalizedVaultField(app, name: "App")
        let username = try normalizedVaultField(username, name: "Username")
        guard !password.isEmpty else { throw VaultValidationError("Password cannot be empty.") }

        let store = try makeStore()
        let record = try store.credential(app: app, username: username)

        try SecureEnclaveManager.authenticate(reason: "Update password for \(username) on \(app)")
        let ciphertext = try SecureEnclaveManager.encrypt(data: Data(password.utf8), tag: record.keyTag)
        try store.updatePassword(app: app, username: username, ciphertext: ciphertext)
    }

    public func deletePassword(app: String, username: String) throws {
        let app = try normalizedVaultField(app, name: "App")
        let username = try normalizedVaultField(username, name: "Username")
        let store = try makeStore()
        _ = try store.credential(app: app, username: username)

        try SecureEnclaveManager.authenticate(reason: "Delete password for \(username) on \(app)")
        try store.deletePassword(app: app, username: username)
    }

    public func createSecret(name: String, json: String) throws {
        let name = try normalizedVaultField(name, name: "Secret name")
        let secret = try parseSecretJSON(json)
        let store = try makeStore()
        guard !store.secretExists(name: name) else {
            throw CredentialStoreError.secretAlreadyExists(name)
        }

        try SecureEnclaveManager.authenticate(reason: "Store secret \(name)")
        _ = try SecureEnclaveManager.ensureKey(tag: defaultKeyTag, label: "Secure Vault password and secret key")
        let ciphertext = try SecureEnclaveManager.encrypt(data: try secretJSONData(secret), tag: defaultKeyTag)
        try store.insertSecret(SecretRecord(name: name, keyTag: defaultKeyTag, ciphertext: ciphertext))
    }

    public func revealSecretJSON(name: String) throws -> String {
        try secretJSONString(revealSecretDictionary(name: name, reason: "Reveal secret \(name)"), prettyPrinted: true)
    }

    public func revealSecretEnvironmentFile(name: String) throws -> String {
        try secretEnvironmentFile(revealSecretDictionary(name: name, reason: "Copy secret \(name) as an environment file"))
    }

    private func revealSecretDictionary(name: String, reason: String) throws -> [String: Any] {
        let name = try normalizedVaultField(name, name: "Secret name")
        let record = try makeStore().secret(name: name)
        let plaintext = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: reason
        )

        return try secretDictionary(from: plaintext)
    }

    public func updateSecret(name: String, json: String) throws {
        let name = try normalizedVaultField(name, name: "Secret name")
        let updatedSecret = try parseSecretJSON(json)
        let store = try makeStore()
        let record = try store.secret(name: name)

        _ = try SecureEnclaveManager.decrypt(
            data: record.ciphertext,
            tag: record.keyTag,
            reason: "Update secret \(name)"
        )

        let ciphertext = try SecureEnclaveManager.encrypt(data: try secretJSONData(updatedSecret), tag: record.keyTag)
        try store.updateSecret(name: name, ciphertext: ciphertext)
    }

    public func deleteSecret(name: String) throws {
        let name = try normalizedVaultField(name, name: "Secret name")
        let store = try makeStore()
        _ = try store.secret(name: name)

        try SecureEnclaveManager.authenticate(reason: "Delete secret \(name)")
        try store.deleteSecret(name: name)
    }

    private func makeStore() throws -> CredentialStore {
        try CredentialStore(databaseURL: databaseURL)
    }
}
