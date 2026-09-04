# Stillzeit (iOS + watchOS)

Native iOS-App zum Erfassen von Still- und Flaschenmahlzeiten, mit
eingebetteter watchOS-App. Swift, SwiftUI, keine externen Abhängigkeiten
(kein SPM, keine Pods). Portiert von einer Flutter-App — Bestandsdaten und
-einstellungen werden beim App-Store-Update nahtlos übernommen
(Details unten).

Schwester-Repo: **StillzeitTracker-Android** (Android + Wear OS, gleicher
Funktionsumfang, gleiches Design, gleiches Watch-Protokoll).

---

## Targets

| Target | Was | Bundle-ID |
|---|---|---|
| `stillzeit` | iPhone-App (SwiftUI, iOS 16+) | `org.dwarftsch.stillzeit` |
| `StillzeitWatch` | watchOS-App (SwiftUI, watchOS 10+), im App-Bundle eingebettet | `org.dwarftsch.stillzeit.watchkitapp` |
| `stillzeitTests` / `stillzeitUITests` | Test-Templates | — |

Alle Targets sind bewusst **auf iOS/watchOS beschränkt**
(`SUPPORTED_PLATFORMS`) — macOS/visionOS wieder zu aktivieren bricht
Xcode-Cloud-Workflows und den UIKit-/WatchConnectivity-Code.

## Einrichtung auf einem neuen Gerät

1. Repo klonen, `stillzeit.xcodeproj` in **Xcode 16 oder neuer** öffnen
   (Projektformat `objectVersion 77` mit synchronisierten Ordner-Gruppen:
   Dateien im Ordner erscheinen automatisch im Target).
2. **Signing:** Automatic Signing; in den Target-Einstellungen das eigene
   Team wählen, falls abweichend. Für Simulator-Builds ist kein
   Zertifikat nötig.
3. Bauen/Starten: Scheme `stillzeit` (iPhone) bzw. `StillzeitWatch` (Uhr)
   auf einem Simulator. Das war's — keine weiteren Setup-Schritte.

```bash
# CLI-Äquivalente
xcodebuild -project stillzeit.xcodeproj -scheme stillzeit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project stillzeit.xcodeproj -scheme StillzeitWatch \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Watch-Test im Simulator: `xcrun simctl pair <watch-udid> <phone-udid>`,
beide booten — die Uhr lädt dann live die iPhone-Einträge (WatchConnectivity
funktioniert zwischen gekoppelten Simulatoren).

## Versionierung & Build-Nummern

- `MARKETING_VERSION`: im Projekt gepflegt, **auf App- und Watch-Target
  identisch halten** (Apple verlangt übereinstimmende
  `CFBundleShortVersionString` von Companion und Watch-App).
  **Konvention:** Major/Minor (1.x.x, x.1.x) über alle Plattformen
  (iOS **und** Android) identisch; die Patch-Stelle darf pro Plattform
  divergieren.
- `CURRENT_PROJECT_VERSION` gilt nur für **lokale** Archive.
  **Xcode Cloud überschreibt die Build-Nummer mit seiner eigenen
  fortlaufenden Zählung** — App Store Connect verlangt steigende
  Build-Nummern nur *innerhalb desselben Versions-Strings*. Kollidiert
  ein Cloud-Build mit einem höheren Alt-Build derselben Version:
  Patch-Version anheben oder in ASC → Xcode Cloud die
  „Next Build Number“ hochsetzen.

## CI

**Xcode Cloud** (App Store Connect): baut/archiviert für TestFlight/App
Store. Im Workflow nur **iOS**-Actions konfigurieren.

**GitHub Actions** (`.github/workflows/build-ipa.yml`, manuell): baut eine
**unsignierte IPA** (inkl. eingebetteter Watch-App) und veröffentlicht sie
als GitHub-Release (`v<version>-<run_number>`) — für Sideloading, **nicht**
für Transporter/App Store geeignet (unsigniert). Keine Secrets nötig.

## Herkunft & Datenmigration (Flutter → nativ)

Die App ersetzt eine Flutter-App unter derselben Bundle-ID. Beim
App-Store-Update bleiben alle Nutzerdaten erhalten (iOS migriert den
Container; der Container-Pfad wechselt dabei die UUID — das ist normal):

- **SQLite:** identische Datei `Documents/stillzeit_demo.db` (sqflite legte
  sie dort ab), Schema `user_version 3` inkl. Upgrade-Pfad. Der ISO-Parser
  (`IsoZeit`) toleriert die Mikrosekunden-Zeitstempel alter Dart-Einträge.
- **Einstellungen:** einmalige Migration der `flutter.`-präfixierten Keys
  aus `UserDefaults.standard` (dort speichert Flutters shared_preferences),
  siehe `AppSettings.migrationAusfuehren()`.
- **mTLS-Zertifikate:** liegen unverändert im Documents-Ordner
  (`client.crt`/`client.key`, sichtbar in der Dateien-App via
  `UIFileSharingEnabled`).
- **Watch:** übernommene Server-Verbindung liegt im Keychain der Uhr
  (Service `org.dwarftsch.stillzeit.watch`) — bleibt bei Updates mit
  gleichem Team erhalten.

## Architektur

```
stillzeit/                       iPhone-App
  Models.swift                   Seite/FlaschenArt/Entry/TodayStats, IsoZeit-Parser
  EntryService.swift             Sendable-Protokoll der Datenquellen + Factory
  DemoService.swift              lokale SQLite (C-API, sqflite-kompatibel)
  ApiService.swift               REST-Client (URLSession; PATCH + mTLS)
  ClientIdentity.swift           PEM (crt/key) -> SecIdentity (Keychain), inkl. PKCS#8-Parser
  CertSource.swift               Zertifikatsquelle: App-Ordner oder frei
                                 gewählter Ordner (security-scoped Bookmark)
  AppOrdner.swift                hält den App-Ordner in der Dateien-App sichtbar
  AppSettings.swift              UserDefaults + Flutter-Migration
  LocalBackupService.swift       JSON-Backup (Format kompatibel zu Android/Flutter)
  PhoneWatchBridge.swift         WatchConnectivity-Endpunkt für die Uhr
  Theme.swift, HomeView.swift, SettingsView.swift, Dialoge.swift, HomeViewModel.swift
  Fonts/                         Nunito (OFL, Lizenz liegt daneben)
