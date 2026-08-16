import Foundation

/// Art des Eintrags. `apiValue` ist exakt der String, den die API erwartet.
enum Seite: String, CaseIterable, Identifiable {
  case links = "Links"
  case rechts = "Rechts"
  case beidseitig = "Beidseitig"
  case flasche = "Flasche"
  case brei = "Brei"
  case wasser = "Wasser"

  var id: String { rawValue }
  var apiValue: String { rawValue }

  /// Nur für Pre/Mutter-Belange (FlaschenArt) – nicht für die Mengenlogik.
  var isFlasche: Bool { self == .flasche }

  /// Einträge mit Pflicht-Menge (Flasche in ml, Brei in g, Wasser in ml).
  var hatMenge: Bool { self == .flasche || self == .brei || self == .wasser }

  /// Still-Einträge, bei denen `dauer_minuten` erlaubt ist.
  var hatDauer: Bool { !hatMenge }

  /// Nur anbieten, wenn die Server-Option `brei_wasser_aktiv` an ist.
  var istBreiWasser: Bool { self == .brei || self == .wasser }

  /// Anzeigeeinheit der Menge; Fallback, wenn die API kein `einheit` liefert.
  var mengenEinheit: String? {
    switch self {
    case .flasche, .wasser: "ml"
    case .brei: "g"
    default: nil
    }
  }

  /// SF-Symbol analog zu den Material-Icons der Android-App.
  var symbol: String {
    switch self {
    case .links: "chevron.left"
    case .rechts: "chevron.right"
    case .beidseitig: "arrow.left.arrow.right"
    case .flasche: "waterbottle"
    case .brei: "fork.knife"
    case .wasser: "drop.fill"
    }
  }

  /// Unbekannte Werte liefern nil – Aufrufer blenden solche Einträge aus
  /// (Listen) bzw. melden einen Fehler (Watch-Anfragen), statt sie wie
  /// früher stillschweigend als „Links“ auszugeben.
  static func fromApi(_ value: String?) -> Seite? {
    value.flatMap(Seite.init(rawValue:))
  }
}

/// Inhalt eines Flaschen-Eintrags.
enum FlaschenArt: String, CaseIterable, Identifiable {
  case pre = "Pre"
  case mutter = "Mutter"

  var id: String { rawValue }
  var apiValue: String { rawValue }

  static func fromApi(_ value: String?) -> FlaschenArt? {
    value.flatMap(FlaschenArt.init(rawValue:))
  }
}

/// Ein einzelner Stillzeit-/Flaschen-/Brei-/Wasser-Eintrag.
struct Entry: Identifiable, Equatable {
  let id: Int64
  let createTime: Date
  let seite: Seite
  /// Bei Einträgen mit `Seite.hatMenge` gesetzt, sonst nil.
  let menge: Int?
  /// Inhalt der Flasche (Pre oder Mutter). Bei älteren Einträgen nil.
  let flaschenArt: FlaschenArt?
  /// Nur bei Still-Einträgen gesetzt (Dauer in Minuten), sonst nil.
  let dauerMinuten: Int?
  /// Einheit der Menge („ml“/„g“) – vom Server geliefert, lokal abgeleitet.
  var einheit: String? = nil

  /// Einheit für die Anzeige: API-Wert, sonst aus der Seite abgeleitet.
  var anzeigeEinheit: String? { einheit ?? seite.mengenEinheit }
}

/// Tagesstatistik (`GET /api/?action=heute`).
struct TodayStats {
  var gesamt = 0
  var links = 0
  var rechts = 0
  var beidseitig = 0
  var flasche = 0
  var totalMl = 0
  var totalMinuten = 0
  /// Anzahl Brei-Einträge heute (0, solange die Option aus ist).
  var brei = 0
  /// Anzahl Wasser-Einträge heute.
  var wasser = 0
  /// Brei-Gesamtmenge heute in Gramm.
  var totalGBrei = 0
  /// Wasser-Gesamtmenge heute in Millilitern (getrennt von `totalMl`).
  var totalMlWasser = 0
  /// Server-Option „Brei & Wasser“ dieser Familie.
  var breiWasserAktiv = false
}

// MARK: - Zeitformate

/// Liest ISO-8601-Zeitstempel tolerant: mit Offset (`+02:00`), mit `Z`,
/// mit 3 oder 6 Nachkommastellen (Dart schrieb Mikrosekunden in die lokale
/// Datenbank!) oder ganz ohne Zeitzone (dann lokale Zeit, wie in Dart).
enum IsoZeit {

  static func parse(_ text: String) -> Date? {
    if let date = fractional.date(from: text) { return date }
    if let date = plain.date(from: text) { return date }
    for formatter in posixFormatter {
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }

  /// Fürs Schreiben in die lokale Datenbank: UTC mit Millisekunden, damit die
  /// lexikalische Sortierung der Strings der zeitlichen entspricht (identisch
  /// zur Android-App).
  static func dbString(from date: Date) -> String {
    fractional.string(from: date)
  }

  /// `2026-06-10T14:30:00+02:00` — so erwartet es die REST-API.
  static func apiString(from date: Date) -> String {
    apiFormatter.string(from: date)
  }

  // (ISO8601-)DateFormatter sind laut Apple-Doku thread-sicher.
  nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let posixFormatter: [DateFormatter] = [
    // Mikrosekunden (Dart), UTC
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'", utc: true),
    make("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", utc: true),
    // Offset-Formen mit Bruchteilen
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", utc: false),
    // Ohne Zeitzone: als lokale Zeit interpretieren
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", utc: false),
    make("yyyy-MM-dd'T'HH:mm:ss", utc: false),
  ]

  private static let apiFormatter = make("yyyy-MM-dd'T'HH:mm:ssXXXXX", utc: false)

  private static func make(_ format: String, utc: Bool) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    if utc { formatter.timeZone = TimeZone(identifier: "UTC") }
    return formatter
  }
}
