import SwiftUI

@main
struct KratosClapApp: App {
    @StateObject private var engine = ClapEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .onAppear {
                    // L'écran ne se met jamais en veille pendant le tournage
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
