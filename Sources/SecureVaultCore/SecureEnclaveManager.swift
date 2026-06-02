import Foundation
import Dispatch
import LocalAuthentication
import Security

public enum VaultError: LocalizedError {
    case keyAlreadyExists(String)
    case keyNotFound(String)
    case keyGenerationFailed(Error)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case algorithmUnsupported
    case authenticationUnavailable(String)
    case authenticationFailed(Error)
    case weakKeyAccessControl(String)
    case keyAuthenticationProbeFailed(String)
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keyAlreadyExists(let tag):
            return "Key '\(tag)' already exists. Run 'secure-vault delete --tag \(tag)' first."
        case .keyNotFound(let tag):
            return "No key found with tag '\(tag)'."
        case .keyGenerationFailed(let err):
            return "Key generation failed: \(err.localizedDescription)"
        case .encryptionFailed(let err):
            return "Encryption failed: \(err.localizedDescription)"
        case .decryptionFailed(let err):
            return "Decryption failed: \(err.localizedDescription)"
        case .algorithmUnsupported:
            return "ECIES algorithm is not supported for this key."
        case .authenticationUnavailable(let reason):
            return "Touch ID or Apple Watch authentication is unavailable: \(reason)"
        case .authenticationFailed(let err):
            return "Authentication failed: \(err.localizedDescription)"
        case .weakKeyAccessControl(let tag):
            return "Key '\(tag)' is not protected by local owner authentication. Delete it and create a new Secure Vault key."
        case .keyAuthenticationProbeFailed(let tag):
            return "Could not verify local owner authentication protection for key '\(tag)'."
        case .keychainError(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
            return "Keychain error (\(status)): \(msg)"
        }
    }
}

public enum SecureEnclaveManager {
    private static let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM
    private static let authenticationProbePlaintext = Data("secure-vault-authentication-probe".utf8)
    public static let defaultPasswordKeyTag = "io.securevault.password-manager"

    // MARK: - Key management

    public static func ensureKey(tag: String, label: String?) throws -> SecKey {
        if keyExists(tag: tag) {
            try requirePrivateKeyAuthentication(tag: tag)
            return try fetchKey(tag: tag, context: nil)
        }
        let key = try generateKey(tag: tag, label: label)
        try requirePrivateKeyAuthentication(tag: tag)
        return key
    }

    public static func generateKey(tag: String, label: String?) throws -> SecKey {
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

    public static func deleteKey(tag: String) throws {
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

    public static func authenticate(reason: String) throws {
        _ = try authenticatedContext(reason: reason)
    }

    private static func authenticatedContext(reason: String) throws -> LAContext {
        let context = LAContext()
        context.localizedReason = reason

        let policy = ownerAuthenticationPolicy()

        var authError: NSError?
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            throw VaultError.authenticationUnavailable(authError?.localizedDescription ?? "no eligible authenticator is configured")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error> = .failure(VaultError.authenticationUnavailable("authentication did not complete"))

        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            if success {
                result = .success(())
            } else {
                result = .failure(error.map(VaultError.authenticationFailed) ?? VaultError.authenticationUnavailable("authentication was cancelled"))
            }
            semaphore.signal()
        }

        semaphore.wait()
        try result.get()
        return context
    }

    private static func ownerAuthenticationPolicy() -> LAPolicy {
        if #available(macOS 15.0, *) {
            return .deviceOwnerAuthenticationWithBiometricsOrCompanion
        }
        return .deviceOwnerAuthenticationWithBiometricsOrWatch
    }

    public static func listKeys() throws -> [(tag: String, label: String?)] {
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

    public static func encrypt(data: Data, tag: String) throws -> Data {
        // Public key operations never require authentication.
        try requirePrivateKeyAuthentication(tag: tag)
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

    public static func decrypt(data: Data, tag: String, reason: String) throws -> Data {
        try decrypt(
            data: data,
            tag: tag,
            reason: reason,
            validateKeyAccess: requirePrivateKeyAuthentication,
            authenticate: { try authenticatedContext(reason: $0) },
            fetchKey: { try fetchKey(tag: $0, context: $1) },
            decryptData: { try decrypt(data: $1, with: $0) }
        )
    }

    internal static func decrypt(
        data: Data,
        tag: String,
        reason: String,
        validateKeyAccess: (String) throws -> Void,
        authenticate: (String) throws -> LAContext,
        fetchKey: (String, LAContext?) throws -> SecKey,
        decryptData: (SecKey, Data) throws -> Data
    ) throws -> Data {
        try validateKeyAccess(tag)
        let context = try authenticate(reason)
        let privateKey = try fetchKey(tag, context)
        return try decryptData(privateKey, data)
    }

    private static func decrypt(data: Data, with privateKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
            throw VaultError.algorithmUnsupported
        }
        var cfError: Unmanaged<CFError>?
        guard let pt = SecKeyCreateDecryptedData(privateKey, algorithm, data as CFData, &cfError) else {
            throw VaultError.decryptionFailed(cfError!.takeRetainedValue() as Error)
        }
        return pt as Data
    }

    private static func requirePrivateKeyAuthentication(tag: String) throws {
        let noAuthContext = LAContext()
        noAuthContext.interactionNotAllowed = true

        let privateKey = try fetchKey(tag: tag, context: noAuthContext)
        try requirePrivateKeyAuthentication(
            tag: tag,
            privateKey: privateKey,
            plaintext: authenticationProbePlaintext
        )
    }

    private static func requirePrivateKeyAuthentication(tag: String, privateKey: SecKey, plaintext: Data) throws {
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw VaultError.algorithmUnsupported
        }

        var encryptionError: Unmanaged<CFError>?
        guard let ciphertext = SecKeyCreateEncryptedData(publicKey, algorithm, plaintext as CFData, &encryptionError) else {
            throw VaultError.encryptionFailed(encryptionError!.takeRetainedValue() as Error)
        }

        var decryptionError: Unmanaged<CFError>?
        if let decrypted = SecKeyCreateDecryptedData(privateKey, algorithm, ciphertext, &decryptionError) {
            guard decrypted as Data == plaintext else {
                throw VaultError.keyAuthenticationProbeFailed(tag)
            }
            throw VaultError.weakKeyAccessControl(tag)
        }

        if let decryptionError {
            _ = decryptionError.takeRetainedValue()
        }
    }

    // MARK: - Helpers

    public static func keyExists(tag: String) -> Bool {
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
