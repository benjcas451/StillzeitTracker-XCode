import Combine
import Foundation
import Network

/// Der Offline-Zustand, den die Oberfläche anzeigt.
@MainActor
final class OfflineStatus: ObservableObject {

  static let shared = OfflineStatus()

  /// Grund der letzten gescheiterten Verbindung; nil heisst „online“.
  @Published private(set) var grund: String?
  /// Anzahl der Schreibzugriffe, die noch auf Übertragung warten.
  @Published private(set) var ausstehend = 0
  /// IDs, deren Stand noch nicht beim Server ist (lokale sind negativ).
  @Published private(set) var ausstehendeIds: Set<Int64> = []

  var istOffline: Bool { grund != nil }

  fileprivate func melde(grund: String?) { self.grund = grund }

  fileprivate func melde(warteschlange: Warteschlange) {
    ausstehend = warteschlange.anzahl
    ausstehendeIds = warteschlange.ausstehendeIds
  }

  /// Setzt alles zurück – beim Wechsel der Datenquelle, damit der Hinweis
  /// des alten Zugangs nicht über dem neuen stehen bleibt.
  func zuruecksetzen() {
    grund = nil
    ausstehend = 0
    ausstehendeIds = []
  }
}

/// Legt sich über die Server-Quelle und hält die App bei einem
/// Verbindungsabbruch benutzbar.
///
/// Lesen: Bei jedem Netzwerkfehler wird der zuletzt erfolgreiche Stand
/// gezeigt — dabei ist gleich, ob die Anfrage ankam, denn ein Lesevorgang
/// verändert nichts.
///
/// Schreiben: In die Warteschlange darf eine Aktion **nur**, wenn sie den
/// Server nachweislich nie erreicht hat (`Netzfehler.nieGesendet`). Bei einer
/// Zeitüberschreitung oder einem Abbruch mitten in der Übertragung könnte der
/// Server sie bereits ausgeführt haben; ein zweiter Versuch legte dann einen
/// zweiten Eintrag an. Solche Fälle melden wie bisher einen Fehler.
///
/// Die Uhr benutzt diesen Umweg bewusst nicht: sie führt eine eigene Outbox
/// und würde denselben Eintrag sonst zweimal einreihen.
final class OfflineService: EntryService {

  private let innen: EntryService
  private let speicher: OfflineSpeicher

  // Warteschlange und Zustand werden nur über `sperre` angefasst; die
  // Dienste wandern zwischen MainActor und Hintergrund-Tasks.
  private let sperre = NSLock()
  nonisolated(unsafe) private var warteschlange: Warteschlange

  init(innen: EntryService, zugang: String) {
    self.innen = innen
    self.speicher = OfflineSpeicher(zugang: zugang)
    self.warteschlange = speicher.ladeWarteschlange()
    meldeStand()
  }

  // MARK: - Lesen

  func getEntries() async throws -> [Entry] {
    do {
      let vomServer = try await innen.getEntries()
      speicher.speichere(eintraege: vomServer)
      await online()
      return aktuelleWarteschlange.anwenden(auf: vomServer)
    } catch let fehler as ServiceError where fehler.netzfehler != nil {
      guard let stand = speicher.ladeEintraege() else { throw fehler }
      await offline(fehler.message)
      return aktuelleWarteschlange.anwenden(auf: stand)
    }
  }

  func getToday() async throws -> TodayStats {
    do {
      let vomServer = try await innen.getToday()
      speicher.speichere(stats: vomServer)
      await online()
      return aktuelleWarteschlange.anwenden(auf: vomServer)
    } catch let fehler as ServiceError where fehler.netzfehler != nil {
      guard let stand = speicher.ladeStats() else { throw fehler }
      await offline(fehler.message)
      return aktuelleWarteschlange.anwenden(auf: stand)
    }
  }

  // MARK: - Schreiben

  @discardableResult
  func createEntry(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date?
  ) async throws -> Entry {
    // Offline steht der Erfassungszeitpunkt fest, sonst bekäme der Eintrag
    // beim Nachholen die Uhrzeit des Hochladens.
    let zeit = createTime ?? Date()
    guard aktuelleWarteschlange.istLeer else {
      // Reihenfolge wahren: Steht schon etwas an, gehört auch das Neue
      // hinten dran, statt es am Stau vorbeizuschicken.
      return reiheEin(
        seite: seite, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten,
        createTime: zeit)
    }
    do {
      let entry = try await innen.createEntry(
        seite: seite, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten,
        createTime: createTime)
      await online()
      return entry
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      return reiheEin(
        seite: seite, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten,
        createTime: zeit)
    }
  }

  func updateFlasche(id: Int64, menge: Int, flaschenArt: FlaschenArt) async throws {
    try await aendere(id: id, menge: menge, flaschenArt: flaschenArt, dauerMinuten: nil) {
      try await self.innen.updateFlasche(id: id, menge: menge, flaschenArt: flaschenArt)
    }
  }

  func updateMenge(id: Int64, menge: Int) async throws {
    try await aendere(id: id, menge: menge, flaschenArt: nil, dauerMinuten: nil) {
      try await self.innen.updateMenge(id: id, menge: menge)
    }
  }

  func updateDauer(id: Int64, dauerMinuten: Int) async throws {
    try await aendere(id: id, menge: nil, flaschenArt: nil, dauerMinuten: dauerMinuten) {
      try await self.innen.updateDauer(id: id, dauerMinuten: dauerMinuten)
    }
  }

