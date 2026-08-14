import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {

  @Published var laedt = true
  @Published var fehler: String?
  @Published var stats: TodayStats?
  @Published var eintraege: [Entry] = []

  /// Für die Schnell-Eingabe gewählte Uhrzeit; nil = "Jetzt".
  @Published var schnellZeit: Date?

  /// Kurzmeldungen (Fehler bei Aktionen, Backup-Ergebnisse).
  @Published var meldung: String?

  private var service: EntryService = createConfiguredEntryService()
  private var beobachter: AnyCancellable?

  init() {
    // Schreibzugriffe der Uhr lösen ein Neuladen aus.
    beobachter = NotificationCenter.default
      .publisher(for: .stillzeitWatchAenderung)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.aktualisieren() }
  }

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    service = createConfiguredEntryService()
    aktualisieren()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
      do {
        async let statsNeu = service.getToday()
        async let eintraegeNeu = service.getEntries()
        let (s, e) = try await (statsNeu, eintraegeNeu)
        stats = s
        eintraege = e
        laedt = false
      } catch {
        fehler = error.localizedDescription
        laedt = false
      }
    }
  }

  /// Gewählte Uhrzeit als heutiger Zeitpunkt, oder nil für "Jetzt".
  private var schnellZeitpunkt: Date? {
    guard let zeit = schnellZeit else { return nil }
    let teile = Calendar.current.dateComponents([.hour, .minute], from: zeit)
    return Calendar.current.date(
      bySettingHour: teile.hour ?? 0, minute: teile.minute ?? 0, second: 0, of: Date())
  }

  func anlegen(
    seite: Seite, menge: Int? = nil, flaschenArt: FlaschenArt? = nil, dauerMinuten: Int? = nil
  ) {
    fuehreAus { [self] in
      try await service.createEntry(
        seite: seite, menge: menge, flaschenArt: flaschenArt,
        dauerMinuten: dauerMinuten, createTime: schnellZeitpunkt)
    }
  }

  func flascheAendern(_ eintrag: Entry, menge: Int, flaschenArt: FlaschenArt) {
    fuehreAus { [self] in
      try await service.updateFlasche(id: eintrag.id, menge: menge, flaschenArt: flaschenArt)
    }
  }

  func dauerAendern(_ eintrag: Entry, dauerMinuten: Int) {
    fuehreAus { [self] in
      try await service.updateDauer(id: eintrag.id, dauerMinuten: dauerMinuten)
    }
  }

  func loeschen(_ eintrag: Entry) {
    fuehreAus { [self] in try await service.deleteEntry(id: eintrag.id) }
  }

  /// Führt eine schreibende Aktion aus und lädt danach neu. Eine gewählte
  /// Schnell-Eingabe-Zeit wird danach auf "Jetzt" zurückgesetzt.
  private func fuehreAus(_ aktion: @escaping () async throws -> Void) {
    Task {
      do {
        try await aktion()
        schnellZeit = nil
        aktualisieren()
      } catch {
        meldung = "Fehler: \(error.localizedDescription)"
      }
    }
  }
}
