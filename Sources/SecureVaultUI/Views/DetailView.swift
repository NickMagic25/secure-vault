import AppKit
import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: VaultViewModel
    let onNewPassword: () -> Void
    let onNewSecret: () -> Void

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: item)
                        revealedContent(for: item)
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

            timestampSummary(for: item)
        }
    }

    @ViewBuilder
    private func revealedContent(for item: VaultItem) -> some View {
        switch viewModel.selectedRevealedValue {
        case .password(let password):
            VStack(alignment: .leading, spacing: 0) {
                revealedActionBar(title: "Password") {
                    viewModel.hideSelected()
                } copyAction: {
                    copyToPasteboard(password)
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(password)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.28))
            )
        case .secretJSON(let json):
            VStack(alignment: .leading, spacing: 0) {
                revealedActionBar(title: "Secret") {
                    viewModel.hideSelected()
                } copyAction: {
                    copyToPasteboard(json)
                }

                Divider()

                secretFields(json: json)
            }
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.28))
            )
        default:
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
            .padding(12)
            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.28))
            )
        }
    }

    @ViewBuilder
    private func secretFields(json: String) -> some View {
        if let rows = try? SecretField.rows(from: json) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Key Values")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            SecretFieldRow(field: row) {
                                copyToPasteboard(row.value)
                            }
                            if index < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        } else {
            ScrollView {
                Text(json)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 180, maxHeight: 420)
            .padding(8)
        }
    }

    private func revealedActionBar(
        title: String,
        hideAction: @escaping () -> Void,
        copyAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Spacer()
            iconButton("Hide", systemImage: "eye.slash", action: hideAction)
            iconButton("Copy", systemImage: "doc.on.doc", action: copyAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func timestampSummary(for item: VaultItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Created \(item.createdAt.localVaultTimestamp)")
            Text("Updated \(item.updatedAt.localVaultTimestamp)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
    }
}

struct DetailsSheet: View {
    let item: VaultItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.title2)
                .fontWeight(.semibold)

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
                detailRow("Created", item.createdAt.localVaultTimestamp)
                detailRow("Updated", item.updatedAt.localVaultTimestamp)
            }
            .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(2)
        }
    }
}

private struct SecretFieldRow: View {
    let field: SecretField
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(field.key)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
                .frame(width: 180, alignment: .leading)

            Text(field.value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Copy \(field.key)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private extension String {
    var localVaultTimestamp: String {
        guard let date = Self.vaultTimestampParser.date(from: self)
            ?? Self.vaultTimestampFractionalParser.date(from: self) else {
            return self
        }
        return Self.vaultTimestampDisplay.string(from: date)
    }

    static let vaultTimestampParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let vaultTimestampFractionalParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let vaultTimestampDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
