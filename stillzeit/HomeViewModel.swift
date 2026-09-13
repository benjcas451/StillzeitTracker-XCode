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

  /// Server-Option „Brei & Wasser“ des aktiven Zugangs. Vor dem ersten
  /// Netzwerk-Roundtrip aus dem Cache/Demo-Toggle geseedet.
  @Published var breiWasserAktiv = AppSettings.breiWasserAktivFuerAktuellenZugang()

  /// Grund der abgebrochenen Verbindung; nil heisst „online“.
  @Published var offlineGrund: String?
  /// Anzahl der Schreibzugriffe, die noch auf Übertragung warten.
  @Published var ausstehend = 0
  /// IDs, deren Stand noch nicht beim Server ist – die Liste markiert sie.
  @Published var ausstehendeIds: Set<Int64> = []

  private var service: EntryService = createConfiguredEntryService(offlineFaehig: true)
  private var beobachter: Set<AnyCancellable> = []

  init() {
    // Schreibzugriffe der Uhr lösen ein Neuladen aus.
    NotificationCenter.default
      .publisher(for: .stillzeitWatchAenderung)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.aktualisieren() }
      .store(in: &beobachter)

    // Den Offline-Zustand übernehmen, statt ihn doppelt zu führen.
    let status = OfflineStatus.shared
    status.$grund.assign(to: &$offlineGrund)
    status.$ausstehend.assign(to: &$ausstehend)
    status.$ausstehendeIds.assign(to: &$ausstehendeIds)

    // Sobald wieder ein Netzwerkpfad da ist, die Warteschlange abarbeiten –
    // ohne dass der Nutzer etwas antippen muss.
    Verbindungswache.shared.wiederVerbunden
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.aktualisieren() }
      .store(in: &beobachter)
  }

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    // Der Hinweis des alten Zugangs darf nicht über dem neuen stehen bleiben;
    // die neue Datenquelle meldet ihren eigenen Stand sofort nach.
    OfflineStatus.shared.zuruecksetzen()
    service = createConfiguredEntryService(offlineFaehig: true)
    // Buttons sofort korrekt zeigen, bevor die erste Antwort da ist.
    breiWasserAktiv = AppSettings.breiWasserAktivFuerAktuellenZugang()
    aktualisieren()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
      // Erst das Liegengebliebene loswerden, dann laden: sonst zeigte die
      // Liste einen Serverstand ohne die eigenen Einträge.
      await warteschlangeAbarbeiten()
      do {
        async let statsNeu = service.getToday()
        async let eintraegeNeu = service.getEntries()
        var (s, e) = try await (statsNeu, eintraegeNeu)
        AppSettings.merkeBreiWasserAktiv(s.breiWasserAktiv)
        // Sichtbar nur, wenn auch das lokale Opt-in aktiv ist – die
        // Server-Option allein blendet nichts ein.
        let sichtbar = s.breiWasserAktiv && AppSettings.breiWasserAktiviert
        s.breiWasserAktiv = sichtbar
        stats = s
        eintraege = e
        breiWasserAktiv = sichtbar
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

  func mengeAendern(_ eintrag: Entry, menge: Int) {
    fuehreAus { [self] in
      try await service.updateMenge(id: eintrag.id, menge: menge)
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

  /// Schickt die offenen Schreibzugriffe zum Server. Verworfene Aktionen
  /// (vom Server inhaltlich zurückgewiesen) meldet sie einmal gesammelt.
  private func warteschlangeAbarbeiten() async {
    guard let offline = service as? OfflineService else { return }
    let verworfen = await offline.nachholen()
    guard !verworfen.isEmpty else { return }
    meldung = verworfen.count == 1
      ? "Eine wartende Änderung wurde vom Server abgelehnt: \(verworfen[0])"
      : "\(verworfen.count) wartende Änderungen wurden vom Server abgelehnt."
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
