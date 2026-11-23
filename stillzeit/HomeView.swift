import SwiftUI

/// Startseite wie im Web (Minze & Honig 2.0): Kopf mit Titel und Symbolen,
/// darunter „Heute“ als Statistik, das Formular „Neuer Eintrag“ mit genau
/// einer Hauptaktion und die Einträge als Liste mit Haarlinien.
struct HomeView: View {
  @StateObject private var model = HomeViewModel()
  @Environment(\.scenePhase) private var szenenPhase

  @State private var zeigeEinstellungen = false
  @State private var zeigeZeitwahl = false
  @State private var flascheDialog: FlascheDialogZustand?
  @State private var dauerDialog: DauerDialogZustand?
  @State private var mengeDialog: MengeDialogZustand?
  @State private var loeschKandidat: Entry?

  // Formular „Neuer Eintrag“
  @State private var seite: Seite?
  @State private var mengeText = ""
  @State private var flaschenArt: FlaschenArt = .pre
  @State private var dauerText = ""
  @State private var formHinweis: String?
  @FocusState private var eingabeFokus: Bool

  var body: some View {
    NavigationStack {
      inhalt
        .background(Mh.bg.ignoresSafeArea())
        // Titel und Symbole stehen im Kopf des Inhalts (wie im Web).
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Fertig") { eingabeFokus = false }
              .font(MhTextStil.button.font)
              .foregroundStyle(Mh.link)
          }
        }
        .sheet(isPresented: $zeigeEinstellungen, onDismiss: model.datenquelleNeuAufbauen) {
          SettingsView()
        }
        .sheet(isPresented: $zeigeZeitwahl) { zeitwahlDialog }
        .sheet(item: $flascheDialog) { zustand in
          FlascheDialog(zustand: zustand) { menge, art in
            if let eintrag = zustand.eintrag {
              model.flascheAendern(eintrag, menge: menge, flaschenArt: art)
            } else {
              model.anlegen(seite: .flasche, menge: menge, flaschenArt: art)
            }
          }
        }
        .sheet(item: $dauerDialog) { zustand in
          DauerDialog(zustand: zustand) { dauer in
            if let eintrag = zustand.eintrag {
              model.dauerAendern(eintrag, dauerMinuten: dauer)
            } else {
              model.anlegen(seite: zustand.seite, dauerMinuten: dauer)
            }
          }
        }
        .sheet(item: $mengeDialog) { zustand in
          MengeDialog(zustand: zustand) { menge in
            if let eintrag = zustand.eintrag {
              model.mengeAendern(eintrag, menge: menge)
            } else {
              model.anlegen(seite: zustand.seite, menge: menge)
            }
          }
        }
        .alert(
          "Eintrag löschen?",
          isPresented: .init(
            get: { loeschKandidat != nil },
            set: { if !$0 { loeschKandidat = nil } })
        ) {
          Button("Abbrechen", role: .cancel) {}
          Button("Löschen", role: .destructive) {
            if let eintrag = loeschKandidat { model.loeschen(eintrag) }
          }
        } message: {
          if let eintrag = loeschKandidat {
            Text("\(eintrag.titel) um \(eintrag.createTime.formatted(date: .omitted, time: .shortened))")
          }
        }
        .alert(
          "Hinweis",
          isPresented: .init(get: { model.meldung != nil }, set: { if !$0 { model.meldung = nil } })
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(model.meldung ?? "")
        }
        .task { model.aktualisieren() }
        // Rückkehr aus dem Hintergrund: nachladen und dabei die Warteschlange
        // abarbeiten – zwischendurch kann die Verbindung wiedergekommen sein,
        // ohne dass die Wache lief.
        .onChange(of: szenenPhase) { neu in
          if neu == .active { model.aktualisieren() }
        }
        // Brei/Wasser abgeschaltet, während eine der beiden Seiten gewählt war.
        .onChange(of: model.breiWasserAktiv) { aktiv in
          if !aktiv, seite?.istBreiWasser == true { seiteWaehlen(nil) }
        }
    }
  }

  // MARK: - Inhalt

  private var kopf: some View {
    MhKopf(
      "Stillzeit",
      symbole: {
        MhSymbolButton("MhRefresh", beschreibung: "Aktualisieren") { model.aktualisieren() }
        MhSymbolButton("MhSliders", beschreibung: "Einstellungen") { zeigeEinstellungen = true }
      })
    .padding(.top, Mh.abstand2)
  }

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.eintraege.isEmpty && model.fehler == nil {
      VStack(alignment: .leading, spacing: 0) {
        kopf
        Spacer()
        MhLaden()
        Spacer()
      }
      .mhSeite()
    } else if let fehler = model.fehler {
      VStack(alignment: .leading, spacing: 0) {
        kopf
        Spacer()
        FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
        Spacer()
      }
      .mhSeite()
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          kopf
          // Offline-Hinweis über allem: der Nutzer soll sofort sehen, dass
          // er zwar weiterarbeiten kann, der Stand aber noch nicht beim
          // Server ist.
          if model.offlineGrund != nil || model.ausstehend > 0 {
            OfflineHinweis(grund: model.offlineGrund, ausstehend: model.ausstehend)
          }
          if let stats = model.stats {
            MhGruppenLabel("Heute")
            HeuteStatistik(stats: stats)
          }
          MhGruppenLabel("Neuer Eintrag").padding(.top, Mh.abstand2)
          neuerEintrag
          MhGruppenLabel("Einträge").padding(.top, Mh.abstand2)
          eintragsListe
        }
        .padding(.bottom, Mh.abstand8)
        .mhSeite()
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable { model.aktualisieren() }
    }
  }

  // MARK: - Neuer Eintrag

  /// Brei/Wasser nur anbieten, wenn die Option aktiv ist – ausblenden statt
  /// deaktivieren (der Server würde sonst mit 400 ablehnen).
  private var sichtbareSeiten: [Seite] {
    Seite.allCases.filter { !$0.istBreiWasser || model.breiWasserAktiv }
  }

  /// „Jetzt“ (0) oder „Andere Uhrzeit“ (1). Die Uhrzeit selbst kommt aus dem
  /// Blatt; wird es abgebrochen, bleibt „Jetzt“ gewählt.
  private var zeitWahl: Binding<Int> {
    Binding(
      get: { model.schnellZeit == nil ? 0 : 1 },
      set: { neu in
        if neu == 0 { model.schnellZeit = nil } else { zeigeZeitwahl = true }
      })
  }

  private var neuerEintrag: some View {
    VStack(alignment: .leading, spacing: Mh.abstand5) {
      MhFeld("Seite") {
        FlexZeile(abstand: Mh.abstand2) {
          ForEach(sichtbareSeiten) { s in
            MhAuswahl(s.apiValue, gewaehlt: seite == s) { seiteWaehlen(s) }
          }
        }
      }

      if let seite, seite.hatMenge {
        let einheit = seite.mengenEinheit ?? "ml"
        MhFeld("Menge (\(einheit))") {
          MhZahlFeld(
            text: $mengeText,
            platzhalter: einheit == "g" ? "z. B. 90 (0 = leer)" : "z. B. 120 (0 = leer)",
            einheit: einheit,
            fokus: $eingabeFokus)
        }
      }

      if seite == .flasche {
        MhFeld("Art") {
          HStack(spacing: Mh.abstand2) {
            ForEach(FlaschenArt.allCases) { art in
              MhAuswahl(art.apiValue, gewaehlt: flaschenArt == art) { flaschenArt = art }
            }
          }
        }
      }

      if let seite, seite.hatDauer {
        MhFeld("Dauer (Minuten)", hinweis: "Optional, lässt sich später in der Liste nachtragen.") {
          MhZahlFeld(text: $dauerText, platzhalter: "z. B. 12", einheit: "min", fokus: $eingabeFokus)
        }
      }

      MhFeld("Uhrzeit") {
        MhSegmente(optionen: ["Jetzt", "Andere Uhrzeit"], gewaehlt: zeitWahl)
        if let zeit = model.schnellZeit {
          HStack(spacing: Mh.abstand2) {
            MhSymbol("MhClock").foregroundStyle(Mh.textSecondary)
            Text("Heute um \(zeit.formatted(date: .omitted, time: .shortened))")
              .mhText(.body)
              .foregroundStyle(Mh.text)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Ändern") { zeigeZeitwahl = true }
              .buttonStyle(.mhText)
          }
        }
      }

      if let formHinweis {
        Text(formHinweis).mhText(.small).foregroundStyle(Mh.danger)
      }

      Button(action: anlegen) {
        Text("Eintrag anlegen")
      }
      .buttonStyle(MhHauptButtonStil(breit: true))
      .disabled(seite == nil)
    }
  }

  private func seiteWaehlen(_ neu: Seite?) {
    if neu != seite {
      mengeText = ""
      dauerText = ""
      flaschenArt = .pre
    }
    seite = neu
    formHinweis = nil
  }

  /// Legt den Eintrag aus dem Formular an – mit denselben Aufrufen wie bisher
  /// die Schnell-Eingabe samt Dialogen: Flasche mit Menge und Art, Brei/Wasser
  /// mit Menge, Stillen optional mit Dauer.
  private func anlegen() {
    guard let gewaehlt = seite else { return }
    if gewaehlt.hatMenge {
      guard let menge = Int(mengeText.trimmingCharacters(in: .whitespaces)), menge >= 0 else {
        formHinweis = "Bitte eine gültige Menge eingeben (0 oder mehr)"
        return
      }
      if gewaehlt.isFlasche {
        model.anlegen(seite: gewaehlt, menge: menge, flaschenArt: flaschenArt)
      } else {
        model.anlegen(seite: gewaehlt, menge: menge)
      }
    } else {
      let roh = dauerText.trimmingCharacters(in: .whitespaces)
      var dauer: Int?
      if !roh.isEmpty {
        guard let wert = Int(roh), wert >= 0 else {
          formHinweis = "Bitte eine gültige Dauer eingeben (0 oder mehr)"
          return
        }
        dauer = wert
      }
      model.anlegen(seite: gewaehlt, dauerMinuten: dauer)
    }
    eingabeFokus = false
    seiteWaehlen(nil)
  }

  // MARK: - Einträge

  @ViewBuilder
  private var eintragsListe: some View {
    if model.eintraege.isEmpty {
      MhLeer("Noch keine Einträge")
    } else {
      let gruppen = Dictionary(grouping: model.eintraege) { $0.createTime.tagesLabel }
      let reihenfolge = model.eintraege.map(\.createTime.tagesLabel).einmalig()
      ForEach(Array(reihenfolge.enumerated()), id: \.element) { index, tag in
        let zeilen = gruppen[tag] ?? []
        VStack(alignment: .leading, spacing: 0) {
          // Tagestrenner wie im Web: Label in Nebentextfarbe über einer Haarlinie.
          Text(tag)
            .mhText(.label)
            .foregroundStyle(Mh.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, index == 0 ? 0 : Mh.abstand6)
            .padding(.bottom, Mh.abstand2)
          MhTrennlinie()
          ForEach(zeilen) { eintrag in
            EintragsZeile(
              eintrag: eintrag,
              ausstehend: model.ausstehendeIds.contains(eintrag.id),
              onBearbeiten: { bearbeiten(eintrag) },
              onLoeschen: { loeschKandidat = eintrag })
            if eintrag.id != zeilen.last?.id { MhTrennlinie() }
          }
        }
      }
    }
  }

  private func bearbeiten(_ eintrag: Entry) {
    if eintrag.seite.isFlasche {
      flascheDialog = FlascheDialogZustand(eintrag: eintrag)
    } else if eintrag.seite.istBreiWasser {
      mengeDialog = MengeDialogZustand(seite: eintrag.seite, eintrag: eintrag)
    } else {
      dauerDialog = DauerDialogZustand(seite: eintrag.seite, eintrag: eintrag)
    }
  }

  private var zeitwahlDialog: some View {
    ZeitwahlSheet(initial: model.schnellZeit) { neu in
      model.schnellZeit = neu
    }
  }
}

