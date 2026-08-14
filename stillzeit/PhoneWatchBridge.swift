import Foundation
import WatchConnectivity

extension Notification.Name {
  /// Schreibzugriffe der Uhr — die Oberfläche lädt daraufhin neu.
  static let stillzeitWatchAenderung = Notification.Name("stillzeitWatchAenderung")
}

/// Beantwortet WatchConnectivity-Anfragen der Uhr direkt gegen die
/// konfigurierte Datenquelle (früher liefen sie über die Flutter-Engine).
/// Protokoll identisch zur Flutter-App und zur Android/Wear-Strecke:
///   Anfrage: {"action": "...", "arguments": { ... }}
///   Antwort: {"ok": true, "data": { ... }} bzw. {"ok": false, "error": "..."}
final class PhoneWatchBridge: NSObject, WCSessionDelegate {

  static let shared = PhoneWatchBridge()

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    if session.activationState != .activated {
      session.activate()
    }
  }

  // MARK: - WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    guard let action = message["action"] as? String else {
      replyHandler(["ok": false, "error": "Ungültige Anfrage der Uhr."])
      return
    }
    let arguments = message["arguments"] as? [String: Any] ?? [:]

    Task {
      do {
        let data = try await Self.fuehreAus(action, arguments)
        replyHandler(["ok": true, "data": data])
      } catch {
        replyHandler(["ok": false, "error": error.localizedDescription])
      }
    }
  }

  // MARK: - Aktionen

  private static func fuehreAus(_ action: String, _ arguments: [String: Any]) async throws
    -> [String: Any]
  {
    switch action {
    case "getConnection":
      return try verbindung()

    case "getDashboard":
      return try await dashboard(createConfiguredEntryService())

    case "createEntry":
      let service = createConfiguredEntryService()
      try await service.createEntry(
        seite: Seite.fromApi(arguments["seite"] as? String),
        menge: arguments["menge"] as? Int,
        flaschenArt: FlaschenArt.fromApi(arguments["flaschen_art"] as? String),
        dauerMinuten: arguments["dauer_minuten"] as? Int,
        createTime: (arguments["create_time"] as? String).flatMap(IsoZeit.parse))
      aenderungMelden()
      return try await dashboard(service)

    case "updateEntry":
      guard let id = (arguments["id"] as? Int).map(Int64.init) else {
        throw ServiceError(message: "Eintrags-ID fehlt.")
      }
      let seite = Seite.fromApi(arguments["seite"] as? String)
      let service = createConfiguredEntryService()
      if seite.isFlasche {
        guard let art = FlaschenArt.fromApi(arguments["flaschen_art"] as? String) else {
          throw ServiceError(message: "Flaschenart fehlt.")
        }
        try await service.updateFlasche(id: id, menge: arguments["menge"] as? Int ?? 0, flaschenArt: art)
      } else {
        try await service.updateDauer(id: id, dauerMinuten: arguments["dauer_minuten"] as? Int ?? 0)
      }
      aenderungMelden()
      return try await dashboard(service)

    default:
      throw ServiceError(message: "Unbekannte Watch-Anfrage: \(action)")
    }
  }

  /// Überträgt die eingerichtete Server-Verbindung an die Uhr, damit diese
  /// anschließend direkt mit dem Server sprechen kann. Bei der lokalen
  /// SQLite-Quelle gibt es nichts zu übernehmen.
  private static func verbindung() throws -> [String: Any] {
    switch AppSettings.mode {
    case .demo:
      return ["mode": "demo"]

    case .apiKey:
      let baseUrl = AppSettings.apiKeyBaseUrl
      guard !baseUrl.isEmpty else {
        throw ServiceError(message: "Auf dem Telefon ist keine API-URL hinterlegt.")
      }
      return ["mode": "apiKey", "base_url": baseUrl, "api_key": AppSettings.apiKey]

    case .api:
      let baseUrl = AppSettings.apiBaseUrl
      guard !baseUrl.isEmpty else {
        throw ServiceError(message: "Auf dem Telefon ist keine API-URL hinterlegt.")
      }
      let (cert, key) = try CertSource().readCredentials()
      return [
        "mode": "api",
        "base_url": baseUrl,
        "client_cert": cert.base64EncodedString(),
        "client_key": key.base64EncodedString(),
      ]
    }
  }

  private static func dashboard(_ service: EntryService) async throws -> [String: Any] {
    let eintraege = try await service.getEntries().prefix(12)
    let liste: [[String: Any]] = eintraege.map { entry in
      var json: [String: Any] = [
        "id": Int(entry.id),
        // Die Uhr erwartet eine explizite Zeitzone; UTC mit Bruchteilen wie
        // bisher (WatchEntry.parseDate deckt genau diese Form ab).
        "create_time": IsoZeit.fractional.string(from: entry.createTime),
        "seite": entry.seite.apiValue,
      ]
      if let menge = entry.menge { json["menge"] = menge }
      if let art = entry.flaschenArt { json["flaschen_art"] = art.apiValue }
      if let dauer = entry.dauerMinuten { json["dauer_minuten"] = dauer }
      return json
    }
    return ["entries": liste]
  }

  private static func aenderungMelden() {
    Task { @MainActor in
      NotificationCenter.default.post(name: .stillzeitWatchAenderung, object: nil)
    }
  }
}
