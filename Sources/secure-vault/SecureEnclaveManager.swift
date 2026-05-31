import Foundation
import LocalAuthentication
import Security

enum VaultError: LocalizedError {
    case keyAlreadyExists(String)
    case keyNotFound(String)
    case keyGenerationFailed(Error)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case algorithmUnsupported
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keyAlreadyExists(let tag):
            return "Key '\(tag)' already exists. Run 'secure-vault delete --tag \(tag)' first."
        case .keyNotFound(let tag):
            return "No key found with tag '\(tag)'. Run 'secure-vault keygen --tag \(tag)' first."
        case .keyGenerationFailed(let err):
            return "Key generation failed: \(err.localizedDescription)"
        case .encryptionFailed(let err):
            return "Encryption failed: \(err.localizedDescription)"
        case .decryptionFailed(let err):
            return "Decryption failed: \(err.localizedDescription)"
        case .algorithmUnsupported:
            return "ECIES algorithm is not supported for this key."
        case .keychainError(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
            return "Keychain error (\(status)): \(msg)"
        }
    }
}

enum SecureEnclaveManager {
    private static let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM

    // MARK: - Key management

    static func generateKey(tag: String, label: String?) throws -> SecKey {
        guard !keyExists(tag: tag) else { throw VaultError.keyAlreadyExists(tag) }

        var cfError: Unmanaged<CFError>?

        // Require Touch ID (any enrolled finger) OR Apple Watch.
        // .privateKeyUsage gates the SE key itself; the biometry/watch flags gate decryption.
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryAny, .or, .watch],
            &cfError
        ) else {
            throw VaultError.keyGenerationFailed(cfError!.takeRetainedValue() as Error)
        }

        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String:    true,
            kSecAttrApplicationTag as String: tagBytes(tag),
            kSecAttrAccessControl as String:  access,
        ]
        if let label { privateAttrs[kSecAttrLabel as String] = label }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:  256,
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String:    privateAttrs,
        ]

        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &cfError) else {
            throw VaultError.keyGenerationFailed(cfError!.takeRetainedValue() as Error)
        }
        return key
    }

    static func deleteKey(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String: tagBytes(tag),
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainError(status)
        }
    }

    static func listKeys() throws -> [(tag: String, label: String?)] {
        let noAuthContext = LAContext()
        noAuthContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String:               kSecClassKey,
            kSecAttrTokenID as String:         kSecAttrTokenIDSecureEnclave,
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnAttributes as String:    true,
            kSecMatchLimit as String:          kSecMatchLimitAll,
            // Don't prompt for auth just to list key metadata
            kSecUseAuthenticationContext as String: noAuthContext,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let array = items as? [[String: Any]] else {
            throw VaultError.keychainError(status)
        }
        return array.compactMap { attrs in
            guard let data = attrs[kSecAttrApplicationTag as String] as? Data,
                  let tag  = String(data: data, encoding: .utf8) else { return nil }
            return (tag: tag, label: attrs[kSecAttrLabel as String] as? String)
        }
    }

    // MARK: - Crypto

    static func encrypt(data: Data, tag: String) throws -> Data {
        // Public key operations never require authentication.
        let privateKey = try fetchKey(tag: tag, context: nil)
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw VaultError.keyNotFound(tag)
        }
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw VaultError.algorithmUnsupported
        }
        var cfError: Unmanaged<CFError>?
        guard let ct = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &cfError) else {
            throw VaultError.encryptionFailed(cfError!.takeRetainedValue() as Error)
        }
        return ct as Data
    }

    static func decrypt(data: Data, tag: String, reason: String) throws -> Data {
        // The LAContext carries the reason string shown in the Touch ID / Watch prompt.
        let context = LAContext()
        context.localizedReason = reason
        let privateKey = try fetchKey(tag: tag, context: context)
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            throw VaultError.algorithmUnsupported
        }
        var cfError: Unmanaged<CFError>?
        // Authentication fires here when the Secure Enclave performs the operation.
        guard let pt = SecKeyCreateDecryptedData(privateKey, algorithm, data as CFData, &cfError) else {
            throw VaultError.decryptionFailed(cfError!.takeRetainedValue() as Error)
        }
        return pt as Data
    }

    // MARK: - Helpers

    static func keyExists(tag: String) -> Bool {
        let noAuthContext = LAContext()
        noAuthContext.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String:                    kSecClassKey,
            kSecAttrApplicationTag as String:       tagBytes(tag),
            kSecAttrTokenID as String:              kSecAttrTokenIDSecureEnclave,
            kSecReturnAttributes as String:         true,
            kSecUseAuthenticationContext as String: noAuthContext,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func fetchKey(tag: String, context: LAContext?) throws -> SecKey {
        var query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: tagBytes(tag),
            kSecAttrTokenID as String:        kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String:          true,
        ]
        if let ctx = context {
            query[kSecUseAuthenticationContext as String] = ctx
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, item != nil else {
            throw status == errSecItemNotFound ? VaultError.keyNotFound(tag) : VaultError.keychainError(status)
        }
        return item as! SecKey
    }

    private static func tagBytes(_ tag: String) -> Data { Data(tag.utf8) }
}
