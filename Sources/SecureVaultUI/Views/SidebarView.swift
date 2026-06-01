import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: VaultViewModel

    private var selection: Binding<VaultItem.ID?> {
        Binding(
            get: { viewModel.selectedItemID },
            set: { viewModel.select($0) }
        )
    }

    var body: some View {
        List(selection: selection) {
            itemSection(.password)
            itemSection(.secret)
        }
        .listStyle(.sidebar)
        .searchable(text: $viewModel.searchText, placement: .sidebar)
    }

    @ViewBuilder
    private func itemSection(_ kind: VaultItemKind) -> some View {
        let items = viewModel.filteredItems.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(kind.title) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.kind.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .tag(item.id)
                    .contextMenu {
                        Button {
                            viewModel.select(item.id)
                            Task { await viewModel.revealSelected() }
                        } label: {
                            Label("Reveal", systemImage: "eye")
                        }
                    }
                }
            }
        }
    }
}
