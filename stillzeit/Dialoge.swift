import SwiftUI

// MARK: - Dialog-Zustände (steuern die Sheets in HomeView)

struct FlascheDialogZustand: Identifiable {
  let id = UUID()
  /// nil = neuen Eintrag anlegen, sonst bearbeiten.
  let eintrag: Entry?
}

struct DauerDialogZustand: Identifiable {
  let id = UUID()
  let seite: Seite
  /// nil = neuen Eintrag anlegen, sonst bearbeiten.
  let eintrag: Entry?
}

// MARK: - Flaschen-Dialog (Menge + Pre/Mutter)

struct FlascheDialog: View {
  let zustand: FlascheDialogZustand
  let onSpeichern: (Int, FlaschenArt) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var mengeText: String
  @State private var flaschenArt: FlaschenArt
  @State private var hinweis: String?
  @FocusState private var fokus: Bool

  init(zustand: FlascheDialogZustand, onSpeichern: @escaping (Int, FlaschenArt) -> Void) {
    self.zustand = zustand
    self.onSpeichern = onSpeichern
    _mengeText = State(initialValue: zustand.eintrag?.menge.map(String.init) ?? "")
    _flaschenArt = State(initialValue: zustand.eintrag?.flaschenArt ?? .pre)
  }

  var body: some View {
    DialogRahmen(titel: zustand.eintrag == nil ? "Flasche hinzufügen" : "Flasche ändern") {
      SegmentAuswahl(auswahl: $flaschenArt)
      MhEingabefeld(
        text: $mengeText, platzhalter: "Menge in ml", einheit: "ml", fokus: $fokus)
      if let hinweis {
        Text(hinweis).font(.nunito(14)).foregroundStyle(Mh.fehlerText)
      }
    } aktionen: {
      DialogAktionen(onAbbrechen: { dismiss() }) {
        guard let menge = Int(mengeText.trimmingCharacters(in: .whitespaces)), menge >= 0 else {
          hinweis = "Bitte eine gültige Menge (≥ 0) eingeben."
          return
        }
        onSpeichern(menge, flaschenArt)
        dismiss()
      }
    }
    .onAppear { fokus = true }
  }
}

// MARK: - Dauer-Dialog

struct DauerDialog: View {
  let zustand: DauerDialogZustand
  let onSpeichern: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var dauerText: String
  @State private var hinweis: String?
  @FocusState private var fokus: Bool

  init(zustand: DauerDialogZustand, onSpeichern: @escaping (Int) -> Void) {
    self.zustand = zustand
    self.onSpeichern = onSpeichern
    _dauerText = State(initialValue: zustand.eintrag?.dauerMinuten.map(String.init) ?? "")
  }

  var body: some View {
    DialogRahmen(
      titel: zustand.eintrag == nil ? "\(zustand.seite.apiValue) hinzufügen" : "Dauer ändern"
    ) {
      MhEingabefeld(text: $dauerText, platzhalter: "Dauer", einheit: "min", fokus: $fokus)
      if let hinweis {
        Text(hinweis).font(.nunito(14)).foregroundStyle(Mh.fehlerText)
      }
    } aktionen: {
      DialogAktionen(onAbbrechen: { dismiss() }) {
        guard let dauer = Int(dauerText.trimmingCharacters(in: .whitespaces)), dauer >= 0 else {
          hinweis = "Bitte eine gültige Dauer (≥ 0) eingeben."
          return
        }
        onSpeichern(dauer)
        dismiss()
      }
    }
    .onAppear { fokus = true }
  }
}

// MARK: - Uhrzeit-Auswahl

struct ZeitwahlSheet: View {
  let initial: Date?
  let onUebernehmen: (Date) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var zeit: Date

  init(initial: Date?, onUebernehmen: @escaping (Date) -> Void) {
    self.initial = initial
    self.onUebernehmen = onUebernehmen
    _zeit = State(initialValue: initial ?? Date())
  }

  var body: some View {
    DialogRahmen(titel: "Uhrzeit wählen") {
      DatePicker("", selection: $zeit, displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    } aktionen: {
      DialogAktionen(speichernTitel: "Übernehmen", onAbbrechen: { dismiss() }) {
        onUebernehmen(zeit)
        dismiss()
      }
    }
  }
}

// MARK: - Gemeinsame Bausteine

/// Sheet im Guide-Look: Karte mit Radius 24, Titel in Nunito ExtraBold.
private struct DialogRahmen<Inhalt: View, Aktionen: View>: View {
  let titel: String
  @ViewBuilder let inhalt: () -> Inhalt
  @ViewBuilder let aktionen: () -> Aktionen

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(titel).font(.nunitoExtraBold(20)).foregroundStyle(Mh.text)
      inhalt()
      aktionen()
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Mh.karte.ignoresSafeArea())
    .presentationDetents([.height(320)])
    // Radius 24 (Guide: Modals) — erst ab iOS 16.4 steuerbar.
    .modifier(EckenRadiusFallsVerfuegbar())
  }
}

private struct EckenRadiusFallsVerfuegbar: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.4, *) {
      content.presentationCornerRadius(24)
    } else {
      content
    }
  }
}

private struct DialogAktionen: View {
  var speichernTitel = "Speichern"
  let onAbbrechen: () -> Void
  let onSpeichern: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button("Abbrechen", action: onAbbrechen)
        .font(.nunitoBold(16))
        .foregroundStyle(Mh.gruenText)
      Button(speichernTitel, action: onSpeichern)
        .buttonStyle(MhButtonStil())
    }
  }
}

/// Eingabefeld nach Guide: zarte Fläche, Rand Grau-200, Radius 12.
struct MhEingabefeld: View {
  @Binding var text: String
  let platzhalter: String
  var einheit: String?
  var fokus: FocusState<Bool>.Binding

  var body: some View {
    HStack {
      TextField(platzhalter, text: $text)
        .keyboardType(.numberPad)
        .font(.nunito(16))
        .focused(fokus)
      if let einheit {
        Text(einheit).font(.nunito(14)).foregroundStyle(Mh.textSekundaer)
      }
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 44)
    .background(Mh.feldFlaeche)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(fokus.wrappedValue ? Mh.minze500 : Mh.rand, lineWidth: 1.5)
    )
  }
}

/// Pre/Mutter-Auswahl: aktives Segment Minze-300 mit 900er-Text.
private struct SegmentAuswahl: View {
  @Binding var auswahl: FlaschenArt

  var body: some View {
    HStack(spacing: 0) {
      ForEach(FlaschenArt.allCases) { art in
        Button {
          auswahl = art
        } label: {
          HStack(spacing: 6) {
            if auswahl == art { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
            Text(art.apiValue).font(.nunitoBold(15))
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(auswahl == art ? Mh.minze300 : Mh.karte)
          .foregroundStyle(auswahl == art ? Mh.minze900 : Mh.text)
        }
      }
    }
    .clipShape(Capsule())
    .overlay(Capsule().strokeBorder(Mh.rand, lineWidth: 1.5))
  }
}
