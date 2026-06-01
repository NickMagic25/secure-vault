import Foundation
import SwiftUI

@MainActor
public final class VaultViewModel: ObservableObject {
    @Published public private(set) var items: [VaultItem] = []
    @Published public var selectedItemID: VaultItem.ID?
    @Published public var searchText = ""
    @Published public private(set) var revealedItemID: VaultItem.ID?
    @Published public private(set) var revealedValue: RevealedVaultValue?
    @Published public private(set) var isWorking = false
    @Published public private(set) var errorMessage: String?

    private let service: VaultServicing
    private let changeMonitor: VaultChangeMonitoring?
    private var isMonitoringVaultChanges = false
    private var needsExternalRefresh = false

    public convenience init(service: VaultServicing = LiveVaultService()) {
        self.init(service: service, changeMonitor: VaultDirectoryMonitor())
    }

    init(service: VaultServicing, changeMonitor: VaultChangeMonitoring?) {
        self.service = service
        self.changeMonitor = changeMonitor
    }

    public var filteredItems: [VaultItem] {
        items.filter { $0.matches(searchText: searchText) }
    }

    public var selectedItem: VaultItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    public var selectedRevealedValue: RevealedVaultValue? {
        guard selectedItemID == revealedItemID else { return nil }
        return revealedValue
    }

    public var isSelectedItemRevealed: Bool {
        selectedRevealedValue != nil
    }

    public func refresh() {
        refresh(clearingReveal: false)
    }

    public func startAutomaticRefresh() {
        guard !isMonitoringVaultChanges else { return }
        isMonitoringVaultChanges = true
        changeMonitor?.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAfterExternalChange()
            }
        }
    }

    public func stopAutomaticRefresh() {
        changeMonitor?.stop()
        isMonitoringVaultChanges = false
        needsExternalRefresh = false
    }

    private func refreshAfterExternalChange() {
        guard !isWorking else {
            needsExternalRefresh = true
            return
        }

        refresh(clearingReveal: true)
    }

    private func refresh(clearingReveal shouldClearReveal: Bool) {
        do {
            let loadedItems = try service.loadItems()
            items = loadedItems
            var shouldClearReveal = shouldClearReveal
            if let selectedItemID, !loadedItems.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = loadedItems.first?.id
                shouldClearReveal = true
            } else if selectedItemID == nil {
                selectedItemID = loadedItems.first?.id
            }
            if shouldClearReveal {
                clearReveal()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ id: VaultItem.ID?) {
        guard selectedItemID != id else { return }
        selectedItemID = id
        clearReveal()
    }

    public func clearError() {
        errorMessage = nil
    }

    public func revealSelected() async {
        guard let item = selectedItem else { return }
        let service = self.service
        await run {
            switch item.kind {
            case .password:
                guard let app = item.app, let username = item.username else {
                    throw VaultUIError.invalidSelection
                }
                return RevealedVaultValue.password(
                    try service.revealPassword(app: app, username: username)
                )
            case .secret:
                guard let name = item.secretName else {
                    throw VaultUIError.invalidSelection
                }
                return RevealedVaultValue.secretJSON(
                    try service.revealSecretJSON(name: name)
                )
            }
        } apply: { value in
            self.revealedItemID = item.id
            self.revealedValue = value
        }
    }

    public func hideSelected() {
        clearReveal()
    }

    public func createPassword(app: String, username: String, password: String) async {
        let newID = VaultItem.passwordID(app: app.trimmingCharacters(in: .whitespacesAndNewlines), username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        let service = self.service
        await mutate(selecting: newID) {
            try service.createPassword(app: app, username: username, password: password)
        }
    }

    public func updateSelectedPassword(password: String) async {
        guard let item = selectedItem, let app = item.app, let username = item.username else { return }
        let service = self.service
        await mutate(selecting: item.id) {
            try service.updatePassword(app: app, username: username, password: password)
        }
    }

    public func createSecret(name: String, json: String) async {
        let newID = VaultItem.secretID(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        let service = self.service
        await mutate(selecting: newID) {
            try service.createSecret(name: name, json: json)
        }
    }

    public func updateSelectedSecret(json: String) async {
        guard let item = selectedItem, let name = item.secretName else { return }
        let service = self.service
        await mutate(selecting: item.id) {
            try service.updateSecret(name: name, json: json)
        }
    }

    public func secretJSON(for item: VaultItem) async -> String? {
        guard item.kind == .secret, let name = item.secretName else { return nil }
        let service = self.service
        var json: String?
        await run {
            try service.revealSecretJSON(name: name)
        } apply: { value in
            json = value
        }
        return json
    }

    public func secretEnvironmentFile(for item: VaultItem) async -> String? {
        guard item.kind == .secret, let name = item.secretName else { return nil }
        let service = self.service
        var contents: String?
        await run {
            try service.revealSecretEnvironmentFile(name: name)
        } apply: { value in
            contents = value
        }
        return contents
    }

    public func deleteSelected() async {
        guard let item = selectedItem else { return }
        let service = self.service
        await mutate(selecting: nil) {
            switch item.kind {
            case .password:
                guard let app = item.app, let username = item.username else {
                    throw VaultUIError.invalidSelection
                }
                try service.deletePassword(app: app, username: username)
            case .secret:
                guard let name = item.secretName else {
                    throw VaultUIError.invalidSelection
                }
                try service.deleteSecret(name: name)
            }
        }
    }

    private func mutate(selecting preferredID: VaultItem.ID?, operation: @escaping () throws -> Void) async {
        let service = self.service
        await run {
            try operation()
            return try service.loadItems()
        } apply: { loadedItems in
            self.items = loadedItems
            if let preferredID, loadedItems.contains(where: { $0.id == preferredID }) {
                self.selectedItemID = preferredID
            } else {
                self.selectedItemID = loadedItems.first?.id
            }
            self.clearReveal()
        }
    }

    private func run<T>(
        operation: @escaping () throws -> T,
        apply: @escaping (T) -> Void
    ) async {
        isWorking = true
        errorMessage = nil

        let result = await Task.detached(priority: .userInitiated) {
            Result { try operation() }
        }.value

        isWorking = false
        switch result {
        case .success(let value):
            apply(value)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        if needsExternalRefresh {
            needsExternalRefresh = false
            refreshAfterExternalChange()
        }
    }

    private func clearReveal() {
        revealedItemID = nil
        revealedValue = nil
    }
}

private enum VaultUIError: LocalizedError {
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "The selected vault item is invalid."
        }
    }
}
