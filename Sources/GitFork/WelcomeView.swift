import AppKit
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            GitForkLogoView()

            Text("GitFork")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .padding(.top, 22)

            Text("A fast, focused Git client for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Button {
                store.chooseRepository()
            } label: {
                Label("Open a Repository", systemImage: "folder")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Choose a local Git repository")
            .padding(.top, 28)

            if !store.recentRepositories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT REPOSITORIES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)

                    ForEach(store.recentRepositories.prefix(5), id: \.path) { url in
                        Button {
                            store.requestOpenRepository(url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(GitForkTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(9)
                        }
                        .buttonStyle(GitForkHoverButtonStyle(.row(isSelected: false)))
                        .help("Open \(url.path)")
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                .frame(width: 450)
                .padding(.top, 32)
            }

            Spacer()

            Text("Native SwiftUI · Powered by /usr/bin/git")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), GitForkTheme.accent.opacity(0.035)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.chooseRepository()
                } label: {
                    Label("Open Repository", systemImage: "folder")
                }
                .help("Choose a local Git repository")
            }
        }
    }
}

private struct GitForkLogoView: View {
    private static let bundledIcon: NSImage? = {
        guard let iconURL = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ) else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
    }()

    var body: some View {
        Group {
            if let icon = Self.bundledIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    GitForkTheme.accent,
                                    Color(red: 0.98, green: 0.70, blue: 0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(12)
            }
        }
        .frame(width: 128, height: 128)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
        .accessibilityHidden(true)
    }
}
