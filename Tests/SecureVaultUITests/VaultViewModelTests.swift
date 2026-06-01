import Testing
import SecureVaultCore
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

    @Test("Hide clears a revealed selected value")
    func hideSelectedValue() async {
        let service = FakeVaultService(items: [.githubPassword])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()

        await viewModel.revealSelected()
        #expect(viewModel.isSelectedItemRevealed)

        viewModel.hideSelected()

        #expect(!viewModel.isSelectedItemRevealed)
        #expect(viewModel.selectedRevealedValue == nil)
    }

    @Test("Secret JSON rows show sorted top-level key values")
    func secretJSONRows() throws {
        let rows = try SecretField.rows(
            from: """
            {
              "PORT": 5432,
              "ENABLED": true,
              "TOKEN": "secret",
              "EMPTY": null
            }
            """
        )

        #expect(rows == [
            SecretField(key: "EMPTY", value: ""),
            SecretField(key: "ENABLED", value: "true"),
            SecretField(key: "PORT", value: "5432"),
            SecretField(key: "TOKEN", value: "secret"),
        ])
    }

    @Test("Environment file output uses valid sorted dotenv lines")
    func environmentFileOutput() throws {
        let contents = try secretEnvironmentFile([
            "PORT": 5432,
            "ENABLED": true,
            "TOKEN": "secret",
            "QUOTE": "hello \"world\"",
        ])

        #expect(contents == """
        ENABLED="true"
        PORT="5432"
        QUOTE="hello \\"world\\""
        TOKEN="secret"
        """)
    }

    @Test("Automatic refresh picks up CLI changes and locks revealed data")
    func automaticRefreshFromVaultChanges() async {
        let service = FakeVaultService(items: [.githubPassword])
        let monitor = FakeVaultChangeMonitor()
        let viewModel = VaultViewModel(service: service, changeMonitor: monitor)
        viewModel.refresh()
        viewModel.startAutomaticRefresh()

        await viewModel.revealSelected()
        #expect(viewModel.isSelectedItemRevealed)

        service.items.append(.productionSecret)
        monitor.emitChange()
        await Task.yield()

        #expect(monitor.startCount == 1)
        #expect(viewModel.items.map(\.id) == [VaultItem.githubPassword.id, VaultItem.productionSecret.id])
        #expect(!viewModel.isSelectedItemRevealed)
        #expect(viewModel.selectedRevealedValue == nil)
    }

    @Test("Automatic refresh starts only once")
    func automaticRefreshStartsOnlyOnce() {
        let service = FakeVaultService(items: [.githubPassword])
        let monitor = FakeVaultChangeMonitor()
        let viewModel = VaultViewModel(service: service, changeMonitor: monitor)

        viewModel.startAutomaticRefresh()
        viewModel.startAutomaticRefresh()

        #expect(monitor.startCount == 1)
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

    @Test("Secret context actions can fetch clone JSON and env file text")
    func secretContextPayloads() async {
        let service = FakeVaultService(items: [.productionSecret])
        let viewModel = VaultViewModel(service: service)
        viewModel.refresh()
        guard let secret = viewModel.selectedItem else {
            Issue.record("Expected a selected secret.")
            return
        }

        let json = await viewModel.secretJSON(for: secret)
        let envFile = await viewModel.secretEnvironmentFile(for: secret)

        #expect(service.revealSecretRequests == ["production-db"])
        #expect(service.revealSecretEnvironmentFileRequests == ["production-db"])
        #expect(json == "{\n  \"TOKEN\": \"secret\"\n}")
        #expect(envFile == "TOKEN=\"secret\"")
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
    var revealSecretEnvironmentFileRequests: [String] = []
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

    func revealSecretEnvironmentFile(name: String) throws -> String {
        revealSecretEnvironmentFileRequests.append(name)
        return "TOKEN=\"secret\""
    }

    func updateSecret(name: String, json: String) throws {}

    func deleteSecret(name: String) throws {
        items.removeAll { $0.secretName == name }
    }
}

private final class FakeVaultChangeMonitor: VaultChangeMonitoring {
    private var onChange: (@Sendable () -> Void)?
    var startCount = 0
    var stopCount = 0

    func start(onChange: @escaping @Sendable () -> Void) {
        startCount += 1
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func emitChange() {
        onChange?()
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
