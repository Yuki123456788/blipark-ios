import SwiftUI

@main
struct BliparkApp: App {
  private let environment = AppEnvironment.live()
  @StateObject private var pipRuntime = ParkingGuidancePiPRuntime()

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environment(\.appEnvironment, environment)
        .environmentObject(pipRuntime)
        .tint(BliparkStyle.brand)
    }
  }
}

