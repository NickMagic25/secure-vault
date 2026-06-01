import AppKit
import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: VaultViewModel
    let onNewPassword: () -> Void
    let onNewSecret: () -> Void
    let onEditPassword: (VaultItem) -> Void
    let onEditSecret: (VaultItem, String?) -> Void
    let onDelete: (VaultItem) -> Void

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: item)
                        revealedContent(for: item)
                        metadata(for: item)
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No Selection")
                .font(.title2)
            HStack {
                Button {
                    onNewPassword()
                } label: {
                    Label("Password", systemImage: "key.fill")
                }
                Button {
                    onNewSecret()
                } label: {
                    Label("Secret", systemImage: "curlybraces.square.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(for item: VaultItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button {
                Task { await viewModel.revealSelected() }
            } label: {
                Label("Reveal", systemImage: "eye")
            }
            .disabled(viewModel.isWorking)

            Menu {
                Button {
                    switch item.kind {
                    case .password:
                        onEditPassword(item)
                    case .secret:
                        onEditSecret(item, currentSecretJSON)
                    }
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    onDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
            .disabled(viewModel.isWorking)
        }
    }

    @ViewBuilder
    private func revealedContent(for item: VaultItem) -> some View {
        switch viewModel.selectedRevealedValue {
        case .password(let password):
            GroupBox("Password") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(password)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(password, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .padding(.vertical, 2)
            }
        case .secretJSON(let json):
            GroupBox("Secret") {
                VStack(alignment: .trailing, spacing: 10) {
                    ScrollView {
                        Text(json)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        default:
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Locked")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.revealSelected() }
                    } label: {
                        Label("Reveal", systemImage: "eye")
                    }
                    .disabled(viewModel.isWorking)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func metadata(for item: VaultItem) -> some View {
        GroupBox("Details") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                if let app = item.app {
                    detailRow("App", app)
                }
                if let username = item.username {
                    detailRow("Username", username)
                }
                if let secretName = item.secretName {
                    detailRow("Name", secretName)
                }
                detailRow("Key Tag", item.keyTag)
                detailRow("Created", item.createdAt)
                detailRow("Updated", item.updatedAt)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
        }
    }

    private var currentSecretJSON: String? {
        guard case .secretJSON(let json) = viewModel.selectedRevealedValue else { return nil }
        return json
    }
}
