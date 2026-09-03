import Foundation

/// Die vom iPhone übernommene Server-Verbindung. Solange keine hinterlegt ist,
/// läuft alles über das iPhone (Relay).
struct ServerConnection: Codable {
  /// Basis-URL inklusive abschließendem Slash.
  let baseURL: String
  /// Wird als `X-API-Key` mitgesendet; im mTLS-Modus optional (nur, wenn der
  /// Server zusätzlich zum Zertifikat einen Key verlangt).
  let apiKey: String?
  /// PEM-Bytes des Client-Zertifikats; nil im API-Key-Modus.
  let clientCertPEM: Data?
  /// PEM-Bytes des privaten Schlüssels; nil im API-Key-Modus.
  let clientKeyPEM: Data?

  var isMutualTLS: Bool { clientCertPEM != nil && clientKeyPEM != nil }

  /// Kurzbeschreibung für die Statusanzeige auf der Uhr.
  var label: String {
    guard isMutualTLS else { return "Direkt · API-Key" }
    return apiKey == nil ? "Direkt · mTLS" : "Direkt · mTLS + Key"
  }

  var url: URL? { URL(string: baseURL) }
}

extension ServerConnection {
  /// Baut die Verbindung aus der Antwort auf `getConnection`.
  /// nil bedeutet: auf dem iPhone ist keine Server-Quelle eingerichtet.
  init?(reply: [String: Any]) {
    let raw = (reply["base_url"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return nil }
    let normalized = raw.hasSuffix("/") ? raw : raw + "/"

    switch reply["mode"] as? String {
    case "apiKey":
      guard let key = reply["api_key"] as? String, !key.isEmpty else { return nil }
      self.init(baseURL: normalized, apiKey: key, clientCertPEM: nil, clientKeyPEM: nil)

    case "api":
      guard
        let certText = reply["client_cert"] as? String,
        let keyText = reply["client_key"] as? String,
        let cert = Data(base64Encoded: certText),
        let key = Data(base64Encoded: keyText)
      else { return nil }
      // Zusatz-Key optional: ältere iPhone-Versionen senden das Feld gar
      // nicht, dann bleibt es wie bisher bei reinem mTLS.
      let zusatzKey = (reply["api_key"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      self.init(baseURL: normalized, apiKey: zusatzKey, clientCertPEM: cert, clientKeyPEM: key)

    default:
      return nil
    }
  }
}

/// Legt die übernommene Verbindung im Keychain der Uhr ab — dort ist das
/// Schlüsselmaterial besser aufgehoben als in den UserDefaults.
enum ServerConnectionStore {

  private static let service = "org.dwarftsch.stillzeit.watch"
  private static let account = "server-connection"

  static func load() -> ServerConnection? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard
      SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(ServerConnection.self, from: data)
  }

  static func save(_ connection: ServerConnection) {
    guard let data = try? JSONEncoder().encode(connection) else { return }
    delete()
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  static func delete() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
