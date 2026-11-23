import SwiftUI

@main
struct StillzeitApp: App {

  init() {
    // Figtree registrieren, Navigationsleiste/Segmente an 2.0 anpassen.
    MhDarstellung.einrichten()
    AppSettings.migrationAusfuehren()
    // Nur im UI-Test für Bildschirmfotos (Launch-Argument): Testdaten.
    Bildschirmfotos.vorbereiten()
    // Ohne mindestens eine Datei blendet iOS den App-Ordner in der
    // „Dateien“-App aus – dort liegen aber client.crt/client.key.
    AppOrdner.sichtbarMachen()
    // Nimmt Anfragen der Apple Watch entgegen (WatchConnectivity).
    PhoneWatchBridge.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
        .tint(Mh.link)
    }
  }
}
