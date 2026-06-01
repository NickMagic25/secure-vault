import AppKit
import Foundation
import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: VaultViewModel
    let onNewPassword: () -> Void
    let onNewSecret: () -> Void
    let onCopySecretEnvironmentFile: (VaultItem) -> Void
    let onCloneSecret: (VaultItem) -> Void
    let onDeleteItem: (VaultItem) -> Void

    @State private var selectionID: VaultItem.ID?
    @State private var expandedKinds = Set(VaultItemKind.allCases)
    @State private var hoveredKind: VaultItemKind?
    @State private var hoveredItemID: VaultItem.ID?

    var body: some View {
        List {
            Section {
                sidebarAction("New Password", systemImage: "key.fill", action: onNewPassword)
                sidebarAction("New Secret", systemImage: "curlybraces.square.fill", action: onNewSecret)
            }

            itemSection(.password)
            itemSection(.secret)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .environment(\.defaultMinListRowHeight, 18)
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
    private func itemSection(_ kind: VaultItemKind) -> some View {
        let items = viewModel.filteredItems.filter { $0.kind == kind }
        Section {
            groupHeader(kind)
                .listRowBackground(Color.clear)
                .listRowInsets(sidebarRowInsets)

            if expandedKinds.contains(kind) {
                ForEach(items) { item in
                    let isRevealed = viewModel.selectedItemID == item.id && viewModel.isSelectedItemRevealed
                    let isHovered = hoveredItemID == item.id
                    let isSelected = selectionID == item.id

                    SidebarItemRow(
                        item: item,
                        title: sidebarTitle(for: item),
                        isHovered: isHovered,
                        isSelected: isSelected,
                        isRevealed: isRevealed,
                        isWorking: viewModel.isWorking,
                        onSelect: { select(item) },
                        onHoverChange: { updateHoveredItem(item, isHovered: $0) },
                        onRevealToggle: { revealToggle(item, isRevealed: isRevealed) },
                        onCopySecretEnvironmentFile: { copySecretEnvironmentFile(item) },
                        onCloneSecret: { cloneSecret(item) },
                        onDeleteItem: { deleteItem(item) }
                    )
                        .listRowBackground(Color.clear)
                        .listRowInsets(sidebarItemInsets)
                }
            }
        }
    }

    private func sidebarAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sidebarLabel(title, systemImage: systemImage, weight: .medium)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(sidebarRowInsets)
    }

    private func groupHeader(_ kind: VaultItemKind) -> some View {
        Button {
            toggleExpansion(for: kind)
        } label: {
            HStack(spacing: 8) {
                sidebarLabel(kind.title, systemImage: kind.systemImage, weight: .semibold)

                Spacer(minLength: 8)

                Image(systemName: expandedKinds.contains(kind) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(hoveredKind == kind ? 1 : 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredKind = isHovered ? kind : nil
        }
    }

    private func sidebarLabel(
        _ title: String,
        systemImage: String,
        weight: Font.Weight
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)

            Text(title)
                .font(.callout)
                .fontWeight(weight)
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

    private func deleteItem(_ item: VaultItem) {
        select(item)
        onDeleteItem(item)
    }

    private func select(_ item: VaultItem) {
        selectionID = item.id
        viewModel.select(item.id)
    }

    private func updateHoveredItem(_ item: VaultItem, isHovered: Bool) {
        if isHovered {
            hoveredItemID = item.id
        } else if hoveredItemID == item.id {
            hoveredItemID = nil
        }
    }

    private func sidebarTitle(for item: VaultItem) -> String {
        if item.kind == .password {
            switch (item.username, item.app) {
            case let (username?, app?):
                return "\(username)@\(app)"
            case let (username?, nil):
                return username
            case let (nil, app?):
                return app
            case (nil, nil):
                return item.title
            }
        }
        return item.title
    }

    private var sidebarRowInsets: EdgeInsets {
        EdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 4)
    }

    private var sidebarItemInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 4)
    }
}