StillzeitWatch/                  watchOS-App (eigenständig lauffähige UI,
                                 DirectApi für den Direktbetrieb gegen den Server)
```

**Datenquellen (vom Nutzer wählbar):** Server per mTLS-Client-Zertifikat,
Server per API-Key (`X-API-Key`-Header) oder lokale SQLite ohne Sync. Im
mTLS-Modus lässt sich seit 2.2.2 **zusätzlich** ein API-Key hinterlegen
(eigener Keychain-Account `mtls-api-key`, getrennt vom `api-key` des
API-Key-Modus) — für Server, die beides prüfen. Bleibt das Feld leer, geht
wie bisher kein `X-API-Key`-Header raus.

### Concurrency-Konventionen

Das Projekt ist unter `SWIFT_STRICT_CONCURRENCY=complete` **meldungsfrei**
— bitte so halten (Xcode Cloud eskaliert Verstöße zu Fehlern):

- `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; MainActor wird explizit
  annotiert (`HomeViewModel`, `WatchConnectivityStore`).
- `EntryService` ist `Sendable`; `DemoService`/`PhoneWatchBridge` sind
  begründet `@unchecked Sendable` (serielle Queue bzw. zustandslos).
- `URLSession` wird im `init` erzeugt, nicht `lazy` (lazy wäre bei
  parallelen Erst-Requests nicht threadsicher).

## Watch-Protokoll (WatchConnectivity)

Uhr → iPhone per `WCSession.sendMessage`; `PhoneWatchBridge` antwortet.
JSON-kompatible Dictionaries:

```
Anfrage:  {"action": "...", "arguments": { ... }}
Antwort:  {"ok": true, "data": { ... }}  bzw.  {"ok": false, "error": "..."}
```

Aktionen: `getConnection` (überträgt die Server-Konfiguration des Telefons,
bei mTLS inkl. PEM als Base64 und – falls hinterlegt – dem zusätzlichen
`api_key` — die Uhr kann danach direkt mit dem Server sprechen und fällt bei
Nichterreichbarkeit automatisch auf das iPhone zurück), `getDashboard` (letzte 12 Einträge), `createEntry`, `updateEntry`.
**Dieses Protokoll ist byte-identisch zur Android/Wear-Strecke** —
Änderungen immer in beiden Repos nachziehen.

## REST-API & Datenmodell

Basis-URL konfiguriert der Nutzer in den Einstellungen. Alle Antworten JSON.

