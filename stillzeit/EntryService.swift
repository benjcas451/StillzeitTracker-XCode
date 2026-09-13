import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  /// Gesetzt, wenn der Fehler ein Verbindungsproblem war – entscheidet
  /// darüber, ob die Aktion in die Offline-Warteschlange darf.
  var netzfehler: Netzfehler?
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
///
/// `offlineFaehig` legt die Warteschlange darüber, die bei einem
/// Verbindungsabbruch einspringt. Die Oberfläche will das; die Watch-Brücke
/// bewusst **nicht** — die Uhr führt eine eigene Outbox und bekäme sonst ein
/// „erledigt“ gemeldet, während der Eintrag noch beim Telefon liegt. Scheitert
/// die Übertragung, meldet die Brücke das weiterhin an die Uhr, die den
/// Eintrag dann selbst aufbewahrt und erneut schickt.
func createConfiguredEntryService(offlineFaehig: Bool = false) -> EntryService {
  let dienst = createServerOderDemoService()
  guard offlineFaehig, let zugang = aktuellerZugang() else { return dienst }
  return OfflineService(innen: dienst, zugang: zugang)
}

/// Kennung des aktuellen Zugangs (Modus + Basis-URL); nil im Demo-Modus, der
/// ohnehin lokal arbeitet und keine Warteschlange braucht.
private func aktuellerZugang() -> String? {
  switch AppSettings.mode {
  case .api: "api|\(AppSettings.apiBaseUrl)"
  case .apiKey: "apiKey|\(AppSettings.apiKeyBaseUrl)"
  case .cloudflare: "cloudflare|\(AppSettings.cloudflareBaseUrl)"
  case .demo: nil
  }
}

private func createServerOderDemoService() -> EntryService {
  switch AppSettings.mode {
  case .api:
    // Zusatz-Key optional: leer bedeutet „nur mTLS“, dann geht wie bisher
    // kein X-API-Key-Header raus.
    ApiService(
      baseURL: AppSettings.apiBaseUrl, certSource: CertSource(),
      apiKey: AppSettings.mtlsApiKey.isEmpty ? nil : AppSettings.mtlsApiKey)
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .cloudflare:
    // Cloudflare Access sichert den Zugang am Rand; der Zusatz-Key ist wie im
    // mTLS-Modus optional und geht nur raus, wenn er hinterlegt ist.
    ApiService(
      baseURL: AppSettings.cloudflareBaseUrl,
      apiKey: AppSettings.cloudflareApiKey.isEmpty ? nil : AppSettings.cloudflareApiKey,
      cfToken: .ausEinstellungen)
  case .demo:
    DemoService.shared
  }
}
