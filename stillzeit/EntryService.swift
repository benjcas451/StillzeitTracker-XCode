import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Gemeinsame Schnittstelle für Eintrags-Quellen: die REST-API ([ApiService])
/// oder die lokale SQLite-Datenbank ([DemoService]). Sendable, damit die
/// Dienste zwischen MainActor (UI) und Hintergrund-Tasks wandern dürfen.
protocol EntryService: Sendable {
  /// Einträge von heute & gestern (neueste zuerst).
  func getEntries() async throws -> [Entry]

  /// Tagesstatistik für heute.
  func getToday() async throws -> TodayStats

  /// Neuen Eintrag anlegen.
  @discardableResult
  func createEntry(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date?
  ) async throws -> Entry

  /// Menge und Inhalt eines Flaschen-Eintrags ändern.
  func updateFlasche(id: Int64, menge: Int, flaschenArt: FlaschenArt) async throws

  /// Menge eines Brei-/Wasser-Eintrags ändern (ohne Flaschen-Art).
  func updateMenge(id: Int64, menge: Int) async throws

  /// Dauer eines Still-Eintrags ändern.
  func updateDauer(id: Int64, dauerMinuten: Int) async throws

  /// Eintrag löschen.
  func deleteEntry(id: Int64) async throws
}

/// Erstellt die aktuell konfigurierte Datenquelle. Wird von der Oberfläche und
/// von der Watch-Brücke verwendet, damit Einträge von der Uhr immer im selben
/// Datenbestand landen wie Einträge vom Telefon.
func createConfiguredEntryService() -> EntryService {
  switch AppSettings.mode {
  case .api:
    ApiService(baseURL: AppSettings.apiBaseUrl, certSource: CertSource())
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .demo:
    DemoService.shared
  }
}
