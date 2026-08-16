import SwiftUI

struct HomeView: View {
  @StateObject private var model = HomeViewModel()

  @State private var zeigeEinstellungen = false
  @State private var zeigeZeitwahl = false
  @State private var flascheDialog: FlascheDialogZustand?
  @State private var dauerDialog: DauerDialogZustand?
  @State private var mengeDialog: MengeDialogZustand?
  @State private var loeschKandidat: Entry?

  var body: some View {
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        inhalt
      }
      .navigationTitle("")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.aktualisieren()
          } label: {
            Image(systemName: "arrow.clockwise").foregroundStyle(Mh.gruenText)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            zeigeEinstellungen = true
          } label: {
            Image(systemName: "gearshape").foregroundStyle(Mh.gruenText)
          }
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
      .alert("Eintrag löschen?", isPresented: .init(
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
    }
  }

  // MARK: - Inhalt

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.eintraege.isEmpty && model.fehler == nil {
      ProgressView().tint(Mh.minze500)
    } else if let fehler = model.fehler {
      FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // App-Titel im Inhalt statt in der Toolbar: iOS faltet Text-Items
          // dort in ein Überlauf-Menü.
          Text("🤱 Stillzeit")
            .font(.nunitoExtraBold(26))
            .foregroundStyle(Mh.text)
          if let stats = model.stats { StatistikKarte(stats: stats) }
          ZeitAuswahl(
            zeit: model.schnellZeit,
            onWaehlen: { zeigeZeitwahl = true },
            onZuruecksetzen: { model.schnellZeit = nil })
          SchnellEingabe(breiWasserAktiv: model.breiWasserAktiv) { seite in
            schnellAnlegen(seite)
          }
          eintragsListe
        }
        .padding(16)
      }
      .refreshable { model.aktualisieren() }
    }
  }

  private func schnellAnlegen(_ seite: Seite) {
    if seite.isFlasche {
      flascheDialog = FlascheDialogZustand(eintrag: nil)
    } else if seite.istBreiWasser {
      // Brei/Wasser brauchen immer eine Menge – Dialog in jedem Fall.
      mengeDialog = MengeDialogZustand(seite: seite, eintrag: nil)
    } else if model.schnellZeit != nil {
      // Bei gewählter Uhrzeit wird die Dauer direkt mit abgefragt.
      dauerDialog = DauerDialogZustand(seite: seite, eintrag: nil)
    } else {
      model.anlegen(seite: seite)
    }
  }

  @ViewBuilder
  private var eintragsListe: some View {
    if model.eintraege.isEmpty {
      Text("Noch keine Einträge")
        .font(.nunito(16))
        .foregroundStyle(Mh.textSekundaer)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    } else {
      let gruppen = Dictionary(grouping: model.eintraege) { $0.createTime.tagesLabel }
      let reihenfolge = model.eintraege.map(\.createTime.tagesLabel).einmalig()
      ForEach(reihenfolge, id: \.self) { tag in
        Text(tag)
          .font(.nunitoBold(14))
          .foregroundStyle(Mh.gruenText)
          .padding(.horizontal, 4)
          .padding(.top, 8)
        ForEach(gruppen[tag] ?? []) { eintrag in
          EintragsKachel(
            eintrag: eintrag,
            onBearbeiten: {
              if eintrag.seite.isFlasche {
                flascheDialog = FlascheDialogZustand(eintrag: eintrag)
              } else if eintrag.seite.istBreiWasser {
                mengeDialog = MengeDialogZustand(seite: eintrag.seite, eintrag: eintrag)
              } else {
                dauerDialog = DauerDialogZustand(seite: eintrag.seite, eintrag: eintrag)
              }
            },
            onLoeschen: { loeschKandidat = eintrag })
        }
      }
    }
  }

  private var zeitwahlDialog: some View {
    ZeitwahlSheet(initial: model.schnellZeit) { neu in
      model.schnellZeit = neu
    }
  }
}

// MARK: - Statistik-Karte

private struct StatistikKarte: View {
  let stats: TodayStats

  var body: some View {
    MhKarte {
      VStack(alignment: .leading, spacing: 12) {
        Text("Heute").font(.nunitoBold(16)).foregroundStyle(Mh.text)
        FlexZeile(abstand: 16) {
          StatWert(label: "Gesamt", wert: "\(stats.gesamt)", farbe: Mh.text)
          StatWert(label: "Links", wert: "\(stats.links)", farbe: Seite.links.akzentText)
          StatWert(label: "Rechts", wert: "\(stats.rechts)", farbe: Seite.rechts.akzentText)
          StatWert(label: "Beidseitig", wert: "\(stats.beidseitig)", farbe: Seite.beidseitig.akzentText)
          StatWert(label: "Flasche", wert: "\(stats.flasche)", farbe: Seite.flasche.akzentText)
          StatWert(label: "Menge", wert: "\(stats.totalMl) ml", farbe: Seite.flasche.akzentText)
          if stats.breiWasserAktiv {
            StatWert(
              label: "Brei", wert: "\(stats.brei) · \(stats.totalGBrei) g",
              farbe: Seite.brei.akzentText)
            StatWert(
              label: "Wasser", wert: "\(stats.wasser) · \(stats.totalMlWasser) ml",
              farbe: Seite.wasser.akzentText)
          }
          StatWert(label: "Zeit", wert: "\(stats.totalMinuten) min", farbe: Mh.gruenText)
        }
      }
    }
  }
}

