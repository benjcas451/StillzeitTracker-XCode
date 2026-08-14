import SwiftUI

@main
struct StillzeitApp: App {

  init() {
    NunitoFont.registrieren()
    AppSettings.migrationAusfuehren()
    // Nimmt Anfragen der Apple Watch entgegen (WatchConnectivity).
    PhoneWatchBridge.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
    }
  }
}
