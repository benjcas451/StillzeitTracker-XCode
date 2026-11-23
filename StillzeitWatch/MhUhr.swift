import SwiftUI

// ============================================================================
// Minze & Honig 2.0 – Farben und Schrift der Uhr (nur dunkel)
// Quelle: DesignGuide/tokens/design-tokens.json, semantic.dark. Die Uhr
// behält den schwarzen watchOS-Grund; Flächen, Linien und Text kommen aus
// den dunklen Rollen. Farbe ist Signal, keine Fläche: Pastell nur für
// Symbole, die gewählte Option ist `selectedBg`/`onSelected`, die
// Hauptaktion `primary`/`onPrimary`. Kein UIKit (watchOS).
// ============================================================================

private func mhFarbe(_ wert: UInt32) -> Color {
  Color(
    red: Double((wert >> 16) & 0xFF) / 255,
    green: Double((wert >> 8) & 0xFF) / 255,
    blue: Double(wert & 0xFF) / 255)
}

/// Dunkle Rollen des Guides (Namen wie in design-tokens.json).
enum MhUhr {
  static let surface = mhFarbe(0x262A28)
  static let surfaceSubtle = mhFarbe(0x2B302D)
  static let border = mhFarbe(0x343A36)
  static let borderStrong = mhFarbe(0x454C47)
  static let text = mhFarbe(0xE6EAE7)
  static let textStrong = mhFarbe(0xFFFFFF)
  static let textSecondary = mhFarbe(0xA9B0AB)
  static let link = mhFarbe(0xA8D5BA)
  static let primary = mhFarbe(0x82BD9B)
  static let onPrimary = mhFarbe(0x1F2221)
  static let selectedBg = mhFarbe(0x2C4F3B)
  static let onSelected = mhFarbe(0xC8E8D4)
  static let danger = mhFarbe(0xF0B6B1)
  /// Datenfarben wie im Web: Stillen Minze, Flasche Honig, Brei/Wasser Flieder.
  static let data1 = mhFarbe(0xA8D5BA)
  static let data2 = mhFarbe(0xF7E8A4)
  static let data3 = mhFarbe(0xCDB4DB)
}

/// Figtree (400/500/600) über `UIAppFonts` der Watch-Info.plist, mit
/// Dynamic Type.
extension Font {
  static func figtree(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-Regular", size: groesse, relativeTo: stil)
  }
  static func figtreeMedium(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-Medium", size: groesse, relativeTo: stil)
  }
  static func figtreeSemiBold(_ groesse: CGFloat, relativeTo stil: Font.TextStyle = .body) -> Font {
    .custom("Figtree-SemiBold", size: groesse, relativeTo: stil)
  }
}
