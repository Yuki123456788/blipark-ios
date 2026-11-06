import SwiftUI

struct ProfileView: View {
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
    }
    .navigationTitle("我的")
  }
}

