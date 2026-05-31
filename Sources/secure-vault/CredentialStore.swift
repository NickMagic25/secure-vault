import Foundation
import SQLite3

struct CredentialRecord {
    let app: String
    let username: String
    let keyTag: String
    let ciphertext: Data
}

struct SecretRecord {
    let name: String
    let keyTag: String
    let ciphertext: Data
}

enum CredentialStoreError: LocalizedError {
    case credentialAlreadyExists(app: String, username: String)
    case credentialNotFound(app: String, username: String)
    case secretAlreadyExists(String)
    case secretNotFound(String)
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .credentialAlreadyExists(let app, let username):
            return "Password already exists for '\(username)' on '\(app)'. Run 'secure-vault update-password --app \(app) --username \(username)' instead."
        case .credentialNotFound(let app, let username):
            return "No password found for '\(username)' on '\(app)'."
        case .secretAlreadyExists(let name):
            return "Secret '\(name)' already exists. Run 'secure-vault update-secret --name \(name) --json <json>' instead."
        case .secretNotFound(let name):
            return "No secret found with name '\(name)'."
        case .databaseError(let message):
            return "Credential database error: \(message)"
        }
    }
}

final class CredentialStore {
    static let defaultDatabaseURL = resolveDefaultDatabaseURL()

    private var db: OpaquePointer?

    init(databaseURL: URL = CredentialStore.defaultDatabaseURL) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if Self.isDefaultVaultDirectory(directoryURL) {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard status == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
            if let db { sqlite3_close(db) }
            throw CredentialStoreError.databaseError(message)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)

        try execute("PRAGMA busy_timeout = 5000")
        try execute("PRAGMA secure_delete = ON")
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func insert(_ record: CredentialRecord) throws {
        guard !credentialExists(app: record.app, username: record.username) else {
            throw CredentialStoreError.credentialAlreadyExists(app: record.app, username: record.username)
        }

        try run(
            """
            INSERT INTO credentials (app, username, key_tag, ciphertext, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(record.app),
                .text(record.username),
                .text(record.keyTag),
                .data(record.ciphertext),
                .text(Self.timestamp()),
                .text(Self.timestamp()),
            ]
        )
    }

    func credential(app: String, username: String) throws -> CredentialRecord {
        var statement: OpaquePointer?
        let sql = """
        SELECT app, username, key_tag, ciphertext
        FROM credentials
        WHERE app = ? AND username = ?
        LIMIT 1
        """
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        try bind(.text(app), to: 1, in: statement)
        try bind(.text(username), to: 2, in: statement)

        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW else {
            if status == SQLITE_DONE {
                throw CredentialStoreError.credentialNotFound(app: app, username: username)
            }
            throw lastError()
        }

        let app = String(cString: sqlite3_column_text(statement, 0))
        let username = String(cString: sqlite3_column_text(statement, 1))
        let keyTag = String(cString: sqlite3_column_text(statement, 2))
        let byteCount = sqlite3_column_bytes(statement, 3)
        guard let bytes = sqlite3_column_blob(statement, 3), byteCount > 0 else {
            throw CredentialStoreError.databaseError("stored ciphertext is empty")
        }

        return CredentialRecord(
            app: app,
            username: username,
            keyTag: keyTag,
            ciphertext: Data(bytes: bytes, count: Int(byteCount))
        )
    }

    func updatePassword(app: String, username: String, ciphertext: Data) throws {
        let timestamp = Self.timestamp()
        try run(
            """
            UPDATE credentials
            SET ciphertext = ?, updated_at = ?
            WHERE app = ? AND username = ?
            """,
            bindings: [
                .data(ciphertext),
                .text(timestamp),
                .text(app),
                .text(username),
            ]
        )

        guard sqlite3_changes(db) > 0 else {
            throw CredentialStoreError.credentialNotFound(app: app, username: username)
        }
    }

    func deletePassword(app: String, username: String) throws {
        try run(
            "DELETE FROM credentials WHERE app = ? AND username = ?",
            bindings: [.text(app), .text(username)]
        )

        guard sqlite3_changes(db) > 0 else {
            throw CredentialStoreError.credentialNotFound(app: app, username: username)
        }
    }

    func credentialExists(app: String, username: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM credentials WHERE app = ? AND username = ? LIMIT 1"
        do {
            try prepare(sql, statement: &statement)
            defer { sqlite3_finalize(statement) }
            try bind(.text(app), to: 1, in: statement)
            try bind(.text(username), to: 2, in: statement)
            return sqlite3_step(statement) == SQLITE_ROW
        } catch {
            return false
        }
    }

    func insertSecret(_ record: SecretRecord) throws {
        guard !secretExists(name: record.name) else {
            throw CredentialStoreError.secretAlreadyExists(record.name)
        }

        try run(
            """
            INSERT INTO secrets (name, key_tag, ciphertext, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(record.name),
                .text(record.keyTag),
                .data(record.ciphertext),
                .text(Self.timestamp()),
                .text(Self.timestamp()),
            ]
        )
    }