  func deleteEntry(id: Int64) async throws {
    if id < 0 || !aktuelleWarteschlange.istLeer {
      // Negative IDs kennt nur die App: der Eintrag wartet noch. Und solange
      // etwas ansteht, bleibt die Reihenfolge gewahrt.
      schreibeWarteschlange { $0.loesche(id: id) }
      return
    }
    do {
      try await innen.deleteEntry(id: id)
      await online()
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      schreibeWarteschlange { $0.loesche(id: id) }
    }
  }

  private func aendere(
    id: Int64, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?,
    direkt: @escaping () async throws -> Void
  ) async throws {
    if id < 0 || !aktuelleWarteschlange.istLeer {
      schreibeWarteschlange {
        $0.aendere(id: id, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten)
      }
      return
    }
    do {
      try await direkt()
      await online()
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      schreibeWarteschlange {
        $0.aendere(id: id, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten)
      }
    }
  }

  // MARK: - Nachholen

  /// Arbeitet die Warteschlange von vorn ab.
  ///
  /// Bricht beim ersten Verbindungsfehler ab — der Rest bleibt in der
  /// Reihenfolge stehen. Weist der Server eine Aktion inhaltlich zurück
  /// (etwa ein längst gelöschter Eintrag), fliegt sie raus und wird gemeldet;
  /// sonst blockierte sie die Warteschlange für immer.
  ///
  /// Liefert die Meldungen zu verworfenen Aktionen.
  @discardableResult
  func nachholen() async -> [String] {
    var verworfen: [String] = []
    while let naechste = aktuelleWarteschlange.aktionen.first {
      do {
        try await sende(naechste)
        schreibeWarteschlange { $0.entferneErste() }
      } catch let fehler as ServiceError where fehler.netzfehler != nil {
        await offline(fehler.message)
        return verworfen
      } catch {
        schreibeWarteschlange { $0.entferneErste() }
        verworfen.append(error.localizedDescription)
      }
    }
    await online()
    return verworfen
  }

  private func sende(_ aktion: Warteaktion) async throws {
    switch aktion {
    case .anlegen(let a):
      guard let seite = Seite.fromApi(a.seite) else {
        throw ServiceError(message: "Unbekannte Eintragsart: \(a.seite)")
      }
      _ = try await innen.createEntry(
        seite: seite, menge: a.menge, flaschenArt: FlaschenArt.fromApi(a.flaschenArt),
        dauerMinuten: a.dauerMinuten, createTime: a.createTime)
    case .aendern(let a):
      if let menge = a.menge, let art = FlaschenArt.fromApi(a.flaschenArt) {
        try await innen.updateFlasche(id: a.id, menge: menge, flaschenArt: art)
      } else if let menge = a.menge {
        try await innen.updateMenge(id: a.id, menge: menge)
      } else if let dauer = a.dauerMinuten {
        try await innen.updateDauer(id: a.id, dauerMinuten: dauer)
      }
    case .loeschen(let id):
      try await innen.deleteEntry(id: id)
    }
  }

  // MARK: - Innere Hilfen

  private var aktuelleWarteschlange: Warteschlange {
    sperre.withLock { warteschlange }
  }

  private func reiheEin(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date
  ) -> Entry {
    var id: Int64 = -1
    schreibeWarteschlange {
      id = $0.lege(
        seite: seite, menge: menge, flaschenArt: flaschenArt, dauerMinuten: dauerMinuten,
        createTime: createTime)
    }
    return Entry(
      id: id, createTime: createTime, seite: seite, menge: menge, flaschenArt: flaschenArt,
      dauerMinuten: dauerMinuten)
  }

  private func schreibeWarteschlange(_ aenderung: (inout Warteschlange) -> Void) {
    let stand: Warteschlange = sperre.withLock {
      aenderung(&warteschlange)
      return warteschlange
    }
    speicher.speichere(stand)
    meldeStand()
  }

  private func meldeStand() {
    let stand = aktuelleWarteschlange
    Task { @MainActor in OfflineStatus.shared.melde(warteschlange: stand) }
  }

  @MainActor private func offline(_ grund: String) {
    OfflineStatus.shared.melde(grund: grund)
  }

  @MainActor private func online() {
    OfflineStatus.shared.melde(grund: nil)
  }
}

// MARK: - Verbindungswache

/// Meldet, sobald wieder ein Netzwerkpfad da ist — damit die Warteschlange
/// nicht erst beim nächsten Antippen abgearbeitet wird.
@MainActor
final class Verbindungswache: ObservableObject {

  static let shared = Verbindungswache()

  /// Feuert bei jedem Wechsel von „kein Pfad“ zu „Pfad da“.
  let wiederVerbunden = PassthroughSubject<Void, Never>()

  private let wache = NWPathMonitor()
  private var warOffline = false

  private init() {
    wache.pathUpdateHandler = { [weak self] pfad in
      let verbunden = pfad.status == .satisfied
      Task { @MainActor in self?.pfadGeaendert(verbunden) }
    }
    wache.start(queue: DispatchQueue(label: "stillzeit.verbindungswache"))
  }

  private func pfadGeaendert(_ verbunden: Bool) {
    if verbunden, warOffline { wiederVerbunden.send(()) }
    warOffline = !verbunden
  }
}
