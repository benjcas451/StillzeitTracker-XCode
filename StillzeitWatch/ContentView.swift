import SwiftUI

// Design-System „Minze & Honig" (v1.0) – die Uhr folgt den Dark-Regeln aus
// Guide 2.8: Pastellflächen (300) mit 900er-Text als Akzente, zarte Flächen
// als abgedunkelte 100er-Äquivalente, Fehler in Rot-300. Zuordnung wie auf
// dem iPhone: Links=Minze, Rechts=Flieder, Beidseitig=Grau, Flasche=Honig,
// Brei=Honig eine Stufe dunkler (400), Wasser=Grau.
enum MhW {
  static let minze300 = Color(red: 0xA8 / 255, green: 0xD5 / 255, blue: 0xBA / 255)
  static let minze900 = Color(red: 0x22 / 255, green: 0x39 / 255, blue: 0x2C / 255)
  static let minzeDunkel = Color(red: 0x26 / 255, green: 0x3B / 255, blue: 0x2F / 255)
  static let honig300 = Color(red: 0xF7 / 255, green: 0xE8 / 255, blue: 0xA4 / 255)
  static let honig400 = Color(red: 0xED / 255, green: 0xD3 / 255, blue: 0x74 / 255)
  static let honig900 = Color(red: 0x47 / 255, green: 0x3A / 255, blue: 0x17 / 255)
  static let honigDunkel = Color(red: 0x3B / 255, green: 0x35 / 255, blue: 0x24 / 255)
  static let flieder300 = Color(red: 0xCD / 255, green: 0xB4 / 255, blue: 0xDB / 255)
  static let flieder900 = Color(red: 0x37 / 255, green: 0x26 / 255, blue: 0x3F / 255)
  static let fliederDunkel = Color(red: 0x35 / 255, green: 0x2B / 255, blue: 0x3C / 255)
  static let grau300 = Color(red: 0xC6 / 255, green: 0xCD / 255, blue: 0xC9 / 255)
  static let grauRand = Color(red: 0x3A / 255, green: 0x40 / 255, blue: 0x3C / 255)
  static let karte = Color(red: 0x29 / 255, green: 0x2D / 255, blue: 0x2B / 255)
  static let textHell = Color(red: 0xEC / 255, green: 0xEF / 255, blue: 0xED / 255)
  static let rot300 = Color(red: 0xF0 / 255, green: 0xB6 / 255, blue: 0xB1 / 255)
}

extension Font {
  static func nunito(_ groesse: CGFloat) -> Font {
    .custom("NunitoExtraLight-Regular", size: groesse)
  }
  static func nunitoBold(_ groesse: CGFloat) -> Font {
    .custom("NunitoExtraLight-Bold", size: groesse)
  }
}

/// Alle Blätter laufen bewusst über **einen** `.sheet`-Modifier: mehrere
/// `.sheet`-Modifier an derselben View sind in SwiftUI nicht zugesichert, in
/// der Praxis öffnet sich dann je nach Version nur noch ein Teil davon.
private enum ActiveSheet: Identifiable {
  case time
  case newBottle
  case newMenge(side: String)
  case connection
  case edit(WatchEntry)

  var id: String {
    switch self {
    case .time: "time"
    case .newBottle: "newBottle"
    case .newMenge(let side): "newMenge-\(side)"
    case .connection: "connection"
    case .edit(let entry): "edit-\(entry.id)"
    }
  }
}

