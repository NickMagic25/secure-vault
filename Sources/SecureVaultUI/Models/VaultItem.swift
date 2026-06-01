import Foundation
import SecureVaultCore

public enum VaultItemKind: String, CaseIterable, Hashable {
    case password
    case secret

    public var title: String {
        switch self {
        case .password: "Passwords"
        case .secret: "Secrets"
        }
    }

    public var singularTitle: String {
        switch self {
        case .password: "Password"
        case .secret: "Secret"
        }
    }

    public var systemImage: String {
        switch self {
        case .password: "key.fill"
        case .secret: "curlybraces.square.fill"
        }
    }
}

public struct VaultItem: Identifiable, Hashable {
    public let id: String
    public let kind: VaultItemKind
    public let title: String
    public let subtitle: String?
    public let app: String?
    public let username: String?
    public let secretName: String?
    public let keyTag: String
    public let createdAt: String
    public let updatedAt: String

    public static func passwordID(app: String, username: String) -> String {
        "password:\(app)\u{1F}\(username)"
    }

    public static func secretID(name: String) -> String {
        "secret:\(name)"
    }

    public init(
        id: String,
        kind: VaultItemKind,
        title: String,
        subtitle: String?,
        app: String?,
        username: String?,
        secretName: String?,
        keyTag: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.app = app
        self.username = username
        self.secretName = secretName
        self.keyTag = keyTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(password summary: StoredCredentialSummary) {
        self.init(
            id: Self.passwordID(app: summary.app, username: summary.username),
            kind: .password,
            title: summary.app,
            subtitle: summary.username,
            app: summary.app,
            username: summary.username,
            secretName: nil,
            keyTag: summary.keyTag,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt
        )
    }

    public init(secret summary: StoredSecretSummary) {
        self.init(
            id: Self.secretID(name: summary.name),
            kind: .secret,
            title: summary.name,
            subtitle: nil,
            app: nil,
            username: nil,
            secretName: summary.name,
            keyTag: summary.keyTag,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt
        )
    }

    public func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [title, subtitle, app, username, secretName]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

public enum RevealedVaultValue: Equatable {
    case password(String)
    case secretJSON(String)
}
