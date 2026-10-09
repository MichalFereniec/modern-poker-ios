import SwiftUI

@main
struct ModernPokerApp: App {
    var body: some Scene {
        WindowGroup {
            ModernPokerRoot()
                .preferredColorScheme(.dark)
        }
    }
}
