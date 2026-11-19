import SwiftUI

enum AppTab: Hashable {
  case home
  case plans
  case profile
}

struct RootTabView: View {
  @State private var selection: AppTab = .home

  var body: some View {
    TabView(selection: $selection) {
      NavigationStack {
        HomeView(onShowPlans: { selection = .plans })
      }
      .tabItem { Label("首頁", systemImage: "house") }
      .tag(AppTab.home)

      NavigationStack {
        PlansView()
      }
      .tabItem { Label("計畫", systemImage: "folder") }
      .tag(AppTab.plans)

      NavigationStack {
        ProfileView()
      }
      .tabItem { Label("我的", systemImage: "person") }
      .tag(AppTab.profile)
    }
  }
}