| Endpunkt | Zweck |
|---|---|
| `GET <base>` | alle Einträge: `{"entries": [...]}` |
| `GET <base>?action=heute` | Tagesstatistik (gesamt, links, rechts, beidseitig, flasche, total_ml, total_minuten + brei, wasser, total_g_brei, total_ml_wasser, brei_wasser_aktiv) |
| `GET <base>?action=last` | letzter Eintrag |
| `POST <base>` | Eintrag anlegen |
| `PATCH <base>?id=42` | Menge (Flasche/Brei/Wasser; Flaschenart nur Flasche) bzw. Dauer ändern |
| `DELETE <base>?id=42` | Eintrag löschen |

Eintrag: `id`, `create_time` (ISO 8601 mit Zeitzonen-Offset), `seite`
(`Links`/`Rechts`/`Beidseitig`/`Flasche` sowie `Brei`/`Wasser`, wenn die
pro Familie schaltbare Server-Option aktiv ist — `?action=heute` liefert
`brei_wasser_aktiv` und die Zusatzfelder `brei`, `wasser`, `total_g_brei`,
`total_ml_wasser`; `gesamt` zählt weiterhin nur Milchmahlzeiten — in der
App zusätzlich lokales Opt-in unter Einstellungen → „Brei & Wasser“,
Default aus), `menge`
(Flasche/Wasser in ml, Brei in g), `einheit` (`ml`/`g`/null),
`flaschen_art` (`Pre`/`Mutter`, nur Flasche), `dauer_minuten` (nur
Still-Einträge). Fehler: `{"error": "..."}` mit passendem HTTP-Status.
Die Query-Form (`?id=42`) ist Absicht — sie funktioniert auf allen Hosts
inklusive der Legacy-Route ohne `/api/`. Die lokale Tabelle `entries`
spiegelt exakt dieses Modell.

## Sicherung & Gerätewechsel

Auf iOS gibt es kein Gegenstück zu Androids `backup_rules.xml` /
`data_extraction_rules.xml`. Gesteuert wird über die Dateiablage
(`Documents` wird gesichert, `Library/Caches` und `tmp` nicht),
`isExcludedFromBackup` und die Keychain-Attribute.

| | iCloud-Backup | Direkttransfer (Schnellstart) |
|---|---|---|
| Einträge (SQLite) | ✅ | ✅ |
| API-Keys (Keychain) | ❌ | ✅ |
| Client-Zertifikat | ❌ | ❌ |

Die API-Keys (der des API-Key-Modus und der optionale Zusatz-Key des
mTLS-Modus) liegen in der Keychain, mit `kSecAttrAccessibleAfterFirstUnlock`
und **ohne** `kSecAttrSynchronizable`. Damit sind sie beim Direkttransfer und
im verschlüsselten Finder-Backup dabei, aus einem iCloud-Backup dagegen nicht
wiederherstellbar — die iOS-Entsprechung der Android-Entscheidung
„`<device-transfer>` ja, `<cloud-backup>` nein“. Nach einer Wiederherstellung
aus iCloud sind sie einmal neu einzutragen. Die Uhr legt ihre übernommene
Verbindung in `ServerConnectionStore` mit demselben Attribut ab.

Client-Zertifikate (`client.crt` / `client.key`) liegen im App-Ordner der
Dateien-App und sind nach einem Gerätewechsel gegebenenfalls neu abzulegen.
Dafür müssen zwei Dinge zusammenkommen:

1. **`UIFileSharingEnabled` und `LSSupportsOpeningDocumentsInPlace` im
   Bundle.** `UIFileSharingEnabled` steht in `AppInfo.plist` und **nicht**
   als `INFOPLIST_KEY_UIFileSharingEnabled` im Projekt: diesen Schlüssel
   kennt Xcode als Build-Setting nicht und verwirft ihn kommentarlos. Genau
   daran lag es – der Schlüssel stand im Projekt und kam nie im Binary an.
   `GENERATE_INFOPLIST_FILE` bleibt `YES`; Xcode nimmt `AppInfo.plist` als
   Basis und mergt die `INFOPLIST_KEY_*`-Werte hinein.
2. **Mindestens eine sichtbare Datei in `Documents/`.** iOS blendet den
   Ordner sonst aus. `AppOrdner` hält dafür beim Start eine `README.txt`
   vor und legt sie an, sobald sie fehlt – bewusst ohne Leer-Prüfung:
   `contentsOfDirectory` zählt auch unsichtbare Punkt-Dateien mit, für iOS
   gilt der Ordner damit trotzdem als leer.

