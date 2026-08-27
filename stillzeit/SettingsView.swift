import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var mode = AppSettings.mode
  @State private var apiUrl = AppSettings.apiBaseUrl
  @State private var apiKeyUrl = AppSettings.apiKeyBaseUrl
  @State private var apiKey = AppSettings.apiKey
  @State private var apiKeySichtbar = false
  @State private var certsOk = CertSource().sindVorhanden
  @State private var meldung: String?
  @State private var infoTitel: String?
  @State private var infoText: String?
  @State private var restoreBestaetigen = false
  @State private var exportDokument: BackupDokument?
  @State private var zeigeImport = false
  @FocusState private var urlFokus: Bool
  @FocusState private var keyFokus: Bool

  var body: some View {
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            datenquelle
            if mode == .apiKey { apiKeySektion }
            if mode == .api { mtlsSektion }
            breiWasserSektion
            if mode == .demo { backupSektion }
            erklaerung
          }
          .padding(16)
        }
      }
      .navigationTitle("Einstellungen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Fertig") { dismiss() }
            .font(.nunitoBold(16))
            .foregroundStyle(Mh.gruenText)
        }
      }
    }
    .alert(
      "Hinweis", isPresented: .init(get: { meldung != nil }, set: { if !$0 { meldung = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(meldung ?? "")
    }
    .alert("Backup wiederherstellen?", isPresented: $restoreBestaetigen) {
      Button("Abbrechen", role: .cancel) {}
      Button("Backup auswählen") { zeigeImport = true }
    } message: {
      Text(
        "Alle aktuell lokal gespeicherten Einträge werden durch den Inhalt des "
          + "Backups ersetzt. Dieser Vorgang kann nicht rückgängig gemacht werden.")
    }
    .sheet(
      isPresented: .init(get: { infoText != nil }, set: { if !$0 { infoText = nil } })
    ) {
      InfoSheet(titel: infoTitel ?? "", text: infoText ?? "")
    }
    .fileExporter(
      isPresented: .init(get: { exportDokument != nil }, set: { if !$0 { exportDokument = nil } }),
      document: exportDokument,
      contentType: .json,
      defaultFilename: LocalBackupService.dateiname()
    ) { ergebnis in
      switch ergebnis {
      case .success: meldung = "Backup gespeichert."
      case .failure(let fehler): meldung = "Backup fehlgeschlagen: \(fehler.localizedDescription)"
      }
    }
    .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.json]) { ergebnis in
      wiederherstellen(ergebnis)
    }
  }

  // MARK: - Sektionen

  private var datenquelle: some View {
    VStack(alignment: .leading, spacing: 4) {
      Sektion("Datenquelle")
      ModusZeile(
        gewaehlt: mode == .api, titel: "Server (mTLS-API)",
        untertitel: "Synchronisation per Client-Zertifikat"
      ) { setzeModus(.api) }
      ModusZeile(
        gewaehlt: mode == .apiKey, titel: "Server (API-Key)",
        untertitel: "API-Key empfohlen (statt Zertifikat)"
      ) { setzeModus(.apiKey) }
      ModusZeile(
        gewaehlt: mode == .demo, titel: "Lokal (SQLite)",
        untertitel: "Einträge bleiben nur auf diesem Gerät"
      ) { setzeModus(.demo) }
    }
  }

  private func setzeModus(_ neu: DataSourceMode) {
    mode = neu
    AppSettings.mode = neu
  }

  private var apiKeySektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Server (API-Key)")
      UrlFeld(wert: $apiKeyUrl, fokus: $urlFokus) { AppSettings.apiKeyBaseUrl = $0 }
      HStack {
        Group {
          if apiKeySichtbar {
            TextField("API-Key (optional)", text: $apiKey)
          } else {
            SecureField("API-Key (optional)", text: $apiKey)
          }
        }
        .font(.nunito(16))
        .focused($keyFokus)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: apiKey) { neu in AppSettings.apiKey = neu }
        Button {
          apiKeySichtbar.toggle()
        } label: {
          Image(systemName: apiKeySichtbar ? "eye.slash" : "eye")
            .foregroundStyle(Mh.textSekundaer)
        }
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background(Mh.feldFlaeche)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(keyFokus ? Mh.minze500 : Mh.rand, lineWidth: 1.5))
      Text("Empfohlen. Ohne API-Key nur für interne Testzwecke.")
        .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }

  private var mtlsSektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Server (mTLS-API)")
      UrlFeld(wert: $apiUrl, fokus: $urlFokus) { AppSettings.apiBaseUrl = $0 }
      HStack(spacing: 12) {
        Image(systemName: certsOk ? "checkmark.circle.fill" : "xmark.circle.fill")
          .foregroundStyle(certsOk ? Mh.gruenText : Mh.fehlerText)
        VStack(alignment: .leading, spacing: 2) {
          Text(certsOk ? "Zertifikate gefunden" : "Keine Zertifikate gefunden")
            .font(.nunito(16)).foregroundStyle(Mh.text)
          Text(
            "\(CertSource.certFileName) & \(CertSource.keyFileName) per Dateien-App "
              + "in den Ordner der App „Stillzeit“ kopieren")
            .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
        }
      }
      Button {
        certsOk = CertSource().sindVorhanden
        meldung = certsOk ? "Zertifikate gefunden." : "Keine Zertifikate gefunden."
      } label: {
        Label("Erneut prüfen", systemImage: "arrow.clockwise")
          .font(.nunitoBold(15))
          .foregroundStyle(Mh.gruenText)
          .padding(.horizontal, 14)
          .frame(minHeight: 40)
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
      }
    }
  }

  private var breiWasserSektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Brei & Wasser")
      // Lokales Opt-in (Default aus): erst dieser Schalter blendet die
      // beiden Erfassungs-Buttons ein – in den Server-Modi zusätzlich nur,
      // wenn auch die Server-Option der Familie aktiv ist.
      Toggle(isOn: Binding(
        get: { AppSettings.breiWasserAktiviert },
        set: { AppSettings.breiWasserAktiviert = $0 })
      ) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Brei & Wasser erfassen").font(.nunito(16)).foregroundStyle(Mh.text)
          Text(
            mode == .demo
              ? "Zusätzliche Buttons für Brei (g) und Wasser (ml)."
              : "Zusätzliche Buttons für Brei (g) und Wasser (ml) – erscheinen "
                + "nur, wenn der Server die Option für diese Familie anbietet."
          )
          .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
        }
      }
      .tint(Mh.minze500)
    }
  }

  private var backupSektion: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Backup")
      Button {
        exportieren()
      } label: {
        Label("In iCloud speichern", systemImage: "icloud.and.arrow.up")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MhButtonStil(flaeche: Mh.honig300, text: Mh.honig900))
      Button {
        restoreBestaetigen = true
      } label: {
        Label("Backup wiederherstellen", systemImage: "arrow.counterclockwise")
          .font(.nunitoBold(16))
          .foregroundStyle(Mh.gruenText)
          .frame(maxWidth: .infinity, minHeight: 44)
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
      }
      Text("Im Dateidialog iCloud Drive als Ziel wählen.")
        .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }

  private var erklaerung: some View {
    VStack(alignment: .leading, spacing: 12) {
      Sektion("Erklärung")
      HStack(spacing: 8) {
        InfoButton(titel: "Aufbau API", symbol: "cloud") {
          infoTitel = "Aufbau API"
          infoText = SettingsView.apiInfoText
        }
        InfoButton(titel: "Aufbau Datenbank", symbol: "cylinder.split.1x2") {
          infoTitel = "Aufbau Datenbank"
          infoText = SettingsView.dbInfoText
        }
      }
    }
  }

  // MARK: - Backup-Logik

  private func exportieren() {
    Task {
      do {
        let rows = try await DemoService.shared.exportRows()
        exportDokument = BackupDokument(daten: try LocalBackupService.exportJson(rows))
      } catch {
        meldung = "Backup fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }

  private func wiederherstellen(_ ergebnis: Result<URL, Error>) {
    Task {
      do {
        let url = try ergebnis.get()
        guard url.startAccessingSecurityScopedResource() else {
          throw ServiceError(message: "Datei ließ sich nicht öffnen.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let rows = try LocalBackupService.parseUndValidiere(
          try LocalBackupService.leseBegrenzt(url))
        try await DemoService.shared.replaceAll(rows)
        meldung = "Wiederherstellung erfolgreich: \(rows.count) Einträge."
      } catch {
        meldung = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }
}

// MARK: - Bausteine

private struct Sektion: View {
  let titel: String
  init(_ titel: String) { self.titel = titel }

  var body: some View {
    Text(titel).font(.nunitoBold(14)).foregroundStyle(Mh.gruenText)
  }
}

private struct ModusZeile: View {
  let gewaehlt: Bool
  let titel: String
  let untertitel: String
  let onWahl: () -> Void

  var body: some View {
    Button(action: onWahl) {
      HStack(spacing: 12) {
        Image(systemName: gewaehlt ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 20))
          .foregroundStyle(gewaehlt ? Mh.gruenText : Mh.textSekundaer)
        VStack(alignment: .leading, spacing: 2) {
          Text(titel).font(.nunito(16)).foregroundStyle(Mh.text)
          Text(untertitel).font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
        }
        Spacer()
      }
      .padding(.vertical, 8)
    }
  }
}

private struct UrlFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let onAenderung: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField("API-URL", text: $wert)
        .font(.nunito(16))
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .focused(fokus)
        .onChange(of: wert) { neu in onAenderung(neu) }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Mh.feldFlaeche)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(fokus.wrappedValue ? Mh.minze500 : Mh.rand, lineWidth: 1.5))
      Text("Basis-URL der API inkl. abschließendem /")
        .font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }
}

