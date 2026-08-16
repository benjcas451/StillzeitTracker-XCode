import Foundation

/// Welche Datenquelle die App verwendet. Rohwerte identisch zur Flutter-App.
enum DataSourceMode: String {
  /// Die mTLS-Server-API.
  case api
  /// Server-API mit API-Key (X-API-Key-Header) statt Client-Zertifikat.
  case apiKey
  /// Immer die lokale SQLite-Datenbank.
  case demo
}

/// Lädt und speichert App-Einstellungen (UserDefaults).
///
/// Beim ersten Start nach dem Umstieg von der Flutter-App werden deren Werte
/// übernommen: Flutters shared_preferences speichert auf iOS in denselben
/// UserDefaults, nur mit dem Präfix `flutter.` (gleiche Bundle-ID = gleicher
/// Container, deshalb funktioniert das nahtlos).
enum AppSettings {

  // Computed statt stored: UserDefaults ist thread-sicher, aber als
  // gespeicherte Globale würde der Compiler Sendable-Warnungen melden.
  private static var defaults: UserDefaults { .standard }

  private enum Key {
    static let mode = "data_source_mode"
    static let apiKey = "api_key"
    static let apiBaseUrl = "api_base_url"
    static let apiKeyBaseUrl = "api_key_base_url"
    static let migriert = "migriert_von_flutter"
  }

  static func migrationAusfuehren() {
    guard !defaults.bool(forKey: Key.migriert) else { return }
    for key in [Key.mode, Key.apiKey, Key.apiBaseUrl, Key.apiKeyBaseUrl] {
      if defaults.object(forKey: key) == nil,
        let wert = defaults.string(forKey: "flutter." + key)
      {
        defaults.set(wert, forKey: key)
      }
    }
    defaults.set(true, forKey: Key.migriert)
  }

  static var mode: DataSourceMode {
    get { defaults.string(forKey: Key.mode).flatMap(DataSourceMode.init) ?? .demo }
    set { defaults.set(newValue.rawValue, forKey: Key.mode) }
  }

  static var apiKey: String {
    get { defaults.string(forKey: Key.apiKey) ?? "" }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.apiKey) }
  }

  /// Basis-URL der mTLS-API; leer, solange keine hinterlegt ist.
  static var apiBaseUrl: String {
    get { ladeUrl(Key.apiBaseUrl) }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.apiBaseUrl) }
  }

  /// Basis-URL der API-Key-API; leer, solange keine hinterlegt ist.
  static var apiKeyBaseUrl: String {
    get { ladeUrl(Key.apiKeyBaseUrl) }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: Key.apiKeyBaseUrl) }
  }

  /// Demo-Modus: lokale Entsprechung der Server-Option „Brei & Wasser“.
  static var breiWasserDemoAktiv: Bool {
    get { defaults.bool(forKey: "brei_wasser_demo_aktiv") }
    set { defaults.set(newValue, forKey: "brei_wasser_demo_aktiv") }
  }

  /// Zuletzt vom Server gemeldeter Stand der Option „Brei & Wasser“ –
  /// pro Zugang (Modus + Basis-URL) gehalten, weil die Option je Familie
  /// geschaltet wird. Im Demo-Modus gilt stattdessen [breiWasserDemoAktiv].
  static func breiWasserAktivFuerAktuellenZugang() -> Bool {
    switch mode {
    case .demo: breiWasserDemoAktiv
    default: defaults.bool(forKey: breiWasserCacheKey())
    }
  }

  /// Cache nach erfolgreichem `?action=heute` aktualisieren (nicht im Demo).
  static func merkeBreiWasserAktiv(_ aktiv: Bool) {
    guard mode != .demo else { return }
    defaults.set(aktiv, forKey: breiWasserCacheKey())
  }

  private static func breiWasserCacheKey() -> String {
    let baseUrl =
      switch mode {
      case .api: apiBaseUrl
      case .apiKey: apiKeyBaseUrl
      case .demo: ""
      }
    return "brei_wasser_aktiv:\(mode.rawValue):\(baseUrl)"
  }

  private static func ladeUrl(_ key: String) -> String {
    let url = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    if url.isEmpty { return "" }
    return url.hasSuffix("/") ? url : url + "/"
  }
}