    func secret(name: String) throws -> SecretRecord {
        var statement: OpaquePointer?
        let sql = """
        SELECT name, key_tag, ciphertext
        FROM secrets
        WHERE name = ?
        LIMIT 1
        """
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        try bind(.text(name), to: 1, in: statement)

        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW else {
            if status == SQLITE_DONE {
                throw CredentialStoreError.secretNotFound(name)
            }
            throw lastError()
        }

        let name = String(cString: sqlite3_column_text(statement, 0))
        let keyTag = String(cString: sqlite3_column_text(statement, 1))
        let byteCount = sqlite3_column_bytes(statement, 2)
        guard let bytes = sqlite3_column_blob(statement, 2), byteCount > 0 else {
            throw CredentialStoreError.databaseError("stored secret ciphertext is empty")
        }

        return SecretRecord(
            name: name,
            keyTag: keyTag,
            ciphertext: Data(bytes: bytes, count: Int(byteCount))
        )
    }

    func updateSecret(name: String, ciphertext: Data) throws {
        try run(
            """
            UPDATE secrets
            SET ciphertext = ?, updated_at = ?
            WHERE name = ?
            """,
            bindings: [
                .data(ciphertext),
                .text(Self.timestamp()),
                .text(name),
            ]
        )

        guard sqlite3_changes(db) > 0 else {
            throw CredentialStoreError.secretNotFound(name)
        }
    }

    func deleteSecret(name: String) throws {
        try run(
            "DELETE FROM secrets WHERE name = ?",
            bindings: [.text(name)]
        )

        guard sqlite3_changes(db) > 0 else {
            throw CredentialStoreError.secretNotFound(name)
        }
    }

    func secretExists(name: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM secrets WHERE name = ? LIMIT 1"
        do {
            try prepare(sql, statement: &statement)
            defer { sqlite3_finalize(statement) }
            try bind(.text(name), to: 1, in: statement)
            return sqlite3_step(statement) == SQLITE_ROW
        } catch {
            return false
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS credentials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app TEXT NOT NULL,
                username TEXT NOT NULL,
                key_tag TEXT NOT NULL,
                ciphertext BLOB NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(app, username)
            )
            """
        )

        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_credentials_app_username
            ON credentials(app, username)
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS secrets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                key_tag TEXT NOT NULL,
                ciphertext BLOB NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_secrets_name
            ON secrets(name)
            """
        )
    }

    private enum Binding {
        case text(String)
        case data(Data)
    }

    private func execute(_ sql: String) throws {
        let status = sqlite3_exec(db, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw lastError() }
    }

    private func run(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            try bind(binding, to: Int32(index + 1), in: statement)
        }

        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw lastError() }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        let status = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard status == SQLITE_OK else { throw lastError() }
    }

    private func bind(_ binding: Binding, to index: Int32, in statement: OpaquePointer?) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status: Int32

        switch binding {
        case .text(let value):
            status = sqlite3_bind_text(statement, index, value, -1, transient)
        case .data(let data):
            status = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), transient)
            }
        }

        guard status == SQLITE_OK else { throw lastError() }
    }

    private func lastError() -> CredentialStoreError {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        return .databaseError(message)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func resolveDefaultDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["SECURE_VAULT_DB_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".secure-vault", isDirectory: true)
            .appendingPathComponent("vault.sqlite", isDirectory: false)
    }

    private static func isDefaultVaultDirectory(_ url: URL) -> Bool {
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".secure-vault", isDirectory: true)
        return url.standardizedFileURL.path == defaultDirectory.standardizedFileURL.path
    }
}