// MARK: - Heute

/// Eine Kennzahl der Tagesübersicht.
private struct Kennzahl: Identifiable {
  let wert: Int
  let label: String
  var einheit: String?

  var id: String { label }
}

/// „Heute“ wie im Web: Zahlen dünn in Textfarbe, Einheit klein in
/// Nebentextfarbe, drei feste Spalten (bei sehr großer Schrift zwei),
/// Gruppen durch Haarlinien getrennt.
private struct HeuteStatistik: View {
  let stats: TodayStats
  @Environment(\.dynamicTypeSize) private var schriftgroesse

  private var spalten: Int { schriftgroesse.isAccessibilitySize ? 2 : 3 }

  var body: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      KennzahlRaster(
        zahlen: [
          Kennzahl(wert: stats.gesamt, label: "Gesamt"),
          Kennzahl(wert: stats.links, label: "Links"),
          Kennzahl(wert: stats.rechts, label: "Rechts"),
          Kennzahl(wert: stats.beidseitig, label: "Beidseitig"),
          Kennzahl(wert: stats.flasche, label: "Flasche"),
          Kennzahl(wert: stats.totalMinuten, label: "Stilldauer", einheit: "min"),
        ], spalten: spalten)
      MhTrennlinie()
      KennzahlRaster(
        zahlen: [Kennzahl(wert: stats.totalMl, label: "Flaschenmenge", einheit: "ml")],
        spalten: spalten)
      if stats.breiWasserAktiv {
        MhTrennlinie()
        // Je Zeile Anzahl und Menge, wie im Web.
        KennzahlRaster(
          zahlen: [
            Kennzahl(wert: stats.brei, label: "Brei"),
            Kennzahl(wert: stats.totalGBrei, label: "Brei-Menge", einheit: "g"),
          ], spalten: spalten)
        KennzahlRaster(
          zahlen: [
            Kennzahl(wert: stats.wasser, label: "Wasser"),
            Kennzahl(wert: stats.totalMlWasser, label: "Wasser-Menge", einheit: "ml"),
          ], spalten: spalten)
      }
    }
  }
}

