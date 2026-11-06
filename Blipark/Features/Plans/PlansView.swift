import SwiftUI

struct PlansView: View {
  var body: some View {
    BliparkEmptyState(
      title: "尚無計畫",
      message: "從目的地探索選擇候選停車點後，就能儲存成計畫。",
      symbol: "folder.badge.plus"
    )
    .navigationTitle("計畫")
  }
}