struct ContentView: View {
  @EnvironmentObject private var store: WatchConnectivityStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTime: Date?
  @State private var activeSheet: ActiveSheet?

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 10) {
          lastEntry
          timeSelector
          quickActions
          connectionMessage
          noticeMessage
          history
          connectionStatus
        }
        .padding(.horizontal, 3)
      }
      .navigationTitle("Stillzeit")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: store.refresh) {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(store.isLoading)
        }
      }
      .overlay {
        if store.isLoading { ProgressView() }
      }
      .sheet(item: $activeSheet) { sheet in
        switch sheet {
        case .time:
          TimePicker(initialDate: selectedTime ?? .now) { date in
            selectedTime = date
            activeSheet = nil
          }

        case .newBottle:
          BottlePicker(
            title: "Flasche",
            values: Array(stride(from: 10, through: 300, by: 10)),
            initialValue: 90,
            initialBottleType: "Pre"
          ) { amount, bottleType in
            activeSheet = nil
            store.add(
              side: "Flasche",
              amount: amount,
              bottleType: bottleType,
              at: selectedTime
            )
            selectedTime = nil
          }

        case .newMenge(let side):
          ValuePicker(
            title: side,
            unit: einheit(fuer: side),
            values: Array(stride(from: 10, through: 300, by: 10)),
            initialValue: side == "Brei" ? 90 : 30
          ) { amount in
            activeSheet = nil
            store.add(side: side, amount: amount, at: selectedTime)
            selectedTime = nil
          }

        case .connection:
          ConnectionView(store: store)

        case .edit(let entry):
          if entry.side == "Flasche" {
            let amount = entry.amount ?? 0
            BottlePicker(
              title: entryTitle(for: entry),
              values: Self.values(
                Array(stride(from: 0, through: 300, by: 10)), including: amount),
              initialValue: amount,
              initialBottleType: entry.bottleType ?? "Pre"
            ) { value, bottleType in
              activeSheet = nil
              store.update(entry, value: value, bottleType: bottleType)
            }
          } else if hatMenge(entry.side) {
            // Brei/Wasser: Menge ändern, ohne Flaschen-Art.
            let amount = entry.amount ?? 0
            ValuePicker(
              title: entry.side,
              unit: entry.unit ?? einheit(fuer: entry.side),
              values: Self.values(
                Array(stride(from: 0, through: 300, by: 10)), including: amount),
              initialValue: amount
            ) { value in
              activeSheet = nil
              store.update(entry, value: value)
            }
          } else {
            let duration = entry.duration ?? 0
            ValuePicker(
              title: entry.side,
              unit: "Min.",
              values: Self.values(Array(0...120), including: duration),
              initialValue: duration
            ) { value in
              activeSheet = nil
              store.update(entry, value: value)
            }
          }
        }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { store.refresh() }
      }
    }
  }

  private var lastEntry: some View {
    Group {
      if let entry = store.entries.first {
        VStack(spacing: 2) {
          Text("Letzter Eintrag")
            .font(.nunito(11))
            .foregroundStyle(.secondary)
          HStack(spacing: 5) {
            Image(systemName: icon(for: entry.side))
              .foregroundStyle(color(for: entry.side))
            Text(entryTitle(for: entry)).font(.nunitoBold(15))
            Text(entry.date, style: .time)
              .font(.nunitoBold(15))
              .monospacedDigit()
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(subtleBackground(for: entry.side), in: RoundedRectangle(cornerRadius: 16))
      } else {
        Text("Noch kein Eintrag")
          .font(.nunitoBold(15))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(MhW.karte, in: RoundedRectangle(cornerRadius: 16))
      }
    }
  }

  private var timeSelector: some View {
    HStack(spacing: 6) {
      Button {
        selectedTime = nil
      } label: {
        Label("Jetzt", systemImage: selectedTime == nil ? "checkmark.circle.fill" : "clock")
          .frame(maxWidth: .infinity, minHeight: 32)
          .background(
            selectedTime == nil ? MhW.minze300 : MhW.karte,
            in: RoundedRectangle(cornerRadius: 16))
          .foregroundStyle(selectedTime == nil ? MhW.minze900 : .secondary)
      }

      Button {
        activeSheet = .time
      } label: {
        VStack(spacing: 1) {
          Text("Uhrzeit")
          if let selectedTime {
            Text(selectedTime, style: .time).font(.nunito(11)).monospacedDigit()
          }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(
          selectedTime == nil ? MhW.karte : MhW.minze300,
          in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(selectedTime == nil ? .secondary : MhW.minze900)
      }
    }
    .font(.nunitoBold(12))
    .buttonStyle(.plain)
  }

  private var quickActions: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        ActionButton(
          title: "Links", systemImage: "chevron.left",
          flaeche: MhW.minze300, inhalt: MhW.minze900
        ) {
          add(side: "Links")
        }
        ActionButton(
          title: "Rechts", systemImage: "chevron.right",
          flaeche: MhW.flieder300, inhalt: MhW.flieder900
        ) {
          add(side: "Rechts")
        }
      }
      HStack(spacing: 6) {
        ActionButton(
          title: "Beidseitig", systemImage: "arrow.left.arrow.right",
          flaeche: MhW.grauRand, inhalt: MhW.textHell
        ) {
          add(side: "Beidseitig")
        }
        ActionButton(
          title: "Flasche", systemImage: "waterbottle",
          flaeche: MhW.honig300, inhalt: MhW.honig900
        ) {
          activeSheet = .newBottle
        }
      }
      // Nur bei aktiver Server-Option – der Server lehnt POSTs sonst ab.
      if store.breiWasserAktiv {
        HStack(spacing: 6) {
          ActionButton(
            title: "Brei", systemImage: "fork.knife",
            flaeche: MhW.honig400, inhalt: MhW.honig900
          ) {
            activeSheet = .newMenge(side: "Brei")
          }
          ActionButton(
            title: "Wasser", systemImage: "drop.fill",
            flaeche: MhW.grauRand, inhalt: MhW.textHell
          ) {
            activeSheet = .newMenge(side: "Wasser")
          }
        }
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var connectionMessage: some View {
    if let message = store.errorMessage {
      VStack(spacing: 6) {
        Text(message)
          .font(.nunito(13))
          .foregroundStyle(MhW.rot300)
          .multilineTextAlignment(.center)
        Button(action: store.refresh) {
          Label("Erneut verbinden", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(store.isLoading)
      }
      .padding(.vertical, 4)
    }
  }

  @ViewBuilder
  private var noticeMessage: some View {
    if let notice = store.notice {
      Text(notice)
        .font(.nunito(11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  /// Zeigt, ob die Uhr direkt mit dem Server spricht oder über das iPhone geht
  /// — und führt zum Übernehmen der Verbindung.
  private var connectionStatus: some View {
    Button {
      activeSheet = .connection
    } label: {
      Label(store.statusText, systemImage: store.connection == nil ? "iphone" : "link")
        .font(.nunito(11))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(store.connection == nil ? .gray : MhW.minze300)
    .padding(.top, 8)
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Letzte Einträge")
        .font(.nunitoBold(15))
        .padding(.top, 8)

      if store.entries.isEmpty {
        Text("Noch keine Einträge")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.entries) { entry in
          Button {
            activeSheet = .edit(entry)
          } label: {
            HStack {
              Image(systemName: icon(for: entry.side))
                .foregroundStyle(color(for: entry.side))
              VStack(alignment: .leading, spacing: 1) {
                Text(entryTitle(for: entry))
                Text(entry.date, style: .time)
                  .font(.nunito(11))
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(valueText(for: entry))
                .font(.nunito(12))
                .monospacedDigit()
              Image(systemName: "slider.horizontal.3")
                .font(.nunito(11))
                .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(MhW.karte, in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func add(side: String) {
    store.add(side: side, at: selectedTime)
    selectedTime = nil
  }

  /// Nimmt den gespeicherten Wert mit in die Auswahl auf, falls er nicht ins
  /// Raster passt.
  ///
  /// Auf dem Telefon sind ml und Minuten frei eintippbar (Textfeld ohne
  /// Schrittweite und ohne Obergrenze), die Uhr bietet dagegen nur ein festes
  /// Raster. Fehlt der Wert darin, findet `Picker` kein passendes `tag` — das
  /// Rad bleibt dann ohne Auswahl stehen und lässt sich nicht bedienen.
  static func values(_ grid: [Int], including current: Int) -> [Int] {
    guard current >= 0, !grid.contains(current) else { return grid }
    return (grid + [current]).sorted()
  }

  private func valueText(for entry: WatchEntry) -> String {
    if hatMenge(entry.side) {
      return "\(entry.amount ?? 0) \(entry.unit ?? einheit(fuer: entry.side))"
    }
    return "\(entry.duration ?? 0) Min."
  }

  private func entryTitle(for entry: WatchEntry) -> String {
    guard entry.side == "Flasche", let bottleType = entry.bottleType else {
      return entry.side
    }
    return "Flasche · \(bottleType)"
  }

  private func icon(for side: String) -> String {
    switch side {
    case "Links": "chevron.left"
    case "Rechts": "chevron.right"
    case "Beidseitig": "arrow.left.arrow.right"
    case "Brei": "fork.knife"
    case "Wasser": "drop.fill"
    default: "waterbottle"
    }
  }

  private func color(for side: String) -> Color {
    switch side {
    case "Links": MhW.minze300
    case "Rechts": MhW.flieder300
    case "Beidseitig": MhW.grau300
    case "Brei": MhW.honig400
    case "Wasser": MhW.grau300
    default: MhW.honig300
    }
  }

  /// Zarte, abgedunkelte Fläche hinter der Letzter-Eintrag-Karte.
  private func subtleBackground(for side: String) -> Color {
    switch side {
    case "Links": MhW.minzeDunkel
    case "Rechts": MhW.fliederDunkel
    case "Beidseitig": MhW.karte
    case "Wasser": MhW.karte
    default: MhW.honigDunkel
    }
  }
}

/// Übernimmt die auf dem iPhone eingerichtete Server-Verbindung, sodass die
/// Uhr anschließend selbst mit dem Server spricht.
private struct ConnectionView: View {
  @ObservedObject var store: WatchConnectivityStore
  @Environment(\.dismiss) private var dismiss

  private var connected: Bool { store.connection != nil }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Text("Server-Verbindung")
          .font(.nunitoBold(15))

        Text(store.statusText)
          .font(.nunito(15))
          .foregroundStyle(connected ? MhW.minze300 : .secondary)

        Text(
          connected
            ? "Anfragen gehen direkt an den Server. Ist er nicht erreichbar, springt die Uhr automatisch auf das iPhone um."
            : "Alle Anfragen laufen über das iPhone. Ist dort ein Server eingerichtet, kann die Uhr die Verbindung übernehmen."
        )
        .font(.nunito(11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

        if store.isLoading {
          ProgressView()
        }

        if let message = store.errorMessage {
          Text(message)
            .font(.nunito(11))
            .foregroundStyle(MhW.rot300)
            .multilineTextAlignment(.center)
        }

        Button {
          store.importConnection()
        } label: {
          Label(
            connected ? "Erneut importieren" : "Verbindung importieren",
            systemImage: "square.and.arrow.down"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MhW.minze300)
        .foregroundStyle(MhW.minze900)
        .disabled(store.isLoading)

        if connected {
          Button(role: .destructive) {
            store.removeConnection()
          } label: {
            Label("Verbindung entfernen", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(store.isLoading)
        }

        Button("Fertig") { dismiss() }
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 4)
    }
  }
}

private struct ActionButton: View {
  let title: String
  let systemImage: String
  let flaeche: Color
  let inhalt: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage).font(.title3)
        Text(title).font(.nunitoBold(11)).lineLimit(1).minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(flaeche, in: RoundedRectangle(cornerRadius: 12))
      .foregroundStyle(inhalt)
    }
  }
}

private struct TimePicker: View {
  @State private var date: Date
  let onSave: (Date) -> Void

  init(initialDate: Date, onSave: @escaping (Date) -> Void) {
    _date = State(initialValue: initialDate)
    self.onSave = onSave
  }

  var body: some View {
    VStack {
      DatePicker("Uhrzeit", selection: $date, displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
      Button("Übernehmen") { onSave(date) }
        .buttonStyle(.borderedProminent)
        .tint(MhW.minze300)
        .foregroundStyle(MhW.minze900)
    }
  }
}

/// Eingabe eines Zahlenwerts: frei eintippbar wie auf dem Telefon, darunter
/// eine Schnellauswahl der gängigen Werte.
///
/// Bewusst eine `List` statt eines Wheel-`Picker`: ein Wheel-Picker fällt auf
/// watchOS innerhalb eines `VStack` neben anderen Bedienelementen auf Höhe 0
/// zusammen — sichtbar bleibt dann nur seine Beschriftung.
private struct ValuePicker: View {
  let title: String
  let unit: String
  let values: [Int]
  let initialValue: Int
  let onSave: (Int) -> Void

  @State private var customValue: Int

  init(
    title: String,
    unit: String,
    values: [Int],
    initialValue: Int,
    onSave: @escaping (Int) -> Void
  ) {
    self.title = title
    self.unit = unit
    self.values = values
    self.initialValue = initialValue
    self.onSave = onSave
    _customValue = State(initialValue: initialValue)
  }

  var body: some View {
    List {
      Section(title) {
        FreeValueField(unit: unit, value: $customValue) { onSave(max(0, customValue)) }
      }

      Section("Schnellauswahl") {
        ForEach(values, id: \.self) { item in
          SelectableRow(
            text: "\(item) \(unit)",
            isSelected: item == initialValue
          ) {
            onSave(item)
          }
        }
      }
    }
  }
}

/// Menge und Inhalt einer Flasche. Der Inhalt wird oben umgeschaltet und bei
/// jeder Übernahme mitgespeichert.
private struct BottlePicker: View {
  let title: String
  let values: [Int]
  let initialValue: Int
  let onSave: (Int, String) -> Void

  @State private var bottleType: String
  @State private var customValue: Int

  init(
    title: String,
    values: [Int],
    initialValue: Int,
    initialBottleType: String,
    onSave: @escaping (Int, String) -> Void
  ) {
    self.title = title
    self.values = values
    self.initialValue = initialValue
    self.onSave = onSave
    _bottleType = State(initialValue: initialBottleType)
    _customValue = State(initialValue: initialValue)
  }

  var body: some View {
    List {
      Section(title) {
        HStack(spacing: 5) {
          ForEach(["Pre", "Mutter"], id: \.self) { type in
            Button(type) { bottleType = type }
              .buttonStyle(.bordered)
              .tint(bottleType == type ? MhW.minze300 : .gray)
              .frame(maxWidth: .infinity)
          }
        }

        FreeValueField(unit: "ml", value: $customValue) {
          onSave(max(0, customValue), bottleType)
        }
      }

      Section("Schnellauswahl") {
        ForEach(values, id: \.self) { item in
          SelectableRow(
            text: "\(item) ml",
            isSelected: item == initialValue
          ) {
            onSave(item, bottleType)
          }
        }
      }
    }
  }
}

/// Freies Eintippen einer Zahl — damit sind auf der Uhr dieselben Werte
/// erreichbar wie im Textfeld der Telefon-App, also auch krumme Zahlen und
/// Werte oberhalb der Schnellauswahl.
private struct FreeValueField: View {
  let unit: String
  @Binding var value: Int
  let onSubmit: () -> Void

  var body: some View {
    TextField(unit, value: $value, format: .number)
      .onSubmit(onSubmit)

    Button(action: onSubmit) {
      HStack {
        Text("Übernehmen")
        Spacer()
        Text("\(max(0, value)) \(unit)")
          .foregroundStyle(MhW.minze300)
          .monospacedDigit()
      }
    }
  }
}

/// Eine antippbare Zeile; der aktuell gespeicherte Wert ist markiert.
private struct SelectableRow: View {
  let text: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(text)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(MhW.minze300)
        }
      }
    }
  }
}