Der Build-Check liest beide Schlüssel mit `PlistBuddy` aus dem gebauten
Bundle und schlägt fehl, wenn einer nicht `true` ist. Dass beide ankommen –
einer aus der Datei, einer aus den Build-Settings – belegt zugleich, dass
der Merge greift; `CFBundleShortVersionString` wird als zweiter Beleg
mitgeprüft.

Alternativ lässt sich unter *Einstellungen → Server (mTLS-API)* ein
beliebiger anderer Ordner auswählen. Er wird als security-scoped Bookmark
gespeichert. Nach einer Wiederherstellung auf einem neuen Gerät zeigt das
Bookmark ins Leere; die App meldet das und bittet darum, den Ordner erneut
auszuwählen.

Unabhängig davon gibt es das manuelle Backup unter *Einstellungen → Backup*.

## Design-System „Minze & Honig“ (v1.0)

Quelle der Wahrheit im Code: `stillzeit/Theme.swift` (iPhone, `Mh`-Enum)
und die `MhW`-Tokens in `StillzeitWatch/ContentView.swift`. Kernregeln:

- **Grundregel:** Weiß dominiert (~80 %), Farbe liegt *auf* dem Grund —
  nie als Seitenhintergrund. Dark: Grund `#1F2221`, Karten `#292D2B`,
  Ränder `#3A403C` — kein reines Schwarz.
- **Skalen 50–900** je Markenfarbe. 300 = Markenton (Flächen/Buttons),
  100 = zarte Hinweisfläche, 600/700 = text-/icontauglich auf Weiß,
  900 = Text auf 300er-Flächen. **Pastell (300) nie als Text auf Weiß.**
- **Markenfarben:** Minze (Primär) `#A8D5BA`/300, Honig (Sekundär)
  `#F7E8A4`/300, Flieder (Akzent, sparsam) `#CDB4DB`/300; Grau leicht
  grünstichig (`#F6F8F6` … `#1F2221`); Rot nur semantisch
  (Fehler/Löschen: Fläche 100 `#FAE3E1`, Text 700 `#96362F`, dark 300 `#F0B6B1`).
- **Eintragsarten (Chip-Muster, plattformübergreifend identisch):**
  Links = Minze, Rechts = Flieder, Flasche = Honig, Beidseitig = Grau,
  Brei = Honig eine Stufe dunkler (400), Wasser = neutrales Grau.
  Kacheln/Buttons: Fläche 300 + Text 900; Listen-Avatare: zarte Fläche
  (100 bzw. Dark-Äquivalent `#263B2F`/`#3B3524`/`#352B3C`) + Icon 700/300.
- **Dark Mode:** Pastellflächen (300) bleiben unverändert mit 900er-Text;
  100er-Flächen werden zu den abgedunkelten Äquivalenten. Die
  Systemfarben laufen über `UIColor`-Dynamic-Provider (hell/dunkel).
- **Typografie:** ausschließlich **Nunito** (eingebettet, OFL — Lizenz
  liegt in `Fonts/`); Gewicht statt Schriftmischung (400/600/700/800).
  Stolperfalle: die statischen Google-Fonts-Schnitte tragen die
  PostScript-Namen `NunitoExtraLight-Regular/-SemiBold/-Bold/-ExtraBold` —
  es sind trotzdem die normalen Gewichte. iPhone registriert die Fonts zur
  Laufzeit (`NunitoFont.registrieren()`), die Watch über `UIAppFonts` in
  ihrer `Info.plist`.
- **AccentColor** (Systemdialoge, Navigationstitel der Watch): Minze —
  600 hell / 300 dunkel.
- **Form:** Radius 8 / 12 (Buttons, Inputs) / 16 (Karten) / 24 (Sheets) /
  Pill (Chips). Touch-Ziele min. 44 pt.
- Kontraste sind WCAG-AA-geprüft; Farbe nie als einziger Informationsträger.

## Sicherheit / was nie ins Repo darf

Provisioning-Profile, `.p12`/Private Keys, App-Store-Connect-API-Keys,
API-Keys und Server-URLs von Nutzern. Signing läuft über Automatic
Signing bzw. Xcode Cloud — es liegen bewusst keinerlei Credentials im Repo.
