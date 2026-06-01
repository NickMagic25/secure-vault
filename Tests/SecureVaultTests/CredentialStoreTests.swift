import Foundation
import XCTest

@testable import SecureVaultCore

final class CredentialStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testCredentialLifecyclePersistsAndDeletesRecords() throws {
        let databaseURL = makeTemporaryDatabaseURL()

        do {
            let store = try CredentialStore(databaseURL: databaseURL)
            XCTAssertFalse(store.credentialExists(app: "github", username: "nick"))

            try store.insert(
                CredentialRecord(
                    app: "github",
                    username: "nick",
                    keyTag: "test-key",
                    ciphertext: Data("first-password".utf8)
                )
            )

            XCTAssertTrue(store.credentialExists(app: "github", username: "nick"))
            let record = try store.credential(app: "github", username: "nick")
            XCTAssertEqual(record.app, "github")
            XCTAssertEqual(record.username, "nick")
            XCTAssertEqual(record.keyTag, "test-key")
            XCTAssertEqual(record.ciphertext, Data("first-password".utf8))

            XCTAssertThrowsError(
                try store.insert(
                    CredentialRecord(
                        app: "github",
                        username: "nick",
                        keyTag: "test-key",
                        ciphertext: Data("duplicate".utf8)
                    )
                )
            ) { error in
                guard case CredentialStoreError.credentialAlreadyExists("github", "nick") = error else {
                    return XCTFail("Expected duplicate credential error, got \(error)")
                }
            }

            try store.updatePassword(
                app: "github",
                username: "nick",
                ciphertext: Data("rotated-password".utf8)
            )
        }

        do {
            let reopenedStore = try CredentialStore(databaseURL: databaseURL)
            XCTAssertEqual(
                try reopenedStore.credential(app: "github", username: "nick").ciphertext,
                Data("rotated-password".utf8)
            )

            try reopenedStore.deletePassword(app: "github", username: "nick")
            XCTAssertFalse(reopenedStore.credentialExists(app: "github", username: "nick"))
            XCTAssertThrowsError(try reopenedStore.credential(app: "github", username: "nick")) { error in
                guard case CredentialStoreError.credentialNotFound("github", "nick") = error else {
                    return XCTFail("Expected missing credential error, got \(error)")
                }
            }
        }
    }

    func testSecretLifecyclePersistsAndDeletesRecords() throws {
        let databaseURL = makeTemporaryDatabaseURL()
        let store = try CredentialStore(databaseURL: databaseURL)

        XCTAssertFalse(store.secretExists(name: "github-ci"))

        try store.insertSecret(
            SecretRecord(
                name: "github-ci",
                keyTag: "test-key",
                ciphertext: Data(#"{"TOKEN":"abc"}"#.utf8)
            )
        )

        XCTAssertTrue(store.secretExists(name: "github-ci"))
        let record = try store.secret(name: "github-ci")
        XCTAssertEqual(record.name, "github-ci")
        XCTAssertEqual(record.keyTag, "test-key")
        XCTAssertEqual(record.ciphertext, Data(#"{"TOKEN":"abc"}"#.utf8))

        XCTAssertThrowsError(
            try store.insertSecret(
                SecretRecord(
                    name: "github-ci",
                    keyTag: "test-key",
                    ciphertext: Data("duplicate".utf8)
                )
            )
        ) { error in
            guard case CredentialStoreError.secretAlreadyExists("github-ci") = error else {
                return XCTFail("Expected duplicate secret error, got \(error)")
            }
        }

        try store.updateSecret(name: "github-ci", ciphertext: Data(#"{"TOKEN":"rotated"}"#.utf8))
        XCTAssertEqual(
            try store.secret(name: "github-ci").ciphertext,
            Data(#"{"TOKEN":"rotated"}"#.utf8)
        )

        try store.deleteSecret(name: "github-ci")
        XCTAssertFalse(store.secretExists(name: "github-ci"))
        XCTAssertThrowsError(try store.secret(name: "github-ci")) { error in
            guard case CredentialStoreError.secretNotFound("github-ci") = error else {
                return XCTFail("Expected missing secret error, got \(error)")
            }
        }
    }

    private func makeTemporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secure-vault-tests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("vault.sqlite")
    }
}
