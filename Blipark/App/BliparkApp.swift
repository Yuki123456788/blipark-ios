import SwiftUI

@main
struct BliparkApp: App {
  private let environment = AppEnvironment.live()

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environment(\.appEnvironment, environment)
        .tint(BliparkStyle.brand)
    }
  }
}

