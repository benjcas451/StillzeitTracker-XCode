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

struct MengeDialogZustand: Identifiable {
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
      MhFeld("Art") {
        HStack(spacing: Mh.abstand2) {
          ForEach(FlaschenArt.allCases) { art in
            MhAuswahl(art.apiValue, gewaehlt: flaschenArt == art) { flaschenArt = art }
          }
        }
      }
      MhFeld("Menge (ml)") {
        MhZahlFeld(text: $mengeText, platzhalter: "z. B. 120 (0 = leer)", einheit: "ml", fokus: $fokus)
      }
      DialogHinweis(text: hinweis)
    } aktionen: {
      DialogAktionen(onAbbrechen: { dismiss() }) {
        guard let menge = Int(mengeText.trimmingCharacters(in: .whitespaces)), menge >= 0 else {
          hinweis = "Bitte eine gültige Menge eingeben (0 oder mehr)"
          return
        }
        onSpeichern(menge, flaschenArt)
        dismiss()
      }
    }
    .onAppear { fokus = true }
  }
}

// MARK: - Mengen-Dialog (Brei in g, Wasser in ml — ohne Pre/Mutter)

struct MengeDialog: View {
  let zustand: MengeDialogZustand
  let onSpeichern: (Int) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var mengeText: String
  @State private var hinweis: String?
  @FocusState private var fokus: Bool

  init(zustand: MengeDialogZustand, onSpeichern: @escaping (Int) -> Void) {
    self.zustand = zustand
    self.onSpeichern = onSpeichern
    _mengeText = State(initialValue: zustand.eintrag?.menge.map(String.init) ?? "")
  }

  private var einheit: String { zustand.seite.mengenEinheit ?? "ml" }

  var body: some View {
    DialogRahmen(
      titel: zustand.eintrag == nil ? "\(zustand.seite.apiValue) hinzufügen" : "Menge ändern"
    ) {
      MhFeld("Menge (\(einheit))") {
        MhZahlFeld(
          text: $mengeText,
          platzhalter: einheit == "g" ? "z. B. 90 (0 = leer)" : "z. B. 120 (0 = leer)",
          einheit: einheit,
          fokus: $fokus)
      }
      DialogHinweis(text: hinweis)
    } aktionen: {
      DialogAktionen(onAbbrechen: { dismiss() }) {
        guard let menge = Int(mengeText.trimmingCharacters(in: .whitespaces)), menge >= 0 else {
          hinweis = "Bitte eine gültige Menge eingeben (0 oder mehr)"
          return
        }
        onSpeichern(menge)
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
      MhFeld("Dauer (Minuten)") {
        MhZahlFeld(text: $dauerText, platzhalter: "z. B. 12", einheit: "min", fokus: $fokus)
      }
      DialogHinweis(text: hinweis)
    } aktionen: {
      DialogAktionen(onAbbrechen: { dismiss() }) {
        guard let dauer = Int(dauerText.trimmingCharacters(in: .whitespaces)), dauer >= 0 else {
          hinweis = "Bitte eine gültige Dauer eingeben (0 oder mehr)"
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
      DatePicker("Uhrzeit", selection: $zeit, displayedComponents: .hourAndMinute)
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

/// Blatt im 2.0-Look: Fläche `surface`, Titel H2 linksbündig, Radius 20.
private struct DialogRahmen<Inhalt: View, Aktionen: View>: View {
  let titel: String
  @ViewBuilder let inhalt: () -> Inhalt
  @ViewBuilder let aktionen: () -> Aktionen

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Mh.abstand5) {
        Text(titel)
          .mhText(.h2)
          .foregroundStyle(Mh.textStrong)
          .accessibilityAddTraits(.isHeader)
        inhalt()
        aktionen()
      }
      .padding(Mh.abstand6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Mh.surface.ignoresSafeArea())
    .presentationDetents([.medium, .large])
    // Radius 20 (Guide: Dialoge) — erst ab iOS 16.4 steuerbar.
    .modifier(EckenRadiusFallsVerfuegbar())
  }
}

private struct EckenRadiusFallsVerfuegbar: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.4, *) {
      content.presentationCornerRadius(Mh.radiusXl)
    } else {
      content
    }
  }
}

/// Eine Hauptaktion rechts, „Abbrechen“ leise als Text davor.
private struct DialogAktionen: View {
  var speichernTitel = "Speichern"
  let onAbbrechen: () -> Void
  let onSpeichern: () -> Void

  var body: some View {
    HStack(spacing: Mh.abstand4) {
      Spacer(minLength: 0)
      Button("Abbrechen", action: onAbbrechen)
        .buttonStyle(.mhText)
      Button(speichernTitel, action: onSpeichern)
        .buttonStyle(.mhHaupt)
    }
  }
}

/// Fehlerhinweis unter den Feldern (nur sichtbar, wenn es einen gibt).
private struct DialogHinweis: View {
  let text: String?

  var body: some View {
    if let text {
      Text(text).mhText(.small).foregroundStyle(Mh.danger)
    }
  }
}

/// Zahlenfeld (`input`): 44 pt, Radius 10, Haarlinie `borderStrong`, Grund
/// `fieldBg`, Einheit rechts im Feld in Nebentextfarbe.
struct MhZahlFeld: View {
  @Binding var text: String
  let platzhalter: String
  var einheit: String?
  var fokus: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: Mh.abstand2) {
      TextField(platzhalter, text: $text)
        .keyboardType(.numberPad)
        .mhText(.body)
        .foregroundStyle(Mh.text)
        .tint(Mh.primary)
        .focused(fokus)
      if let einheit {
        Text(einheit).mhText(.body).foregroundStyle(Mh.textSecondary)
      }
    }
    .padding(.horizontal, Mh.abstand3)
    .frame(minHeight: Mh.touch)
    .background(
      RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous).fill(Mh.fieldBg))
    .overlay(
      RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
        .stroke(fokus.wrappedValue ? Mh.focusRing : Mh.borderStrong, lineWidth: 1))
  }
}
