import Foundation

// MARK: - Warteschlange

/// Ein Schreibzugriff, der offline erfasst wurde und noch zum Server muss.
///
/// Änderungen und Löschungen beziehen sich immer auf eine **Server-ID**.
/// Betreffen sie einen Eintrag, der selbst noch in der Warteschlange steht,
/// werden sie direkt in dessen `anlegen`-Aktion eingearbeitet bzw. löschen
/// sie ganz — siehe `Warteschlange.aendere` und `Warteschlange.loesche`.
/// Dadurch kann beim Abarbeiten keine noch unbekannte ID auftauchen.
enum Warteaktion: Codable, Equatable {
  case anlegen(Anlegen)
  case aendern(Aendern)
  case loeschen(id: Int64)

  /// Ein offline erfasster neuer Eintrag.
  struct Anlegen: Codable, Equatable {
    /// Negative Kennung, unter der der Eintrag in der Liste auftaucht,
    /// solange er nicht hochgeladen ist.
    let lokaleId: Int64
    let seite: String
    var menge: Int?
    var flaschenArt: String?
    var dauerMinuten: Int?
    /// Zeitpunkt der Erfassung, nicht des Hochladens – sonst bekäme der
    /// Eintrag beim Nachholen die falsche Uhrzeit.
    let createTime: Date
  }

  /// Eine offline erfasste Änderung an einem bereits hochgeladenen Eintrag.
  struct Aendern: Codable, Equatable {
    let id: Int64
    var menge: Int?
    var flaschenArt: String?
    var dauerMinuten: Int?
  }
}

/// Die geordnete Liste der offenen Schreibzugriffe eines Zugangs.
struct Warteschlange: Codable, Equatable {

  private(set) var aktionen: [Warteaktion] = []
  /// Zähler für die nächste lokale Kennung (läuft ins Negative).
  private var naechsteLokaleId: Int64 = -1

  var istLeer: Bool { aktionen.isEmpty }
  var anzahl: Int { aktionen.count }

  /// Server-IDs mit noch nicht übertragenen Änderungen oder Löschungen –
  /// die Oberfläche markiert sie als ausstehend.
  var ausstehendeIds: Set<Int64> {
    var ids = Set<Int64>()
    for aktion in aktionen {
      switch aktion {
      case .anlegen(let a): ids.insert(a.lokaleId)
      case .aendern(let a): ids.insert(a.id)
      case .loeschen(let id): ids.insert(id)
      }
    }
    return ids
  }

  // MARK: Aufnehmen

  /// Nimmt einen neuen Eintrag auf und liefert dessen lokale Kennung.
  mutating func lege(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date
  ) -> Int64 {
    let id = naechsteLokaleId
    naechsteLokaleId -= 1
    aktionen.append(
      .anlegen(
        .init(
          lokaleId: id, seite: seite.apiValue, menge: menge,
          flaschenArt: flaschenArt?.apiValue, dauerMinuten: dauerMinuten,
          createTime: createTime)))
    return id
  }

  /// Nimmt eine Änderung auf. Bei einem Eintrag, der selbst noch wartet,
  /// wird dessen `anlegen`-Aktion angepasst statt eine zweite Aktion
  /// anzuhängen; bei einem bereits hochgeladenen Eintrag ersetzt die neue
  /// Änderung eine ältere für dieselbe ID.
  mutating func aendere(
    id: Int64, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?
  ) {
    if let index = indexDesAnlegens(id) {
      guard case .anlegen(var a) = aktionen[index] else { return }
      if let menge { a.menge = menge }
      if let flaschenArt { a.flaschenArt = flaschenArt.apiValue }
      if let dauerMinuten { a.dauerMinuten = dauerMinuten }
      aktionen[index] = .anlegen(a)
      return
    }
    if let index = aktionen.firstIndex(where: {
      if case .aendern(let a) = $0 { return a.id == id }
      return false
    }) {
      guard case .aendern(var a) = aktionen[index] else { return }
      if let menge { a.menge = menge }
      if let flaschenArt { a.flaschenArt = flaschenArt.apiValue }
      if let dauerMinuten { a.dauerMinuten = dauerMinuten }
      aktionen[index] = .aendern(a)
      return
    }
    aktionen.append(
      .aendern(
        .init(
          id: id, menge: menge, flaschenArt: flaschenArt?.apiValue,
          dauerMinuten: dauerMinuten)))
  }

  /// Nimmt eine Löschung auf. Einen Eintrag, der noch gar nicht beim Server
  /// war, wirft sie ersatzlos aus der Warteschlange.
  mutating func loesche(id: Int64) {
    if let index = indexDesAnlegens(id) {
      aktionen.remove(at: index)
      return
    }
    // Eine wartende Änderung wird durch die Löschung hinfällig.
    aktionen.removeAll {
      if case .aendern(let a) = $0 { return a.id == id }
      return false
    }
    aktionen.append(.loeschen(id: id))
  }

  /// Entfernt die erste Aktion – nach erfolgreichem Senden.
  mutating func entferneErste() {
    if !aktionen.isEmpty { aktionen.removeFirst() }
  }

  private func indexDesAnlegens(_ id: Int64) -> Int? {
    guard id < 0 else { return nil }
    return aktionen.firstIndex {
      if case .anlegen(let a) = $0 { return a.lokaleId == id }
      return false
    }
  }

  // MARK: Anwenden

