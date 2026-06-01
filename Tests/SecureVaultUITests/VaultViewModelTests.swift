import Testing
@testable import SecureVaultUI

@Suite("Vault GUI view model")
@MainActor
struct VaultViewModelTests {
    @Test("Refresh shows password app names and secret names without reveal calls")
    func refreshShowsMetadataWithoutReveal() {
        let service = FakeVaultService(items: [.githubPassword, .productionSecret])
        let viewModel = VaultViewModel(service: service)

        viewModel.refresh()

        #expect(viewModel.items.map(\.title) == ["GitHub", "production-db"])
        #expect(viewModel.items.map(\.subtitle) == ["nick", nil])
        #expect(service.revealPasswordRequests.isEmpty)
        #expect(service.revealSecretRequests.isEmpty)
    }

    @Test("Search matches password apps, usernames, and secret names")
    func searchFiltersVisibleMetadata() {
        let service = FakeVaultService(items: [.githubPassword, .productionSecret])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        viewModel.searchText = "nick"
        #expect(viewModel.filteredItems.map(\.id) == [VaultItem.githubPassword.id])

        viewModel.searchText = "production"
        #expect(viewModel.filteredItems.map(\.id) == [VaultItem.productionSecret.id])
    }

    @Test("Reveal asks the service for the selected password only on demand")
    func revealSelectedPassword() async {
        let service = FakeVaultService(items: [.githubPassword])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        await viewModel.revealSelected()

        #expect(service.revealPasswordRequests == ["GitHub:nick"])
        #expect(viewModel.selectedRevealedValue == .password("ghp_secret"))
    }

    @Test("Reveal asks the service for the selected secret only on demand")
    func revealSelectedSecret() async {
        let service = FakeVaultService(items: [.productionSecret])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        await viewModel.revealSelected()

        #expect(service.revealSecretRequests == ["production-db"])
        #expect(viewModel.selectedRevealedValue == .secretJSON("{\n  \"TOKEN\": \"secret\"\n}"))
    }

    @Test("Creating a password refreshes metadata and selects the new row")
    func createPasswordRefreshesAndSelectsNewRow() async {
        let service = FakeVaultService(items: [.productionSecret])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        await viewModel.createPassword(app: "GitHub", username: "nick", password: "secret")

        #expect(service.createdPasswordRequests == ["GitHub:nick"])
        #expect(viewModel.items.map(\.id).contains(VaultItem.githubPassword.id))
        #expect(viewModel.selectedItemID == VaultItem.githubPassword.id)
        #expect(viewModel.selectedRevealedValue == nil)
    }

    @Test("Deleting a selected item refreshes metadata and clears revealed data")
    func deleteSelectedItemRefreshesAndLocksDetail() async {
        let service = FakeVaultService(items: [.githubPassword, .productionSecret])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        await viewModel.revealSelected()
        await viewModel.deleteSelected()

        #expect(service.deletePasswordRequests == ["GitHub:nick"])
        #expect(viewModel.items.map(\.id) == [VaultItem.productionSecret.id])
        #expect(viewModel.selectedRevealedValue == nil)
    }
}

private final class FakeVaultService: VaultServicing {
    var items: [VaultItem]
    var revealPasswordRequests: [String] = []
    var revealSecretRequests: [String] = []
    var deletePasswordRequests: [String] = []
    var createdPasswordRequests: [String] = []

    init(items: [VaultItem]) {
        self.items = items
    }

    func loadItems() throws -> [VaultItem] {
        items
    }

    func createPassword(app: String, username: String, password: String) throws {
        createdPasswordRequests.append("\(app):\(username)")
        items.append(.password(app: app, username: username))
    }

    func revealPassword(app: String, username: String) throws -> String {
        revealPasswordRequests.append("\(app):\(username)")
        return "ghp_secret"
    }

    func updatePassword(app: String, username: String, password: String) throws {}

    func deletePassword(app: String, username: String) throws {
        deletePasswordRequests.append("\(app):\(username)")
        items.removeAll { $0.app == app && $0.username == username }
    }

    func createSecret(name: String, json: String) throws {
        items.append(.secret(name: name))
    }

    func revealSecretJSON(name: String) throws -> String {
        revealSecretRequests.append(name)
        return "{\n  \"TOKEN\": \"secret\"\n}"
    }

    func updateSecret(name: String, json: String) throws {}

    func deleteSecret(name: String) throws {
        items.removeAll { $0.secretName == name }
    }
}

private extension VaultItem {
    static let githubPassword = VaultItem.password(app: "GitHub", username: "nick")
    static let productionSecret = VaultItem.secret(name: "production-db")

    static func password(app: String, username: String) -> VaultItem {
        VaultItem(
            id: passwordID(app: app, username: username),
            kind: .password,
            title: app,
            subtitle: username,
            app: app,
            username: username,
            secretName: nil,
            keyTag: "test-key",
            createdAt: "2026-05-31T12:00:00Z",
            updatedAt: "2026-05-31T12:00:00Z"
        )
    }

    static func secret(name: String) -> VaultItem {
        VaultItem(
            id: secretID(name: name),
            kind: .secret,
            title: name,
            subtitle: nil,
            app: nil,
            username: nil,
            secretName: name,
            keyTag: "test-key",
            createdAt: "2026-05-31T12:00:00Z",
            updatedAt: "2026-05-31T12:00:00Z"
        )
    }
}
