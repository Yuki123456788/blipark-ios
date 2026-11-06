import SwiftUI

struct PlansView: View {
  @Environment(\.appEnvironment) private var environment
  @State private var plans: [ParkingPlan] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if isLoading && plans.isEmpty {
        ProgressView("正在載入計畫…")
      } else if plans.isEmpty {
        BliparkEmptyState(
          title: "尚無計畫",
          message: "從目的地探索選擇候選停車點後，就能儲存成計畫。",
          symbol: "folder.badge.plus"
        )
      } else {
        List {
          ForEach(plans) { plan in
            NavigationLink {
              PlanDetailView(plan: plan)
            } label: {
              PlanCard(plan: plan)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions {
              Button("刪除", role: .destructive) { Task { await delete(plan) } }
            }
          }
        }
        .listStyle(.plain)
        .refreshable { await load() }
      }
    }
    .navigationTitle("計畫")
    .task { await load() }
    .onAppear { Task { await load() } }
    .alert("無法讀取計畫", isPresented: errorBinding) {
      Button("好") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "未知錯誤")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      plans = ParkingPlanSorter.sorted(try await environment.plans.plans())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete(_ plan: ParkingPlan) async {
    do {
      try await environment.plans.delete(id: plan.id)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

