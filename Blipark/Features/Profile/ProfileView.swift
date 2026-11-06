import SwiftUI

struct ProfileView: View {
  @Environment(\.appEnvironment) private var environment

  var body: some View {
    List {
      Section("偏好") {
        Label("預設車種", systemImage: "car")
        Label("停車偏好", systemImage: "slider.horizontal.3")
        Label("觸發距離", systemImage: "scope")
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