private struct StatWert: View {
  let label: String
  let wert: String
  let farbe: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(wert).font(.nunitoExtraBold(22)).foregroundStyle(farbe)
      Text(label).font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
    }
  }
}

/// Einfache umbruchfähige Zeile (FlowRow-Ersatz).
private struct FlexZeile: Layout {
  var abstand: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let breite = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var zeilenHoehe: CGFloat = 0
    for view in subviews {
      let groesse = view.sizeThatFits(.unspecified)
      if x + groesse.width > breite, x > 0 {
        x = 0
        y += zeilenHoehe + 12
        zeilenHoehe = 0
      }
      x += groesse.width + abstand
      zeilenHoehe = max(zeilenHoehe, groesse.height)
    }
    return CGSize(width: breite, height: y + zeilenHoehe)
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
        y += zeilenHoehe + 12
        zeilenHoehe = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
      x += groesse.width + abstand
      zeilenHoehe = max(zeilenHoehe, groesse.height)
    }
  }
}

// MARK: - Zeit-Auswahl & Schnell-Eingabe

private struct ZeitAuswahl: View {
  let zeit: Date?
  let onWaehlen: () -> Void
  let onZuruecksetzen: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Chip(text: "Jetzt", aktiv: zeit == nil, action: onZuruecksetzen)
      Chip(
        text: zeit.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Zeit eintragen",
        symbol: zeit == nil ? "clock" : nil,
        aktiv: zeit != nil,
        action: onWaehlen)
    }
  }
}

/// Pill-Chip nach Guide: aktiv = Minze-300-Fläche mit 900er-Text.
private struct Chip: View {
  let text: String
  var symbol: String?
  let aktiv: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol).font(.system(size: 14)) }
        Text(text).font(.nunitoSemiBold(15))
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 36)
      .background(aktiv ? Mh.minze300 : .clear)
      .foregroundStyle(aktiv ? Mh.minze900 : Mh.text)
      .overlay(
        Capsule().strokeBorder(aktiv ? .clear : Mh.rand, lineWidth: 1.5)
      )
      .clipShape(Capsule())
    }
  }
}

private struct SchnellEingabe: View {
  let breiWasserAktiv: Bool
  let onAnlegen: (Seite) -> Void

  private let spalten = [GridItem(.adaptive(minimum: 150), spacing: 10)]

  /// Brei/Wasser nur anbieten, wenn die Server-Option aktiv ist –
  /// ausblenden statt deaktivieren (der Server würde sonst mit 400 ablehnen).
  private var sichtbare: [Seite] {
    Seite.allCases.filter { !$0.istBreiWasser || breiWasserAktiv }
  }

  var body: some View {
    LazyVGrid(columns: spalten, alignment: .leading, spacing: 10) {
      ForEach(sichtbare) { seite in
        Button {
          onAnlegen(seite)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: seite.symbol).font(.system(size: 15, weight: .bold))
            Text(seite.apiValue)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(MhButtonStil(flaeche: seite.buttonFlaeche, text: seite.buttonText))
      }
    }
  }
}

// MARK: - Eintrags-Kachel

private struct EintragsKachel: View {
  let eintrag: Entry
  let onBearbeiten: () -> Void
  let onLoeschen: () -> Void

  var body: some View {
    MhKarte {
      HStack(spacing: 14) {
        ZStack {
          Circle().fill(eintrag.seite.avatarFlaeche).frame(width: 40, height: 40)
          Image(systemName: eintrag.seite.symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(eintrag.seite.akzentText)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(eintrag.titel).font(.nunito(16)).foregroundStyle(Mh.text)
          Text(eintrag.createTime.formatted(date: .omitted, time: .shortened))
            .font(.nunito(14))
            .foregroundStyle(Mh.textSekundaer)
        }
        Spacer(minLength: 8)
        Text(eintrag.wertText).font(.nunitoBold(16)).foregroundStyle(Mh.text)
        Button(action: onBearbeiten) {
          Image(systemName: "pencil").foregroundStyle(Mh.textSekundaer)
        }
        Button(action: onLoeschen) {
          Image(systemName: "trash").foregroundStyle(Mh.textSekundaer)
        }
      }
    }
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 52))
        .foregroundStyle(Mh.fehlerText)
      Text(meldung)
        .font(.nunito(16))
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button {
        onErneut()
      } label: {
        Label("Erneut versuchen", systemImage: "arrow.clockwise")
      }
      .buttonStyle(MhButtonStil())
    }
    .padding(32)
  }
}

// MARK: - Helfer

extension Entry {
  var titel: String {
    if seite.isFlasche, let art = flaschenArt {
      return "\(seite.apiValue) · \(art.apiValue)"
    }
    return seite.apiValue
  }

  var wertText: String {
    // Einheit aus dem API-Feld, lokal aus der Seite abgeleitet.
    if seite.hatMenge { return "\(menge ?? 0) \(anzeigeEinheit ?? "ml")" }
    if let dauerMinuten { return "\(dauerMinuten) min" }
    return "offen"
  }
}

extension Date {
  var tagesLabel: String {
    if Calendar.current.isDateInToday(self) { return "Heute" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern" }
    return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
  }
}

extension Array where Element: Hashable {
  /// Reihenfolge-erhaltendes Deduplizieren.
  func einmalig() -> [Element] {
    var gesehen = Set<Element>()
    return filter { gesehen.insert($0).inserted }
  }
}
