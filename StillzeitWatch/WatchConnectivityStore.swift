import Foundation
import WatchConnectivity

struct WatchEntry: Identifiable {
  let id: Int
  let date: Date
  let side: String
  let amount: Int?
  let bottleType: String?
  let duration: Int?

  init?(_ value: [String: Any]) {
    guard
      let id = value["id"] as? Int,
      let side = value["seite"] as? String,
      let dateText = value["create_time"] as? String,
      let date = WatchEntry.parseDate(dateText)
    else { return nil }
    self.id = id
    self.side = side
    self.date = date
    amount = value["menge"] as? Int
    bottleType = value["flaschen_art"] as? String
    duration = value["dauer_minuten"] as? Int
  }

  /// Das iPhone schickt UTC-Zeitstempel mit Sekundenbruchteilen, die REST-API
  /// dagegen `…T14:30:00+02:00` ohne. Beide Formen müssen funktionieren.
  static func parseDate(_ text: String) -> Date? {
    ISO8601DateFormatter.stillzeitFractional.date(from: text)
      ?? ISO8601DateFormatter.stillzeit.date(from: text)
  }
}

extension ISO8601DateFormatter {
  // ISO8601DateFormatter ist laut Apple-Doku thread-sicher.
  nonisolated(unsafe) static let stillzeit: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  nonisolated(unsafe) static let stillzeitFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject {
  @Published var entries: [WatchEntry] = []
  @Published var isLoading = false
  @Published private(set) var isReachable = false
  @Published var errorMessage: String?

  /// Kurzer Hinweis unterhalb der Liste (z. B. Ausweichen aufs iPhone).
  @Published var notice: String?

  /// Übernommene Server-Verbindung; nil = alles läuft über das iPhone.
  @Published private(set) var connection: ServerConnection?

  /// Statuszeile: „Direkt · API-Key“, „Direkt · mTLS“ oder „Über iPhone“.
  var statusText: String { connection?.label ?? "Über iPhone" }

  private var direct: DirectApi?
  private let session: WCSession? = WCSession.isSupported() ? .default : nil

  override init() {
    super.init()
    session?.delegate = self
    session?.activate()
    restoreConnection()
  }

  // MARK: - Aktionen

  func refresh() {
    perform(.load)
  }

  func add(side: String, amount: Int? = nil, bottleType: String? = nil, at date: Date?) {
    perform(.create(side: side, amount: amount, bottleType: bottleType, at: date))
  }

  func update(_ entry: WatchEntry, value: Int, bottleType: String? = nil) {
    perform(.update(entry: entry, value: value, bottleType: bottleType))
  }

  // MARK: - Server-Verbindung übernehmen

  /// Holt die auf dem iPhone eingerichtete Server-Verbindung und legt sie auf
  /// der Uhr ab. Danach laufen alle Anfragen direkt.
  func importConnection() {
    isLoading = true
    errorMessage = nil
    notice = nil
    send(action: "getConnection", arguments: nil) { [weak self] data in
      self?.adopt(data)
    }
  }

  /// Verwirft die übernommene Verbindung; alles läuft wieder über das iPhone.
  func removeConnection() {
    direct?.close()
    direct = nil
    connection = nil
    ServerConnectionStore.delete()
    errorMessage = nil
    refresh()
  }

  private func adopt(_ data: [String: Any]) {
    guard let candidate = ServerConnection(reply: data) else {
      fail("Auf dem iPhone ist keine Server-Verbindung eingerichtet.")
      return
    }
    do {
      // Baut bei mTLS gleich die Identity — ein unbrauchbares Zertifikat soll
      // beim Import auffallen, nicht erst beim Speichern eines Eintrags.
      let api = try DirectApi(connection: candidate)
      direct?.close()
      direct = api
      connection = candidate
      ServerConnectionStore.save(candidate)
      errorMessage = nil
      // Eine Erfolgsmeldung erübrigt sich: die Statuszeile zeigt ab jetzt
      // „Direkt · …“ statt „Über iPhone“.
      refresh()
    } catch {
      fail(error.localizedDescription)
    }
  }

  private func restoreConnection() {
    guard let stored = ServerConnectionStore.load() else { return }
    do {
      direct = try DirectApi(connection: stored)
      connection = stored
    } catch {
      ServerConnectionStore.delete()
      errorMessage =
        "Gespeichertes Client-Zertifikat ist unbrauchbar: \(error.localizedDescription)"
    }
  }

  // MARK: - Wegewahl

  fileprivate enum Action {
    case load
    case create(side: String, amount: Int?, bottleType: String?, at: Date?)
    case update(entry: WatchEntry, value: Int, bottleType: String?)
  }

  private func perform(_ action: Action) {
    isLoading = true
    errorMessage = nil
    guard let direct else {
      relay(action)
      return
    }
    Task { await runDirect(action, using: direct) }
  }

  private func runDirect(_ action: Action, using api: DirectApi) async {
    do {
      switch action {
      case .load:
        finish(try await api.entries())

      case .create(let side, let amount, let bottleType, let date):
        try await api.create(side: side, amount: amount, bottleType: bottleType, at: date)
        // Bewusst als eigener Vorgang: schlägt das Nachladen fehl, darf
        // keinesfalls der Eintrag erneut entstehen.
        perform(.load)

      case .update(let entry, let value, let bottleType):
        try await api.update(entry, value: value, bottleType: bottleType)
        perform(.load)
      }
    } catch DirectApiError.unreachable(_) {
      // Der Server war gar nicht erreichbar — nichts wurde gesendet, also ist
      // der Umweg über das iPhone gefahrlos.
      relay(action, notice: "Server nicht direkt erreichbar — über das iPhone erledigt.")
    } catch {
      fail(error.localizedDescription)
    }
  }

  private func relay(_ action: Action, notice: String? = nil) {
    isLoading = true
    send(action: action.relayName, arguments: action.relayArguments) { [weak self] data in
      guard let self else { return }
      let raw = data["entries"] as? [[String: Any]] ?? []
      self.finish(raw.compactMap(WatchEntry.init), notice: notice)
    }
  }

  // MARK: - WatchConnectivity

  private func send(
    action: String,
    arguments: [String: Any]?,
    onData: @escaping @MainActor ([String: Any]) -> Void
  ) {
    guard let session, session.activationState == .activated else {
      isLoading = false
      errorMessage = "Verbindung zum iPhone wird aufgebaut …"
      self.session?.activate()
      return
    }
    isReachable = session.isReachable
    guard session.isReachable else {
      isLoading = false
      errorMessage = "iPhone nicht erreichbar. Bitte Stillzeit dort kurz öffnen."
      return
    }

    var message: [String: Any] = ["action": action]
    if let arguments { message["arguments"] = arguments }
    session.sendMessage(
      message,
      replyHandler: { [weak self] reply in
        Task { @MainActor in
          guard let self else { return }
          guard reply["ok"] as? Bool == true else {
            self.fail(reply["error"] as? String ?? "Unbekannter Fehler")
            return
          }
          self.isReachable = true
          onData(reply["data"] as? [String: Any] ?? [:])
        }
      },
      errorHandler: { [weak self] error in
        Task { @MainActor in
          self?.fail(error.localizedDescription)
        }
      })
  }

  private func finish(_ list: [WatchEntry], notice: String? = nil) {
    isLoading = false
    errorMessage = nil
    self.notice = notice
    entries = list
  }

  private func fail(_ message: String) {
    isLoading = false
    errorMessage = message
  }
}

extension WatchConnectivityStore.Action {
  fileprivate var relayName: String {
    switch self {
    case .load: "getDashboard"
    case .create: "createEntry"
    case .update: "updateEntry"
    }
  }

