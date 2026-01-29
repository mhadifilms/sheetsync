import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainPopoverView()
            .environmentObject(appState)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
