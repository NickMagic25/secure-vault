import AppKit
import SwiftUI

@MainActor
public struct ContentView: View {
    @StateObject private var viewModel: VaultViewModel
    @State private var activeSheet: VaultSheet?
    @State private var pendingDelete: VaultItem?

    public init() {
        _viewModel = StateObject(wrappedValue: VaultViewModel())
    }

    public init(viewModel: VaultViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                onNewPassword: { activeSheet = .newPassword },
                onNewSecret: { activeSheet = .newSecret },
                onCopySecretEnvironmentFile: copySecretEnvironmentFile,
                onCloneSecret: prepareSecretClone
            )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            DetailView(
                viewModel: viewModel,
                onNewPassword: { activeSheet = .newPassword },
                onNewSecret: { activeSheet = .newSecret }
            )
        }
        .frame(minWidth: 900, minHeight: 580)
        .navigationTitle("SecureVault")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let item = viewModel.selectedItem {
                    selectedItemMenu(for: item)
                }
            }
        }
        .task {
            viewModel.refresh()
            viewModel.startAutomaticRefresh()
        }
        .onDisappear {
            viewModel.stopAutomaticRefresh()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newPassword:
                PasswordEditorSheet(mode: .create) { app, username, password in
                    activeSheet = nil
                    Task { await viewModel.createPassword(app: app, username: username, password: password) }
                }
            case .editPassword(let item):
                PasswordEditorSheet(mode: .edit(item)) { _, _, password in
                    activeSheet = nil
                    Task { await viewModel.updateSelectedPassword(password: password) }
                }
            case .newSecret:
                SecretEditorSheet(mode: .create) { name, json in
                    activeSheet = nil
                    Task { await viewModel.createSecret(name: name, json: json) }
                }
            case .cloneSecret(let item, let json):
                SecretEditorSheet(mode: .clone(item, json)) { name, json in
                    activeSheet = nil
                    Task { await viewModel.createSecret(name: name, json: json) }
                }
            case .editSecret(let item, let json):
                SecretEditorSheet(mode: .edit(item, json)) { _, json in
                    activeSheet = nil
                    Task { await viewModel.updateSelectedSecret(json: json) }
                }
            case .details(let item):
                DetailsSheet(item: item)
            }
        }
        .confirmationDialog(
            "Delete Item",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                viewModel.select(item.id)
                pendingDelete = nil
                Task { await viewModel.deleteSelected() }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { item in
            Text(deleteMessage(for: item))
        }
        .alert(
            "Secure Vault",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func copySecretEnvironmentFile(_ item: VaultItem) {
        Task {
            guard let contents = await viewModel.secretEnvironmentFile(for: item) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(contents, forType: .string)
        }
    }

    private func prepareSecretClone(_ item: VaultItem) {
        Task {
            guard let json = await viewModel.secretJSON(for: item) else { return }
            activeSheet = .cloneSecret(item, json)
        }
    }

    @ViewBuilder
    private func selectedItemMenu(for item: VaultItem) -> some View {
        Menu {
            Button {
                activeSheet = .details(item)
            } label: {
                Label("Show Details", systemImage: "info.circle")
            }

            if item.kind == .secret {
                Button {
                    copySecretEnvironmentFile(item)
                } label: {
                    Label("Copy as Env File", systemImage: "doc.on.clipboard")
                }

                Button {
                    prepareSecretClone(item)
                } label: {
                    Label("Clone Secret", systemImage: "plus.square.on.square")
                }
            }

            if viewModel.isSelectedItemRevealed {
                Divider()

                Button {
                    switch item.kind {
                    case .password:
                        activeSheet = .editPassword(item)
                    case .secret:
                        activeSheet = .editSecret(item, currentSecretJSON)
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Divider()

            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More actions")
        .disabled(viewModel.isWorking)
    }

    private var currentSecretJSON: String? {
        guard case .secretJSON(let json) = viewModel.selectedRevealedValue else { return nil }
        return json
    }

    private func deleteMessage(for item: VaultItem) -> String {
        switch item.kind {
        case .password:
            return "Delete password for \(item.subtitle ?? "") on \(item.title)?"
        case .secret:
            return "Delete secret \(item.title)?"
        }
    }
}

private enum VaultSheet: Identifiable {
    case newPassword
    case editPassword(VaultItem)
    case newSecret
    case cloneSecret(VaultItem, String?)
    case editSecret(VaultItem, String?)
    case details(VaultItem)

    var id: String {
        switch self {
        case .newPassword: "new-password"
        case .editPassword(let item): "edit-password-\(item.id)"
        case .newSecret: "new-secret"
        case .cloneSecret(let item, _): "clone-secret-\(item.id)"
        case .editSecret(let item, _): "edit-secret-\(item.id)"
        case .details(let item): "details-\(item.id)"
        }
    }
}
