import Foundation
import LocalAuthentication
import Security
import XCTest

@testable import SecureVaultCore

final class SecureEnclaveManagerSecurityTests: XCTestCase {
    private enum TestError: Error {
        case weakKey
        case authDenied
        case stop
    }

    func testDecryptRejectsWeakSelectedKeyBeforePrompting() {
        var events: [String] = []

        XCTAssertThrowsError(
            try SecureEnclaveManager.decrypt(
                data: Data("ciphertext".utf8),
                tag: "attacker-selected-key",
                reason: "Reveal password",
                validateKeyAccess: { tag in
                    events.append("validate:\(tag)")
                    throw TestError.weakKey
                },
                authenticate: { reason in
                    events.append("auth:\(reason)")
                    return LAContext()
                },
                fetchKey: { tag, _ in
                    events.append("fetch:\(tag)")
                    throw TestError.stop
                },
                decryptData: { _, _ in
                    events.append("decrypt")
                    return Data()
                }
            )
        ) { error in
            XCTAssertTrue(error is TestError)
        }

        XCTAssertEqual(events, ["validate:attacker-selected-key"])
    }

    func testDecryptAuthenticatesBeforeFetchingSelectedKey() {
        var events: [String] = []
        var authenticatedContext: LAContext?

        XCTAssertThrowsError(
            try SecureEnclaveManager.decrypt(
                data: Data("ciphertext".utf8),
                tag: "stored-row-key",
                reason: "Reveal password",
                validateKeyAccess: { tag in
                    events.append("validate:\(tag)")
                },
                authenticate: { reason in
                    events.append("auth:\(reason)")
                    let context = LAContext()
                    authenticatedContext = context
                    return context
                },
                fetchKey: { tag, context in
                    events.append("fetch:\(tag)")
                    guard let context, let authenticatedContext else {
                        XCTFail("Expected fetch to receive the authenticated LAContext")
                        throw TestError.stop
                    }
                    XCTAssertTrue(context === authenticatedContext)
                    throw TestError.stop
                },
                decryptData: { _, _ in
                    events.append("decrypt")
                    return Data()
                }
            )
        ) { error in
            XCTAssertTrue(error is TestError)
        }

        XCTAssertEqual(events, [
            "validate:stored-row-key",
            "auth:Reveal password",
            "fetch:stored-row-key",
        ])
    }

    func testDecryptDoesNotFetchSelectedKeyWhenAuthenticationFails() {
        var events: [String] = []

        XCTAssertThrowsError(
            try SecureEnclaveManager.decrypt(
                data: Data("ciphertext".utf8),
                tag: "stored-row-key",
                reason: "Reveal password",
                validateKeyAccess: { tag in
                    events.append("validate:\(tag)")
                },
                authenticate: { reason in
                    events.append("auth:\(reason)")
                    throw TestError.authDenied
                },
                fetchKey: { tag, _ in
                    events.append("fetch:\(tag)")
                    throw TestError.stop
                },
                decryptData: { _, _ in
                    events.append("decrypt")
                    return Data()
                }
            )
        ) { error in
            XCTAssertTrue(error is TestError)
        }

        XCTAssertEqual(events, [
            "validate:stored-row-key",
            "auth:Reveal password",
        ])
    }
}
