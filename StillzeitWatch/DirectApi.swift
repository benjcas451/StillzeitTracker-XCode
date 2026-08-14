import Foundation

enum DirectApiError: LocalizedError {
  /// Der Server war nicht erreichbar — es wurde garantiert nichts gesendet.
  /// Der Aufrufer darf gefahrlos auf den Weg über das iPhone ausweichen.
  case unreachable(String)
  /// Der Server hat geantwortet, aber mit einem Fehler — oder die Antwort war
  /// unbrauchbar. Hier darf **nicht** über das iPhone wiederholt werden: die
  /// Anfrage könnte bereits ausgeführt worden sein.
  case response(String)

  var errorDescription: String? {
    switch self {
    case .unreachable(let text): text
    case .response(let text): text
    }
  }
}

/// Spricht die Stillzeit-REST-API direkt von der Uhr aus — mit derselben
/// Basis-URL und denselben Zugangsdaten wie die iPhone-App.
final class DirectApi: NSObject {

  private let connection: ServerConnection
  private var identity: SecIdentity?

  private lazy var session: URLSession = URLSession(
    configuration: {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 15
      configuration.waitsForConnectivity = false
      return configuration
    }(),
    delegate: self,
    delegateQueue: nil
  )

  /// Wirft, wenn das Client-Zertifikat nicht verwendbar ist — dadurch fällt
  /// das schon beim Import auf und nicht erst beim Speichern eines Eintrags.
  init(connection: ServerConnection) throws {
    self.connection = connection
    self.identity = nil
    // Erst nach super.init() werfen: vorher müssten sonst alle gespeicherten
    // Eigenschaften bereits gesetzt sein.
    super.init()
    if connection.isMutualTLS, let cert = connection.clientCertPEM,
      let key = connection.clientKeyPEM
    {
      identity = try ClientIdentity.make(certPEM: cert, keyPEM: key)
    }
  }

  func close() {
    session.finishTasksAndInvalidate()
  }

  // MARK: - Aktionen

  /// Die letzten Einträge, neueste zuerst.
  func entries() async throws -> [WatchEntry] {
    let data = try await send("GET", query: nil, body: nil)
    let raw = data["entries"] as? [[String: Any]] ?? []
    return raw.compactMap(WatchEntry.init).prefix(12).map { $0 }
  }

  func create(side: String, amount: Int?, bottleType: String?, at date: Date?) async throws {
    var body: [String: Any] = ["seite": side]
    if side == "Flasche" {
      body["menge"] = amount ?? 0
      if let bottleType { body["flaschen_art"] = bottleType }
    }
    if let date { body["create_time"] = DirectApi.timestamp.string(from: date) }
    _ = try await send("POST", query: nil, body: body)
  }

  func update(_ entry: WatchEntry, value: Int, bottleType: String?) async throws {
    var body: [String: Any] = [:]
    if entry.side == "Flasche" {
      body["menge"] = value
      body["flaschen_art"] = bottleType ?? entry.bottleType ?? "Pre"
    } else {
      body["dauer_minuten"] = value
    }
    _ = try await send("PATCH", query: "id=\(entry.id)", body: body)
  }

  // MARK: - Transport

  private func send(_ method: String, query: String?, body: [String: Any]?) async throws
    -> [String: Any]
  {
    let text = query == nil ? connection.baseURL : "\(connection.baseURL)?\(query!)"
    guard let url = URL(string: text) else {
      throw DirectApiError.response("Ungültige API-URL: \(connection.baseURL)")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let apiKey = connection.apiKey {
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
      throw DirectApi.classify(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw DirectApiError.response("Unerwartete Antwort des Servers.")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw DirectApiError.response("Fehler \(http.statusCode): \(DirectApi.message(from: data))")
    }
    if data.isEmpty { return [:] }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw DirectApiError.response("Unerwartete Antwort des Servers.")
    }
    return json
  }

  /// Nur Fehler, bei denen die Verbindung nachweislich nie zustande kam,
  /// gelten als „ausweichen erlaubt“. Alles Mehrdeutige (Timeout, Abbruch
  /// mitten in der Übertragung) wird gemeldet, statt es zu wiederholen.
  private static func classify(_ error: Error) -> DirectApiError {
    guard let urlError = error as? URLError else {
      return .response(error.localizedDescription)
    }
    switch urlError.code {
    case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
      .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
      .secureConnectionFailed, .serverCertificateUntrusted,
      .serverCertificateHasBadDate, .serverCertificateNotYetValid,
      .serverCertificateHasUnknownRoot, .clientCertificateRejected,
      .clientCertificateRequired:
      return .unreachable(urlError.localizedDescription)
    default:
      return .response(urlError.localizedDescription)
    }
  }

  /// Zieht `{"error": "..."}` heraus bzw. kürzt eine HTML-Fehlerseite.
  private static func message(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["error"] as? String, !text.isEmpty
    {
      return text
    }
    let text = String(data: data, encoding: .utf8) ?? ""
    let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if clean.isEmpty { return "Anfrage fehlgeschlagen" }
    return clean.count > 120 ? String(clean.prefix(120)) + "…" : clean
  }

  /// `2026-06-10T14:30:00+02:00` — so erwartet es die API.
  private static let timestamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter
  }()
}

extension DirectApi: URLSessionTaskDelegate {
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
    let credential = URLCredential(
      identity: identity, certificates: nil, persistence: .forSession)
    completionHandler(.useCredential, credential)
  }
}
