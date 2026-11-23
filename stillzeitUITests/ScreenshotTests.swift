import XCTest

/// Bildschirmfotos für Pull Requests (Minze & Honig 2.0).
///
/// Läuft im Workflow „Bildschirmfotos“; hell/dunkel und Schriftgröße stellt
/// der Workflow am Simulator ein und reicht den Namen der Variante als
/// MH_VARIANTE durch (TEST_RUNNER_MH_VARIANTE). Die App startet im lokalen
/// Modus mit erfundenen Testdaten (`Bildschirmfotos.swift` in der App).
/// Der Test prüft nichts – fehlt eine Ansicht, fehlt nur ihr Foto.
final class ScreenshotTests: XCTestCase {

  override func setUp() {
    continueAfterFailure = true
  }

  func testAnsichten() throws {
    var app = starten()

    // Startseite und weiter unten die Einträge.
    foto(app, "01-start")
    app.swipeUp()
    foto(app, "02-weiter")
    app.swipeUp()
    foto(app, "03-ende")

    // Bearbeiten-Dialog des ersten Eintrags (gibt es im alten Design nicht
    // unter diesem Namen – dann entfällt das Foto).
    let bearbeiten = app.buttons["Bearbeiten"].firstMatch
    if bearbeiten.waitForExistence(timeout: 2), bearbeiten.isHittable {
      bearbeiten.tap()
      foto(app, "04-bearbeiten")
    }

    // Einstellungen: frisch starten, damit der Kopf oben steht.
    app.terminate()
    app = starten()
    let einstellungen = app.buttons["Einstellungen"].firstMatch
    if einstellungen.waitForExistence(timeout: 3) {
      einstellungen.tap()
    } else if let letzter = app.navigationBars.buttons.allElementsBoundByIndex.last {
      // Altes Design: unbeschriftetes Zahnrad als letzter Knopf der Leiste.
      letzter.tap()
    }
    foto(app, "05-einstellungen")
    app.swipeUp()
    foto(app, "06-einstellungen-weiter")

    // Neuer Eintrag mit „Flasche“.
    app.terminate()
    app = starten()
    let flasche = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Flasche'")).firstMatch
    if flasche.waitForExistence(timeout: 5) {
      flasche.tap()
      foto(app, "07-flasche")
    }
  }

  private func starten() -> XCUIApplication {
    let app = XCUIApplication()
    // UserDefaults-Argumente: lokaler Modus, Brei & Wasser sichtbar,
    // Testdaten einspielen (nur mit diesem Argument).
    app.launchArguments += [
      "-MhBildschirmfotos", "1",
      "-data_source_mode", "demo",
      "-brei_wasser_aktiviert", "YES",
      // Deutsch wie auf den Geräten der Familie (Datum, 24-Stunden-Uhr).
      "-AppleLanguages", "(de)",
      "-AppleLocale", "de_DE",
    ]
    app.launch()
    _ = app.staticTexts.matching(NSPredicate(format: "label == 'Links'")).firstMatch
      .waitForExistence(timeout: 20)
    return app
  }

  private func foto(_ app: XCUIApplication, _ name: String) {
    sleep(2)
    let variante = ProcessInfo.processInfo.environment["MH_VARIANTE"] ?? "standard"
    let anhang = XCTAttachment(screenshot: app.screenshot())
    anhang.name = "\(variante)-\(name)"
    anhang.lifetime = .keepAlways
    add(anhang)
  }
}