  fileprivate var relayArguments: [String: Any]? {
    switch self {
    case .load:
      return nil

    case .create(let side, let amount, let bottleType, let date):
      var arguments: [String: Any] = ["seite": side]
      if let amount { arguments["menge"] = amount }
      if let bottleType { arguments["flaschen_art"] = bottleType }
      if let date {
        arguments["create_time"] = ISO8601DateFormatter.stillzeitFractional.string(from: date)
      }
      return arguments

    case .update(let entry, let value, let bottleType):
      var arguments: [String: Any] = ["id": entry.id, "seite": entry.side]
      if entry.side == "Flasche" {
        arguments["menge"] = value
        arguments["flaschen_art"] = bottleType ?? entry.bottleType ?? "Pre"
      } else {
        arguments["dauer_minuten"] = value
      }
      return arguments
    }
  }
}

extension WatchConnectivityStore: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let reachable = session.isReachable
    Task { @MainActor in
      if let error {
        isLoading = false
        errorMessage = error.localizedDescription
      } else if activationState == .activated {
        isReachable = reachable
        refresh()
      }
    }
  }

  /// `isReachable` wird häufig erst kurz nach der Session-Aktivierung wahr.
  /// Sobald das iPhone tatsächlich erreichbar ist, laden wir automatisch neu.
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      isReachable = reachable
      if reachable {
        refresh()
      } else if !isLoading && connection == nil {
        // Im Direktbetrieb spielt die iPhone-Erreichbarkeit keine Rolle.
        errorMessage = "iPhone nicht erreichbar. Bitte Stillzeit dort kurz öffnen."
      }
    }
  }
}