private struct SidebarItemRow: View {
    let item: VaultItem
    let title: String
    let isHovered: Bool
    let isSelected: Bool
    let isRevealed: Bool
    let isWorking: Bool
    let onSelect: () -> Void
    let onHoverChange: (Bool) -> Void
    let onRevealToggle: () -> Void
    let onCopySecretEnvironmentFile: () -> Void
    let onCloneSecret: () -> Void
    let onDeleteItem: () -> Void

    @State private var isShowingHoverDetails = false
    @State private var hoverDetailsTask: Task<Void, Never>?
    @State private var isPointerInside = false

    var body: some View {
        GeometryReader { geometry in
            rowContent
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .background {
                    if hasRowBackground {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(rowBackground)
                            .frame(width: geometry.size.width, height: geometry.size.height + 10)
                    }
                }
        }
        .frame(height: 20)
        .background(SecondaryClickMonitor(onSecondaryClick: suppressHoverDetailsForContextMenu))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { updateHoverState($0) }
        .onDisappear {
            hoverDetailsTask?.cancel()
        }
        .popover(isPresented: $isShowingHoverDetails, arrowEdge: .trailing) {
            hoverDetails
        }
        .contextMenu {
            contextMenuContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 0)

            if isHovered {
                actionButtons
                    .fixedSize()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 3)
        .padding(.vertical, 0)
    }

    private var actionButtons: some View {
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
        .padding(.leading, 3)
        .padding(.trailing, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(isSelected ? Color.white : Color.primary)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
        return Color.clear
    }

    private var hasRowBackground: Bool {
        isSelected || isHovered
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onRevealToggle()
        } label: {
            Label(
                isRevealed ? "Hide" : "Reveal",
                systemImage: isRevealed ? "eye.slash" : "eye"
            )
        }

        if item.kind == .secret {
            Divider()

            Button {
                onCopySecretEnvironmentFile()
            } label: {
                Label("Copy as Env File", systemImage: "doc.on.clipboard")
            }

            Button {
                onCloneSecret()
            } label: {
                Label("Clone Secret", systemImage: "plus.square.on.square")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDeleteItem()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var hoverDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item.kind {
            case .password:
                Text(item.app ?? title)
                    .font(.headline)
                    .lineLimit(2)
                if let username = item.username {
                    Text("Username: \(username)")
                        .foregroundStyle(.secondary)
                }
            case .secret:
                Text(item.secretName ?? title)
                    .font(.headline)
                    .lineLimit(2)
            }

            Divider()

            detailLine("Created", item.createdAt.localSidebarTimestamp)
            detailLine("Updated", item.updatedAt.localSidebarTimestamp)
        }
        .font(.callout)
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .lineLimit(2)
        }
    }

    private func updateHoverState(_ hovered: Bool) {
        isPointerInside = hovered
        onHoverChange(hovered)
        hoverDetailsTask?.cancel()

        guard hovered else {
            isShowingHoverDetails = false
            return
        }

        hoverDetailsTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isPointerInside {
                    isShowingHoverDetails = true
                }
            }
        }
    }

    private func suppressHoverDetailsForContextMenu() {
        isShowingHoverDetails = false
        hoverDetailsTask?.cancel()
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

private struct SecondaryClickMonitor: NSViewRepresentable {
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    final class MonitoringView: NSView {
        var onSecondaryClick: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window == nil {
                removeMonitor()
            } else {
                installMonitor()
            }
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window, event.window === window else { return event }
                guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else {
                    return event
                }
                let point = convert(event.locationInWindow, from: nil)
                if bounds.contains(point) {
                    DispatchQueue.main.async {
                        self.onSecondaryClick()
                    }
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private extension String {
    var localSidebarTimestamp: String {
        guard let date = Self.sidebarTimestampParser.date(from: self)
            ?? Self.sidebarTimestampFractionalParser.date(from: self) else {
            return self
        }
        return Self.sidebarTimestampDisplay.string(from: date)
    }

    static let sidebarTimestampParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let sidebarTimestampFractionalParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let sidebarTimestampDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
