import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: VaultViewModel
    let onNewPassword: () -> Void
    let onNewSecret: () -> Void
    let onCopySecretEnvironmentFile: (VaultItem) -> Void
    let onCloneSecret: (VaultItem) -> Void

    @State private var selectionID: VaultItem.ID?
    @State private var expandedKinds = Set(VaultItemKind.allCases)
    @State private var hoveredKind: VaultItemKind?

    var body: some View {
        List {
            Section {
                sidebarAction("New Password", systemImage: "key.fill", action: onNewPassword)
                sidebarAction("New Secret", systemImage: "curlybraces.square.fill", action: onNewSecret)
            }

            itemSection(.password, action: onNewPassword)
            itemSection(.secret, action: onNewSecret)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .searchable(text: $viewModel.searchText, placement: .sidebar)
        .onAppear {
            selectionID = viewModel.selectedItemID
        }
        .onChange(of: selectionID) { newValue in
            guard newValue != nil else { return }
            guard newValue != viewModel.selectedItemID else { return }
            Task { @MainActor in
                viewModel.select(newValue)
            }
        }
        .onChange(of: viewModel.selectedItemID) { newValue in
            guard selectionID != newValue else { return }
            selectionID = newValue
        }
    }

    @ViewBuilder
    private func itemSection(_ kind: VaultItemKind, action: @escaping () -> Void) -> some View {
        let items = viewModel.filteredItems.filter { $0.kind == kind }
        Section {
            groupHeader(kind)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 1, trailing: 8))

            if expandedKinds.contains(kind) {
                if items.isEmpty {
                    Button(action: action) {
                        Text("Add \(kind.singularTitle)")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 30, bottom: 1, trailing: 8))
                } else {
                    ForEach(items) { item in
                        let isRevealed = viewModel.selectedItemID == item.id && viewModel.isSelectedItemRevealed

                        SidebarItemRow(
                            item: item,
                            isSelected: selectionID == item.id,
                            isRevealed: isRevealed,
                            isWorking: viewModel.isWorking,
                            onSelect: { select(item) },
                            onRevealToggle: { revealToggle(item, isRevealed: isRevealed) },
                            onCopySecretEnvironmentFile: { copySecretEnvironmentFile(item) },
                            onCloneSecret: { cloneSecret(item) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 1, trailing: 8))
                        .contextMenu {
                            contextMenu(for: item, isRevealed: isRevealed)
                        }
                    }
                }
            }
        }
    }

    private func sidebarAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .fontWeight(.medium)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func contextMenu(for item: VaultItem, isRevealed: Bool) -> some View {
        Button {
            revealToggle(item, isRevealed: isRevealed)
        } label: {
            Label(
                isRevealed ? "Hide" : "Reveal",
                systemImage: isRevealed ? "eye.slash" : "eye"
            )
        }

        if item.kind == .secret {
            Divider()

            Button {
                copySecretEnvironmentFile(item)
            } label: {
                Label("Copy as Env File", systemImage: "doc.on.clipboard")
            }

            Button {
                cloneSecret(item)
            } label: {
                Label("Clone Secret", systemImage: "plus.square.on.square")
            }
        }
    }

    private func groupHeader(_ kind: VaultItemKind) -> some View {
        Button {
            toggleExpansion(for: kind)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expandedKinds.contains(kind) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 10)
                    .opacity(hoveredKind == kind ? 1 : 0)

                Image(systemName: kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)

                Text(kind.title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredKind = isHovered ? kind : nil
        }
    }

    private func toggleExpansion(for kind: VaultItemKind) {
        if expandedKinds.contains(kind) {
            expandedKinds.remove(kind)
        } else {
            expandedKinds.insert(kind)
        }
    }

    private func revealToggle(_ item: VaultItem, isRevealed: Bool) {
        select(item)
        if isRevealed {
            viewModel.hideSelected()
        } else {
            Task { await viewModel.revealSelected() }
        }
    }

    private func copySecretEnvironmentFile(_ item: VaultItem) {
        select(item)
        onCopySecretEnvironmentFile(item)
    }

    private func cloneSecret(_ item: VaultItem) {
        select(item)
        onCloneSecret(item)
    }

    private func select(_ item: VaultItem) {
        selectionID = item.id
        viewModel.select(item.id)
    }
}

private struct SidebarItemRow: View {
    let item: VaultItem
    let isSelected: Bool
    let isRevealed: Bool
    let isWorking: Bool
    let onSelect: () -> Void
    let onRevealToggle: () -> Void
    let onCopySecretEnvironmentFile: () -> Void
    let onCloneSecret: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                actionButton(
                    isRevealed ? "Hide" : "Reveal",
                    systemImage: isRevealed ? "eye.slash" : "eye",
                    action: onRevealToggle
                )

                if item.kind == .secret {
                    actionButton(
                        "Copy as Env File",
                        systemImage: "doc.on.clipboard",
                        action: onCopySecretEnvironmentFile
                    )
                    actionButton(
                        "Clone Secret",
                        systemImage: "plus.square.on.square",
                        action: onCloneSecret
                    )
                }
            }
            .frame(width: actionWidth, alignment: .trailing)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }

    private var actionWidth: CGFloat {
        item.kind == .secret ? 68 : 22
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.22))
        }
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.08))
        }
        return AnyShapeStyle(Color.clear)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(isWorking)
        .help(title)
    }
}
