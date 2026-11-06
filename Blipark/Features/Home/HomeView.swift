import SwiftUI

struct HomeView: View {
  let onShowPlans: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        brandHeader

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("我的下一個計畫")
              .font(.headline)
            Spacer()
            Button("查看全部", action: onShowPlans)
              .font(.subheadline)
          }

          BliparkEmptyState(
            title: "還沒有停車計畫",
            message: "搜尋目的地，開始規劃附近的停車方式。",
            symbol: "calendar.badge.plus"
          )
          .frame(minHeight: 180)
          .bliparkCard()
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("準備去哪裡？")
            .font(.headline)
          NavigationLink {
            ContentUnavailableView(
              "目的地搜尋即將接上",
              systemImage: "magnifyingglass",
              description: Text("搜尋流程會透過可替換的資料 Provider 提供結果。")
            )
          } label: {
            Label("搜尋地點、地址或貼上連結", systemImage: "magnifyingglass")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
              .background(.background, in: RoundedRectangle(cornerRadius: 16))
              .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(.quaternary)
              }
          }
          .buttonStyle(.plain)
          .accessibilityHint("開啟目的地搜尋")
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationBarHidden(true)
  }

  private var brandHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "scope")
        .font(.title2.weight(.semibold))
        .foregroundStyle(BliparkStyle.brand)
      Text("Blipark")
        .font(.largeTitle.bold())
      Spacer()
    }
    .accessibilityElement(children: .combine)
  }
}

