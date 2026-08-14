import SwiftUI

@main
struct StillzeitWatchApp: App {
  @StateObject private var store = WatchConnectivityStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(store)
    }
  }
}
