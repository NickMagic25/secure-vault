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
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            DetailView(
                viewModel: viewModel,
                onNewPassword: { activeSheet = .newPassword },
                onNewSecret: { activeSheet = .newSecret },
                onEditPassword: { item in activeSheet = .editPassword(item) },
                onEditSecret: { item, json in activeSheet = .editSecret(item, json) },
                onDelete: { item in pendingDelete = item }
            )
        }
        .frame(minWidth: 900, minHeight: 580)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")

                Menu {
                    Button {
                        activeSheet = .newPassword
                    } label: {
                        Label("Password", systemImage: "key.fill")
                    }

                    Button {
                        activeSheet = .newSecret
                    } label: {
                        Label("Secret", systemImage: "curlybraces.square.fill")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add")
            }
        }
        .task {
            viewModel.refresh()
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
            case .editSecret(let item, let json):
                SecretEditorSheet(mode: .edit(item, json)) { _, json in
                    activeSheet = nil
                    Task { await viewModel.updateSelectedSecret(json: json) }
                }
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
    case editSecret(VaultItem, String?)

    var id: String {
        switch self {
        case .newPassword: "new-password"
        case .editPassword(let item): "edit-password-\(item.id)"
        case .newSecret: "new-secret"
        case .editSecret(let item, _): "edit-secret-\(item.id)"
        }
    }
}
