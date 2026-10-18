import SwiftUI

@main
struct KratosClapApp: App {
    @StateObject private var engine = ClapEngine()
    @StateObject private var log = TakeLogStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(log)
                .preferredColorScheme(.dark)
                .onAppear {
                    // L'écran ne se met jamais en veille pendant le tournage
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