private struct KennzahlRaster: View {
  let zahlen: [Kennzahl]
  let spalten: Int

  private var zeilen: [[Kennzahl]] {
    stride(from: 0, to: zahlen.count, by: spalten).map {
      Array(zahlen[$0..<min($0 + spalten, zahlen.count)])
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      ForEach(Array(zeilen.enumerated()), id: \.offset) { _, zeile in
        HStack(alignment: .top, spacing: Mh.abstand3) {
          ForEach(0..<spalten, id: \.self) { index in
            Group {
              if index < zeile.count {
                let zahl = zeile[index]
                MhStat("\(zahl.wert)", label: zahl.label, einheit: zahl.einheit)
              } else {
                Color.clear.frame(height: 1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }
}

/// Einfache umbruchfähige Zeile (FlowRow-Ersatz).
struct FlexZeile: Layout {
  var abstand: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let breite = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var zeilenHoehe: CGFloat = 0
    var breiteste: CGFloat = 0
    for view in subviews {
      let groesse = view.sizeThatFits(.unspecified)
      if x + groesse.width > breite, x > 0 {
        x = 0
        y += zeilenHoehe + abstand
        zeilenHoehe = 0
      }
      x += groesse.width + abstand
      breiteste = max(breiteste, x - abstand)
      zeilenHoehe = max(zeilenHoehe, groesse.height)
    }
    return CGSize(width: proposal.width ?? breiteste, height: y + zeilenHoehe)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var zeilenHoehe: CGFloat = 0
    for view in subviews {
      let groesse = view.sizeThatFits(.unspecified)
      if x + groesse.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += zeilenHoehe + abstand
        zeilenHoehe = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
      x += groesse.width + abstand
      zeilenHoehe = max(zeilenHoehe, groesse.height)
    }
  }
}

// MARK: - Eintragszeile

private struct EintragsZeile: View {
  let eintrag: Entry
  /// Der Eintrag wartet noch auf die Übertragung zum Server.
  let ausstehend: Bool
  let onBearbeiten: () -> Void
  let onLoeschen: () -> Void

  var body: some View {
    HStack(spacing: Mh.abstand2) {
      Text(eintrag.createTime.formatted(date: .omitted, time: .shortened))
        .mhText(.small)
        .monospacedDigit()
        .foregroundStyle(Mh.textSecondary)
        .frame(minWidth: 48, alignment: .leading)
      MhPunkt(farbe: eintrag.seite.punktFarbe)
      VStack(alignment: .leading, spacing: 2) {
        Text(eintrag.titel)
          .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
          .foregroundStyle(Mh.textStrong)
        HStack(spacing: Mh.abstand2) {
          Text(eintrag.wertText)
            .mhText(.small)
            .monospacedDigit()
            .foregroundStyle(Mh.textSecondary)
          if ausstehend {
            Image("MhClock")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 14, height: 14)
              .foregroundStyle(Mh.warningFg)
              .accessibilityLabel("Wartet auf Übertragung")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      MhSymbolButton("MhEdit", beschreibung: "Bearbeiten", aktion: onBearbeiten)
      MhSymbolButton("MhTrash", beschreibung: "Eintrag löschen", farbe: Mh.textTertiary, aktion: onLoeschen)
    }
    .padding(.vertical, Mh.abstand1)
    .frame(minHeight: 60)
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: Mh.abstand4) {
      MhSymbol("MhAlert", groesse: 32).foregroundStyle(Mh.danger)
      Text(meldung)
        .mhText(.body)
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button(action: onErneut) {
        MhButtonInhalt("Erneut versuchen", symbol: "MhRefresh")
      }
      .buttonStyle(.mhHaupt)
      .padding(.top, Mh.abstand2)
    }
    .frame(maxWidth: .infinity)
    .padding(Mh.abstand4)
  }
}

/// Hinweis über der Liste: Verbindung weg, App weiter benutzbar.
private struct OfflineHinweis: View {
  /// Grund der abgebrochenen Verbindung; nil heisst „wieder online, aber es
  /// wartet noch etwas auf die Übertragung“.
  let grund: String?
  let ausstehend: Int

  var body: some View {
    MhHinweis(
      text, titel: titel, art: .warnung, symbol: grund == nil ? "MhUpload" : "MhCloudOff")
  }

  private var titel: String {
    guard let grund else { return "Übertragung läuft" }
    return "Offline – \(grund)"
  }

  private var text: String {
    guard ausstehend > 0 else {
      return "Angezeigt wird der zuletzt geladene Stand."
    }
    let was = ausstehend == 1 ? "Eine Änderung wartet" : "\(ausstehend) Änderungen warten"
    return "\(was) auf die Übertragung und geht raus, sobald die Verbindung steht."
  }
}

// MARK: - Helfer

extension Seite {
  /// Datenfarbe wie im Web: Stillen Minze, Flasche Honig, Brei/Wasser Flieder.
  /// Immer zusammen mit dem Namen der Seite.
  var punktFarbe: Color {
    if hatDauer { return Mh.data1 }
    if isFlasche { return Mh.data2 }
    return Mh.data3
  }
}

extension Entry {
  var titel: String {
    if seite.isFlasche, let art = flaschenArt {
      return "\(seite.apiValue) · \(art.apiValue)"
    }
    return seite.apiValue
  }

  /// Menge mit Einheit bzw. Dauer; „Dauer offen“, solange keine eingetragen ist.
  var wertText: String {
    // Einheit aus dem API-Feld, lokal aus der Seite abgeleitet.
    if seite.hatMenge { return "\(menge ?? 0) \(anzeigeEinheit ?? "ml")" }
    if let dauerMinuten { return "\(dauerMinuten) min" }
    return "Dauer offen"
  }
}

extension Date {
  /// „Heute · 23.11.2026“, „Gestern · 22.11.2026“, sonst nur das Datum – wie im Web.
  var tagesLabel: String {
    let datum = formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    if Calendar.current.isDateInToday(self) { return "Heute · \(datum)" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern · \(datum)" }
    return datum
  }
}

extension Array where Element: Hashable {
  /// Reihenfolge-erhaltendes Deduplizieren.
  func einmalig() -> [Element] {
    var gesehen = Set<Element>()
    return filter { gesehen.insert($0).inserted }
  }
}
