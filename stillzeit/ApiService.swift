import Foundation
import Security

/// Spricht die Stillzeit-Tracker-REST-API an. Authentifizierung wahlweise per
/// mTLS-Client-Zertifikat ([certSource]) oder API-Key (`X-API-Key`-Header).
/// Endpunkte und JSON-Felder identisch zur Flutter-/Android-App.
final class ApiService: NSObject, EntryService {

  private let baseURL: String
  private let apiKey: String?
  private let certSource: CertSource?
  private var identity: SecIdentity?

  private lazy var session: URLSession = URLSession(
    configuration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 20
      return configuration
    }(),
    delegate: self,
    delegateQueue: nil)

  init(baseURL: String, certSource: CertSource? = nil, apiKey: String? = nil) {
    self.baseURL = baseURL
    self.certSource = certSource
    self.apiKey = apiKey
  }

  // MARK: - EntryService

  func getEntries() async throws -> [Entry] {
    let data = try await send("GET", query: nil, body: nil)
    let raw = data["entries"] as? [[String: Any]] ?? []
    return raw.compactMap(Self.eintragAusJson)
  }

  func getToday() async throws -> TodayStats {
    let data = try await send("GET", query: "action=heute", body: nil)
    func v(_ key: String) -> Int { data[key] as? Int ?? 0 }
    return TodayStats(
      gesamt: v("gesamt"), links: v("links"), rechts: v("rechts"),
      beidseitig: v("beidseitig"), flasche: v("flasche"),
      totalMl: v("total_ml"), totalMinuten: v("total_minuten"))
  }

  @discardableResult
  func createEntry(
    seite: Seite, menge: Int?, flaschenArt: FlaschenArt?, dauerMinuten: Int?, createTime: Date?
  ) async throws -> Entry {
    var body: [String: Any] = ["seite": seite.apiValue]
    if seite.isFlasche {
      body["menge"] = menge ?? 0
      if let flaschenArt { body["flaschen_art"] = flaschenArt.apiValue }
    }
    if !seite.isFlasche, let dauerMinuten { body["dauer_minuten"] = dauerMinuten }
    if let createTime { body["create_time"] = IsoZeit.apiString(from: createTime) }
    let data = try await send("POST", query: nil, body: body)
    guard let entry = Self.eintragAusJson(data) else {
      throw ServiceError(message: "Unerwartete Antwort der API.")
    }
    return entry
  }

  func updateFlasche(id: Int64, menge: Int, flaschenArt: FlaschenArt) async throws {
    _ = try await send(
      "PATCH", query: "id=\(id)",
      body: ["menge": menge, "flaschen_art": flaschenArt.apiValue])
  }

  func updateDauer(id: Int64, dauerMinuten: Int) async throws {
    _ = try await send("PATCH", query: "id=\(id)", body: ["dauer_minuten": dauerMinuten])
  }

  func deleteEntry(id: Int64) async throws {
    _ = try await send("DELETE", query: "id=\(id)", body: nil)
  }

  // MARK: - Transport

  private func send(_ method: String, query: String?, body: [String: Any]?) async throws
    -> [String: Any]
  {
    guard !baseURL.isEmpty else {
      throw ServiceError(
        message: "Keine API-URL konfiguriert. Bitte in den Einstellungen die "
          + "Basis-URL des Servers hinterlegen.")
    }
    // Query-Form `?id=43` statt Pfad-Form – letztere braucht serverseitiges
    // URL-Rewrite und liefert sonst 404.
    let text = query == nil ? baseURL : "\(baseURL)?\(query!)"
    guard let url = URL(string: text) else {
      throw ServiceError(message: "Ungültige API-URL: \(baseURL)")
    }

    // mTLS-Identity beim ersten Zugriff aus den PEM-Dateien bauen.
    if identity == nil, let certSource {
      let (cert, key) = try certSource.readCredentials()
      identity = try ClientIdentity.make(certPEM: cert, keyPEM: key)
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey, !apiKey.isEmpty {
      request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw ServiceError(message: error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ServiceError(message: "Unerwartete Antwort des Servers.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ServiceError(message: "Fehler \(http.statusCode): \(Self.meldung(aus: data))")
    }
    if data.isEmpty { return [:] }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ServiceError(message: "Unerwartete Antwort (kein JSON).")
    }
    return json
  }

  /// Zieht `{"error": "..."}` heraus bzw. kürzt eine HTML-Fehlerseite.
  private static func meldung(aus data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["error"] as? String, !text.isEmpty
    {
      return text
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if clean.isEmpty { return "Anfrage fehlgeschlagen" }
    return clean.count > 200 ? String(clean.prefix(200)) + "…" : clean
  }

  private static func eintragAusJson(_ json: [String: Any]) -> Entry? {
    guard
      let id = json["id"] as? Int,
      let zeitText = json["create_time"] as? String,
      let zeit = IsoZeit.parse(zeitText)
    else { return nil }
    return Entry(
      id: Int64(id),
      createTime: zeit,
      seite: Seite.fromApi(json["seite"] as? String),
      menge: json["menge"] as? Int,
      flaschenArt: FlaschenArt.fromApi(json["flaschen_art"] as? String),
      dauerMinuten: json["dauer_minuten"] as? Int)
  }
}

extension ApiService: URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
      let identity
    else {
      // Server-Zertifikat weiterhin normal gegen den System-Trust-Store prüfen.
      completionHandler(.performDefaultHandling, nil)
      return
    }
    completionHandler(
      .useCredential,
      URLCredential(identity: identity, certificates: nil, persistence: .forSession))
  }
}
