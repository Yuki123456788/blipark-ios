import SwiftUI

struct ProfileView: View {
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    List {
      Section("偏好") {
        NavigationLink {
          GeneralSettingsView(repository: environment.preferences)
        } label: {
          Label("App 設定", systemImage: "gearshape")
        }
      }

      Section("App") {
        LabeledContent("版本", value: "0.1.0")
      }

      #if DEBUG
      Section("開發與測試") {
        NavigationLink {
          DeveloperToolsView(repository: environment.testDatasets)
        } label: {
          Label("開發者工具", systemImage: "hammer")
        }
      }
      #endif
    }
    .navigationTitle("我的")
  }
}

