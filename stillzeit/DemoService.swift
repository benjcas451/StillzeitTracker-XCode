import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Eine Roh-Zeile der Tabelle `entries` (für Backup-Export/-Restore).
struct EntryRow {
  let id: Int64
  let createTime: String
  let seite: String
  let menge: Int?
  let flaschenArt: String?
  let dauerMinuten: Int?
}

/// Lokaler Modus: nutzt exakt die SQLite-Datenbank weiter, die schon die
/// Flutter-App (sqflite) angelegt hat – gleicher Dateiname im Documents-
/// Ordner, gleiches Schema, gleiche Version (PRAGMA user_version = 3).
/// Bestehende Daten werden beim Umstieg dadurch nahtlos übernommen.
///
/// `@unchecked Sendable`: Das einzige veränderliche Feld (`db`) wird
/// ausschließlich auf der seriellen `queue` gelesen und geschrieben – der
/// Compiler kann das bei der SQLite-C-API (OpaquePointer) nur nicht beweisen.
final class DemoService: EntryService, @unchecked Sendable {

  /// Eine Verbindung für die gesamte Prozesslaufzeit: Oberfläche, Backup und
  /// Watch-Brücke dürfen sie sich nicht gegenseitig wegschließen.
  static let shared = DemoService()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "org.dwarftsch.stillzeit.demo-db")

  private init() {}

  // MARK: - Öffnen & Schema

  private func datenbank() throws -> OpaquePointer {
    if let db { return db }
    let pfad = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("stillzeit_demo.db").path

    var handle: OpaquePointer?
    guard sqlite3_open(pfad, &handle) == SQLITE_OK, let handle else {
      throw ServiceError(message: "Lokale Datenbank ließ sich nicht öffnen.")
    }
    try migrieren(handle)
    db = handle
    return handle
  }

  /// Identisch zur sqflite-Migration der Flutter-App (Version 1 → 3).
  private func migrieren(_ db: OpaquePointer) throws {
    let version = skalarInt(db, "PRAGMA user_version") ?? 0
    if version == 0 {
      try ausfuehren(
        db,
        """
        CREATE TABLE IF NOT EXISTS entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          create_time TEXT NOT NULL,
          seite TEXT NOT NULL,
          menge INTEGER,
          flaschen_art TEXT,
          dauer_minuten INTEGER
        )
        """)
    } else {
      if version < 2 {
        try ausfuehren(db, "ALTER TABLE entries ADD COLUMN dauer_minuten INTEGER")
      }
      if version < 3 {
        try ausfuehren(db, "ALTER TABLE entries ADD COLUMN flaschen_art TEXT")
      }
    }
    if version < 3 {
      try ausfuehren(db, "PRAGMA user_version = 3")
    }
  }

  // MARK: - EntryService

  func getEntries() async throws -> [Entry] {
    try await auf { db in
      try self.zeilen(
        db, "SELECT * FROM entries WHERE create_time >= ? ORDER BY create_time DESC",
        parameter: [IsoZeit.dbString(from: Self.tagesbeginn(tageZurueck: 1))]
      ).compactMap(Self.alsEntry)
    }
  }

  func getToday() async throws -> TodayStats {
    try await auf { db in
      let rows = try self.zeilen(
        db, "SELECT * FROM entries WHERE create_time >= ?",
        parameter: [IsoZeit.dbString(from: Self.tagesbeginn())])
      var stats = TodayStats()
      for row in rows {
        switch Seite.fromApi(row.seite) {
        case .links:
          stats.links += 1
          stats.totalMinuten += row.dauerMinuten ?? 0
        case .rechts:
          stats.rechts += 1
          stats.totalMinuten += row.dauerMinuten ?? 0
        case .beidseitig:
          stats.beidseitig += 1
          stats.totalMinuten += row.dauerMinuten ?? 0
        case .flasche:
          stats.flasche += 1
          stats.totalMl += row.menge ?? 0
        case .brei:
          stats.brei += 1
          stats.totalGBrei += row.menge ?? 0
        case .wasser:
          stats.wasser += 1
          stats.totalMlWasser += row.menge ?? 0
        case nil:
          continue  // unbekannte Zeile überspringen
        }
      }
      // Wie die Server-API: gesamt zählt nur Milchmahlzeiten – Brei und
      // Wasser bewusst NICHT (Home-Assistant-Kontrakt).
      stats.gesamt = stats.links + stats.rechts + stats.beidseitig + stats.flasche
      // Lokale Entsprechung der Server-Option (Demo-Toggle).
      stats.breiWasserAktiv = AppSettings.breiWasserDemoAktiv
      return stats
    }
  }

  @discardableResult
  func createEntry(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date?
  ) async throws -> Entry {
    try await auf { db in
      let zeit = createTime ?? Date()
      try self.ausfuehren(
        db,
        "INSERT INTO entries(create_time, seite, menge, flaschen_art, dauer_minuten) VALUES(?,?,?,?,?)",
        parameter: [
          IsoZeit.dbString(from: zeit),
          seite.apiValue,
          seite.hatMenge ? (menge ?? 0) : nil,
          // Flaschen-Art gibt es nur bei der Flasche.
          seite.isFlasche ? flaschenArt?.apiValue : nil,
          seite.hatDauer ? dauerMinuten : nil,
        ])
      return Entry(
        id: sqlite3_last_insert_rowid(db),
        createTime: zeit,
        seite: seite,
        menge: seite.hatMenge ? (menge ?? 0) : nil,
        flaschenArt: seite.isFlasche ? flaschenArt : nil,
        dauerMinuten: seite.hatDauer ? dauerMinuten : nil)
    }
  }

  func updateFlasche(id: Int64, menge: Int, flaschenArt: FlaschenArt) async throws {
    try await auf { db in
      try self.ausfuehren(
        db, "UPDATE entries SET menge = ?, flaschen_art = ? WHERE id = ?",
        parameter: [menge, flaschenArt.apiValue, id])
    }
  }

  func updateMenge(id: Int64, menge: Int) async throws {
    try await auf { db in
      try self.ausfuehren(
        db, "UPDATE entries SET menge = ? WHERE id = ?", parameter: [menge, id])
    }
  }

  func updateDauer(id: Int64, dauerMinuten: Int) async throws {
    try await auf { db in
      try self.ausfuehren(
        db, "UPDATE entries SET dauer_minuten = ? WHERE id = ?", parameter: [dauerMinuten, id])
    }
  }

  func deleteEntry(id: Int64) async throws {
    try await auf { db in
      try self.ausfuehren(db, "DELETE FROM entries WHERE id = ?", parameter: [id])
    }
  }

  // MARK: - Backup

  /// Alle Roh-Zeilen der lokalen Tabelle (für den Backup-Export).
  func exportRows() async throws -> [EntryRow] {
    try await auf { db in
      try self.zeilen(db, "SELECT * FROM entries ORDER BY id", parameter: [])
    }
  }

  /// Ersetzt den gesamten Bestand durch [rows] (Backup-Restore), transaktional.
  func replaceAll(_ rows: [EntryRow]) async throws {
    try await auf { db in
      try self.ausfuehren(db, "BEGIN")
      do {
        try self.ausfuehren(db, "DELETE FROM entries")
        for row in rows {
          try self.ausfuehren(
            db,
            "INSERT INTO entries(id, create_time, seite, menge, flaschen_art, dauer_minuten) VALUES(?,?,?,?,?,?)",
            parameter: [row.id, row.createTime, row.seite, row.menge, row.flaschenArt, row.dauerMinuten])
        }
        try self.ausfuehren(db, "COMMIT")
      } catch {
        try? self.ausfuehren(db, "ROLLBACK")
        throw error
      }
    }
  }

  // MARK: - SQLite-Handwerk

  private func auf<T: Sendable>(
    _ arbeit: @Sendable @escaping (OpaquePointer) throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { fortsetzung in
      queue.async {
        do {
          fortsetzung.resume(returning: try arbeit(try self.datenbank()))
        } catch {
          fortsetzung.resume(throwing: error)
        }
      }
    }
  }

  private func ausfuehren(_ db: OpaquePointer, _ sql: String, parameter: [Any?] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
  }

  private func zeilen(_ db: OpaquePointer, _ sql: String, parameter: [Any?]) throws -> [EntryRow] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)

    // Spaltenindizes anhand der Namen, damit SELECT * robust bleibt.
    var spalten: [String: Int32] = [:]
    for index in 0..<sqlite3_column_count(statement) {
      spalten[String(cString: sqlite3_column_name(statement, index))] = index
    }
    func text(_ name: String) -> String? {
      guard let index = spalten[name],
        let wert = sqlite3_column_text(statement, index)
      else { return nil }
      return String(cString: wert)
    }
    func zahl(_ name: String) -> Int? {
      guard let index = spalten[name],
        sqlite3_column_type(statement, index) != SQLITE_NULL
      else { return nil }
      return Int(sqlite3_column_int64(statement, index))
    }

    var ergebnis: [EntryRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      ergebnis.append(
        EntryRow(
          id: Int64(zahl("id") ?? 0),
          createTime: text("create_time") ?? "",
          seite: text("seite") ?? "",
          menge: zahl("menge"),
          flaschenArt: text("flaschen_art"),
          dauerMinuten: zahl("dauer_minuten")))
    }
    return ergebnis
  }

  private func binden(_ statement: OpaquePointer?, _ parameter: [Any?]) {
    for (index, wert) in parameter.enumerated() {
      let position = Int32(index + 1)
      switch wert {
      case nil: sqlite3_bind_null(statement, position)
      case let text as String: sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
      case let zahl as Int: sqlite3_bind_int64(statement, position, Int64(zahl))
      case let zahl as Int64: sqlite3_bind_int64(statement, position, zahl)
      default: sqlite3_bind_null(statement, position)
      }
    }
  }

  private func skalarInt(_ db: OpaquePointer, _ sql: String) -> Int? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return Int(sqlite3_column_int64(statement, 0))
  }

  // MARK: - Helfer

  private static func alsEntry(_ row: EntryRow) -> Entry? {
    guard
      let zeit = IsoZeit.parse(row.createTime),
      // Zeilen unbekannter Art (z. B. aus einem neueren Backup) ausblenden.
      let seite = Seite.fromApi(row.seite)
    else { return nil }
    return Entry(
      id: row.id,
      createTime: zeit,
      seite: seite,
      menge: row.menge,
      flaschenArt: FlaschenArt.fromApi(row.flaschenArt),
      dauerMinuten: row.dauerMinuten)
  }

  /// Heutiger Tagesbeginn (lokale Zeit), optional um Tage zurückversetzt.
  private static func tagesbeginn(tageZurueck: Int = 0) -> Date {
    let start = Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(byAdding: .day, value: -tageZurueck, to: start) ?? start
  }
}
