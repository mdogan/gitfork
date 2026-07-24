import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        List {
            Section {
                SidebarRow(
                    title: WorkspaceSection.changes.rawValue,
                    icon: WorkspaceSection.changes.icon,
                    isSelected: store.selectedSection == .changes
                ) {
                    store.selectedSection = .changes
                    store.selectedReference = nil
                    if let change = store.changes.first {
                        store.selectChange(change, staged: change.isStaged)
                    }
                } badge: {
                    if !store.changes.isEmpty {
                        Text("\(store.changes.count)")
                    }
                }

                SidebarRow(
                    title: WorkspaceSection.history.rawValue,
                    icon: WorkspaceSection.history.icon,
                    isSelected: store.selectedSection == .history && store.selectedReference == nil
                ) {
                    store.selectReference(nil)
                } badge: {
                    EmptyView()
                }
            }

            ForEach(store.groupedReferences, id: \.0.rawValue) { kind, references in
                if !references.isEmpty {
                    Section(kind.title) {
                        ForEach(references) { reference in
                            SidebarRow(
                                title: reference.name,
                                icon: reference.isCurrent ? "checkmark.circle.fill" : kind.icon,
                                isSelected: store.selectedReference == reference
                            ) {
                                store.selectReference(reference)
                            } badge: {
                                EmptyView()
                            }
                            .contextMenu {
                                Button("Show History") {
                                    store.selectReference(reference)
                                }
                                Divider()
                                Button(reference.kind == .tag ? "Checkout Detached" : "Checkout") {
                                    store.checkout(reference)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            RepositoryIdentityView()
        }
    }
}

private struct SidebarRow<Badge: View>: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let badge: () -> Badge

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? GitForkTheme.accent : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
                badge()
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(title)")
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? GitForkTheme.accent.opacity(0.13) : .clear)
        )
    }
}

private struct RepositoryIdentityView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(GitForkTheme.accent.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.repositoryName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(store.repositoryURL?.deletingLastPathComponent().path ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                Button {
                    store.chooseRepository()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Open another repository")
            }
            .padding(10)
            .background(.bar)
        }
    }
}
