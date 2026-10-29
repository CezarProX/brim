import SwiftUI

/// Connections: live previews of what the notch shows for music, calls and app activity.
struct ConnectionsSettingsView: View {
    @State private var selectedTool: IslandActivity?

    var body: some View {
        Group {
            SettingsSection(
                "Music",
                footer: "Music and calls are detected automatically in your running apps. macOS may require a one-time permission for an app. Activity never opens the notch automatically."
            ) {
                preview { NowPlayingView(model: .shared) }
            }
            SettingsSection("Calls") {
                preview { CallActivityView(model: .shared) }
            }
            SettingsSection(
                "Activities",
                footer: "Some controls depend on the app’s version and language. Brim shows only the actions it can identify in the running app."
            ) {
                preview { ActivityToolsView(center: .shared, selection: $selectedTool).frame(height: 320) }
            }
        }
    }

    /// The island's own view, on the island's black, so it reads as a preview of the notch.
    private func preview<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(.vertical, 4)
    }
}