  /// Legt die offenen Aktionen über eine Liste vom Server (bzw. aus dem
  /// Zwischenspeicher), damit die Oberfläche den Stand zeigt, den der Nutzer
  /// erwartet: neueste zuerst.
  func anwenden(auf eintraege: [Entry]) -> [Entry] {
    var liste = eintraege
    for aktion in aktionen {
      switch aktion {
      case .anlegen(let a):
        guard let seite = Seite.fromApi(a.seite) else { continue }
        liste.append(
          Entry(
            id: a.lokaleId, createTime: a.createTime, seite: seite, menge: a.menge,
            flaschenArt: FlaschenArt.fromApi(a.flaschenArt), dauerMinuten: a.dauerMinuten))
      case .aendern(let a):
        guard let index = liste.firstIndex(where: { $0.id == a.id }) else { continue }
        let alt = liste[index]
        liste[index] = Entry(
          id: alt.id, createTime: alt.createTime, seite: alt.seite,
          menge: a.menge ?? alt.menge,
          flaschenArt: FlaschenArt.fromApi(a.flaschenArt) ?? alt.flaschenArt,
          dauerMinuten: a.dauerMinuten ?? alt.dauerMinuten, einheit: alt.einheit)
      case .loeschen(let id):
        liste.removeAll { $0.id == id }
      }
    }
    return liste.sorted { $0.createTime > $1.createTime }
  }

  /// Rechnet die offenen Aktionen in die Tagesstatistik ein, damit Kacheln
  /// und Liste nicht auseinanderlaufen. Nur Einträge von heute zählen.
  func anwenden(auf stats: TodayStats, heute: Date = Date()) -> TodayStats {
    var werte = stats
    let kalender = Calendar.current
    for aktion in aktionen {
      guard case .anlegen(let a) = aktion,
        kalender.isDate(a.createTime, inSameDayAs: heute),
        let seite = Seite.fromApi(a.seite)
      else { continue }
      switch seite {
      case .links: werte.links += 1
      case .rechts: werte.rechts += 1
      case .beidseitig: werte.beidseitig += 1
      case .flasche:
        werte.flasche += 1
        werte.totalMl += a.menge ?? 0
      case .brei:
        werte.brei += 1
        werte.totalGBrei += a.menge ?? 0
      case .wasser:
        werte.wasser += 1
        werte.totalMlWasser += a.menge ?? 0
      }
      // „gesamt“ zählt nur Milchmahlzeiten – wie auf dem Server.
      if !seite.istBreiWasser { werte.gesamt += 1 }
      if seite.hatDauer { werte.totalMinuten += a.dauerMinuten ?? 0 }
    }
    return werte
  }
}

// MARK: - Ablage

/// Zwischengespeicherter Lesestand eines Zugangs.
///
/// Einträge und Statistik liegen getrennt, weil die Oberfläche beide
/// nebenläufig lädt (`async let`) — in einer gemeinsamen Datei überschriebe
/// die eine Antwort die andere.
struct Lesestand<Inhalt: Codable>: Codable {
  var inhalt: Inhalt
  var stand: Date
}

/// Legt Warteschlange und Lesestand je Zugang im App-Verzeichnis ab.
///
/// Der Schlüssel ist Modus plus Basis-URL: Wer zwischen zwei Servern
/// wechselt, bekommt nicht die Einträge des anderen zu sehen und lädt auch
/// keine Warteschlange dort hoch, wo sie nicht hingehört. Die Ablage liegt in
/// `Application Support` und damit ausserhalb von `Caches` — der Lesestand
/// darf verschwinden, die Warteschlange nicht.
struct OfflineSpeicher {

  private let ordner: URL
  private let schluessel: String

  init(zugang: String) {
    // Der Zugang wandert in den Dateinamen; Sonderzeichen der URL raus.
    schluessel = zugang.map { $0.isLetterOrDigit ? $0 : "_" }.map(String.init).joined()
    let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ordner = basis.appendingPathComponent("Offline", isDirectory: true)
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
  }

  private var warteschlangeUrl: URL {
    ordner.appendingPathComponent("warteschlange_\(schluessel).json")
  }

  private var eintraegeUrl: URL {
    ordner.appendingPathComponent("eintraege_\(schluessel).json")
  }

  private var statsUrl: URL {
    ordner.appendingPathComponent("stats_\(schluessel).json")
  }

  func ladeWarteschlange() -> Warteschlange {
    guard let daten = try? Data(contentsOf: warteschlangeUrl),
      let warteschlange = try? JSONDecoder().decode(Warteschlange.self, from: daten)
    else { return Warteschlange() }
    return warteschlange
  }

  func speichere(_ warteschlange: Warteschlange) {
    guard let daten = try? JSONEncoder().encode(warteschlange) else { return }
    try? daten.write(to: warteschlangeUrl, options: .atomic)
  }

  func ladeEintraege() -> [Entry]? {
    lade(eintraegeUrl, als: [Entry].self)
  }

  func speichere(eintraege: [Entry]) {
    speichere(eintraege, nach: eintraegeUrl)
  }

  func ladeStats() -> TodayStats? {
    lade(statsUrl, als: TodayStats.self)
  }

  func speichere(stats: TodayStats) {
    speichere(stats, nach: statsUrl)
  }

  private func lade<Inhalt: Codable>(_ url: URL, als: Inhalt.Type) -> Inhalt? {
    guard let daten = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Lesestand<Inhalt>.self, from: daten).inhalt
  }

  private func speichere<Inhalt: Codable>(_ inhalt: Inhalt, nach url: URL) {
    guard let daten = try? JSONEncoder().encode(Lesestand(inhalt: inhalt, stand: Date()))
    else { return }
    try? daten.write(to: url, options: .atomic)
  }
}

extension Character {
  fileprivate var isLetterOrDigit: Bool { isLetter || isNumber }
}
