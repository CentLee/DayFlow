import SwiftUI

@main
struct DayFlowApp: App {
    @State private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appStore)
        }
    }
}

