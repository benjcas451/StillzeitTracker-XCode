import SwiftUI

@main
struct StillzeitApp: App {

  init() {
    NunitoFont.registrieren()
    AppSettings.migrationAusfuehren()
    // Ohne mindestens eine Datei blendet iOS den App-Ordner in der
    // „Dateien“-App aus – dort liegen aber client.crt/client.key.
    AppOrdner.sichtbarMachen()
    // Nimmt Anfragen der Apple Watch entgegen (WatchConnectivity).
    PhoneWatchBridge.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
    }
  }
}
