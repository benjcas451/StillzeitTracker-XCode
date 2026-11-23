import Foundation

/// Erfundene Testdaten für die Bildschirmfotos im UI-Test (Workflow
/// „Bildschirmfotos“, `stillzeitUITests/ScreenshotTests.swift`).
///
/// Greift nur, wenn die App mit dem Launch-Argument `-MhBildschirmfotos 1`
/// UND im lokalen Modus startet (der Test setzt dazu `-data_source_mode demo`
/// als UserDefaults-Argument). Im normalen Betrieb passiert hier nichts.
enum Bildschirmfotos {

  static var aktiv: Bool { UserDefaults.standard.bool(forKey: "MhBildschirmfotos") }

  /// Beim App-Start aufrufen, bevor die Oberfläche das erste Mal lädt.
  static func vorbereiten() {
    guard aktiv, AppSettings.mode == .demo else { return }
    try? DemoService.shared.ersetzeSofort(testdaten())
  }

  /// Ein ruhiger Vormittag und der Abend davor – relativ zum heutigen Tag,
  /// damit „Heute“ und „Gestern“ immer gefüllt sind.
  private static func testdaten() -> [EntryRow] {
    typealias Zeile = (tage: Int, stunde: Int, minute: Int, seite: Seite, menge: Int?, art: FlaschenArt?, dauer: Int?)
    let zeilen: [Zeile] = [
      (1, 17, 10, .links, nil, nil, 9),
      (1, 19, 45, .flasche, 90, .mutter, nil),
      (1, 22, 30, .rechts, nil, nil, 13),
      (0, 0, 40, .links, nil, nil, 14),
      (0, 3, 15, .rechts, nil, nil, 11),
      (0, 5, 30, .flasche, 120, .pre, nil),
      (0, 6, 50, .beidseitig, nil, nil, 18),
      (0, 8, 10, .brei, 80, nil, nil),
      (0, 8, 15, .wasser, 40, nil, nil),
      (0, 9, 20, .links, nil, nil, nil),
    ]
    let kalender = Calendar.current
    let heute = kalender.startOfDay(for: Date())
    return zeilen.enumerated().map { index, zeile in
      let tag = kalender.date(byAdding: .day, value: -zeile.tage, to: heute) ?? heute
      let zeit =
        kalender.date(bySettingHour: zeile.stunde, minute: zeile.minute, second: 0, of: tag) ?? tag
      return EntryRow(
        id: Int64(index + 1),
        createTime: IsoZeit.dbString(from: zeit),
        seite: zeile.seite.apiValue,
        menge: zeile.menge,
        flaschenArt: zeile.art?.apiValue,
        dauerMinuten: zeile.dauer)
    }
  }
}