private struct InfoButton: View {
  let titel: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(titel, systemImage: symbol)
        .font(.nunitoBold(15))
        .foregroundStyle(Mh.gruenText)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Mh.rand, lineWidth: 1.5))
    }
  }
}

private struct InfoSheet: View {
  let titel: String
  let text: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(text)
          .font(.nunito(15))
          .foregroundStyle(Mh.text)
          .textSelection(.enabled)
          .padding(16)
      }
      .background(Mh.grund)
      .navigationTitle(titel)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Schließen") { dismiss() }
            .font(.nunitoBold(16)).foregroundStyle(Mh.gruenText)
        }
      }
    }
  }
}

/// FileDocument-Hülle für den Export-Dialog.
struct BackupDokument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]
  let daten: Data

  init(daten: Data) { self.daten = daten }

  init(configuration: ReadConfiguration) throws {
    daten = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: daten)
  }
}

// MARK: - Info-Texte (identisch zur Flutter-/Android-App)

extension SettingsView {
  static let apiInfoText = """
    Die App spricht eine REST-API unter der eingestellten Basis-URL an. Alle Antworten sind JSON.

    Endpunkte:

    • GET <Basis-URL>
      Alle Einträge: {"entries": [...]}

    • GET <Basis-URL>?action=heute
      Tagesstatistik: gesamt, links, rechts, beidseitig, flasche, total_ml, total_minuten

    • GET <Basis-URL>?action=last
      Letzter Eintrag (oder leeres Objekt)

    • POST <Basis-URL>
      Neuen Eintrag anlegen, Body z. B.:
      {"seite": "Links", "dauer_minuten": 12}
      {"seite": "Links"}
      {"seite": "Flasche", "menge": 120, "flaschen_art": "Pre"}
      {"seite": "Brei", "menge": 90} bzw. {"seite": "Wasser", "menge": 30}
      Optional "create_time" als ISO 8601 mit Zeitzonen-Offset, z. B. 2026-06-10T14:30:00+02:00

    • PATCH <Basis-URL>?id=42
      Flasche ändern: {"menge": 150, "flaschen_art": "Mutter"}
      Brei/Wasser ändern: {"menge": 120}
      Stilldauer ändern: {"dauer_minuten": 15}

    • DELETE <Basis-URL>?id=42
      Eintrag löschen

    Gültige Werte für "seite": Links, Rechts, Beidseitig, Flasche sowie – wenn die \
    Server-Option "Brei & Wasser" der Familie aktiv ist (?action=heute liefert \
    "brei_wasser_aktiv") – Brei und Wasser.

    Authentifizierung je nach Datenquelle:
    • Server (mTLS-API): Client-Zertifikat (client.crt + client.key)
    • Server (API-Key): HTTP-Header "X-API-Key: <Key>"

    Ein Eintrag hat die Felder id, create_time, seite, menge (bei Flasche/Wasser in ml, bei \
    Brei in g), einheit ("ml", "g" oder null), flaschen_art (Pre oder Mutter, nur bei Flasche) \
    und dauer_minuten (optionale Stilldauer in Minuten, nur bei Links/Rechts/Beidseitig). \
    Fehler kommen als {"error": "..."} mit passendem HTTP-Statuscode.
    """

  static let dbInfoText = """
    Im Modus "Lokal (SQLite)" speichert die App alle Einträge in der Datenbank stillzeit_demo.db \
    im app-privaten Speicher. Andere Apps haben keinen Zugriff, es findet keine Synchronisation statt.

    Tabelle "entries":

    • id
      INTEGER, Primärschlüssel (Auto-Increment)

    • create_time
      TEXT, Zeitpunkt als ISO 8601 in UTC gespeichert (dadurch chronologisch sortierbar), \
    Anzeige in lokaler Zeit

    • seite
      TEXT: Links, Rechts, Beidseitig, Flasche, Brei oder Wasser

    • menge
      INTEGER, Menge (Flasche/Wasser in ml, Brei in g) – sonst NULL

    • flaschen_art
      TEXT, Pre oder Mutter – nur bei Flasche gesetzt, bei älteren Einträgen ggf. NULL

    • dauer_minuten
      INTEGER, optionale Stilldauer in Minuten – nur bei Links/Rechts/Beidseitig gesetzt, sonst NULL

    Die Server-API verwendet dasselbe Datenmodell, Einträge sind also identisch aufgebaut \
    (id, create_time, seite, menge, flaschen_art, dauer_minuten).
    """
}
