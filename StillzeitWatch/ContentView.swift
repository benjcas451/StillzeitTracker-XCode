import SwiftUI

// Design-System „Minze & Honig 2.0“: Farben und Schrift aus MhUhr.swift
// (dunkle Rollen, Figtree). Aufbau der Uhr unverändert. Farbe ist Signal:
// neutrale Flächen, Datenfarben nur an den Symbolen (Stillen Minze,
// Flasche Honig, Brei/Wasser Flieder), gewählte Option selectedBg,
// Hauptaktion primary.

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
        Group {
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
        .font(.figtree(16))
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { store.refresh() }
      }
    }
    .font(.figtree(16))
  }

  private var lastEntry: some View {
    Group {
      if let entry = store.entries.first {
        VStack(spacing: 2) {
          Text("Letzter Eintrag")
            .font(.figtree(11))
            .foregroundStyle(MhUhr.textSecondary)
          HStack(spacing: 5) {
            Image(systemName: icon(for: entry.side))
              .foregroundStyle(color(for: entry.side))
            Text(entryTitle(for: entry)).font(.figtreeSemiBold(15))
            Text(entry.date, style: .time)
              .font(.figtreeSemiBold(15))
              .monospacedDigit()
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(MhUhr.surface, in: RoundedRectangle(cornerRadius: 16))
      } else {
        Text("Noch kein Eintrag")
          .font(.figtreeSemiBold(15))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(MhUhr.surface, in: RoundedRectangle(cornerRadius: 16))
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
            selectedTime == nil ? MhUhr.selectedBg : MhUhr.surface,
            in: RoundedRectangle(cornerRadius: 16))
          .foregroundStyle(selectedTime == nil ? MhUhr.onSelected : MhUhr.textSecondary)
      }

      Button {
        activeSheet = .time
      } label: {
        VStack(spacing: 1) {
          Text("Uhrzeit")
          if let selectedTime {
            Text(selectedTime, style: .time).font(.figtree(11)).monospacedDigit()
          }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(
          selectedTime == nil ? MhUhr.surface : MhUhr.selectedBg,
          in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(selectedTime == nil ? MhUhr.textSecondary : MhUhr.onSelected)
      }
    }
    .font(.figtreeMedium(12))
    .buttonStyle(.plain)
  }

  private var quickActions: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        ActionButton(
          title: "Links", systemImage: "chevron.left",
          symbolFarbe: MhUhr.data1
        ) {
          add(side: "Links")
        }
        ActionButton(
          title: "Rechts", systemImage: "chevron.right",
          symbolFarbe: MhUhr.data1
        ) {
          add(side: "Rechts")
        }
      }
      HStack(spacing: 6) {
        ActionButton(
          title: "Beidseitig", systemImage: "arrow.left.arrow.right",
          symbolFarbe: MhUhr.data1
        ) {
          add(side: "Beidseitig")
        }
        ActionButton(
          title: "Flasche", systemImage: "waterbottle",
          symbolFarbe: MhUhr.data2
        ) {
          activeSheet = .newBottle
        }
      }
      // Nur bei aktiver Server-Option – der Server lehnt POSTs sonst ab.
      if store.breiWasserAktiv {
        HStack(spacing: 6) {
          ActionButton(
            title: "Brei", systemImage: "fork.knife",
            symbolFarbe: MhUhr.data3
          ) {
            activeSheet = .newMenge(side: "Brei")
          }
          ActionButton(
            title: "Wasser", systemImage: "drop.fill",
            symbolFarbe: MhUhr.data3
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
          .font(.figtree(13))
          .foregroundStyle(MhUhr.danger)
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
        .font(.figtree(11))
        .foregroundStyle(MhUhr.textSecondary)
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
        .font(.figtree(11))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(store.connection == nil ? .gray : MhUhr.link)
    .padding(.top, 8)
  }

  private var history: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Letzte Einträge")
        .font(.figtreeSemiBold(15))
        .padding(.top, 8)

      if store.entries.isEmpty {
        Text("Noch keine Einträge")
          .foregroundStyle(MhUhr.textSecondary)
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
                  .font(.figtree(11))
                  .foregroundStyle(MhUhr.textSecondary)
              }
              Spacer()
              Text(valueText(for: entry))
                .font(.figtree(12))
                .monospacedDigit()
              Image(systemName: "slider.horizontal.3")
                .font(.figtree(11))
                .foregroundStyle(MhUhr.textSecondary)
            }
            .padding(8)
            .background(MhUhr.surface, in: RoundedRectangle(cornerRadius: 12))
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

  /// Datenfarbe wie im Web: Stillen Minze, Flasche Honig, Brei/Wasser Flieder.
  private func color(for side: String) -> Color {
    switch side {
    case "Links", "Rechts", "Beidseitig": MhUhr.data1
    case "Brei", "Wasser": MhUhr.data3
    default: MhUhr.data2
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
          .font(.figtreeSemiBold(15))

        Text(store.statusText)
          .font(.figtree(15))
          .foregroundStyle(connected ? MhUhr.link : MhUhr.textSecondary)

        Text(
          connected
            ? "Anfragen gehen direkt an den Server. Ist er nicht erreichbar, springt die Uhr automatisch auf das iPhone um."
            : "Alle Anfragen laufen über das iPhone. Ist dort ein Server eingerichtet, kann die Uhr die Verbindung übernehmen."
        )
        .font(.figtree(11))
        .foregroundStyle(MhUhr.textSecondary)
        .multilineTextAlignment(.center)

        if store.isLoading {
          ProgressView()
        }

        if let message = store.errorMessage {
          Text(message)
            .font(.figtree(11))
            .foregroundStyle(MhUhr.danger)
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
        .tint(MhUhr.primary)
        .foregroundStyle(MhUhr.onPrimary)
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

/// Schnellaktion: neutrale Fläche, Text in Textfarbe, das Symbol trägt die
/// Datenfarbe der Seite.
private struct ActionButton: View {
  let title: String
  let systemImage: String
  let symbolFarbe: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage).font(.title3).foregroundStyle(symbolFarbe)
        Text(title).font(.figtreeMedium(11)).lineLimit(1).minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .background(MhUhr.surface, in: RoundedRectangle(cornerRadius: 12))
      .foregroundStyle(MhUhr.textStrong)
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
        .tint(MhUhr.primary)
        .foregroundStyle(MhUhr.onPrimary)
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
              .tint(bottleType == type ? MhUhr.link : .gray)
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
          .foregroundStyle(MhUhr.link)
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
            .foregroundStyle(MhUhr.link)
        }
      }
    }
  }
}
