import SwiftUI

struct DepartureConfirmationView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var pipRuntime: ParkingGuidancePiPRuntime

  let plan: ParkingPlan
  let onStarted: (ParkingGuidanceSession) -> Void

  @State private var usesExternalMap = true
  @State private var externalMapProvider: ExternalMapProvider = .appleMaps
  @State private var isStarting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          tripSummary
          modeSelection
          if usesExternalMap { mapProviderSelection }
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("準備出發")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("關閉") { dismiss() }
            .disabled(isStarting)
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          if isStarting, usesExternalMap {
            Text(pipRuntime.statusMessage)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          Button {
            Task { await startTrip() }
          } label: {
            if isStarting {
              ProgressView().frame(maxWidth: .infinity)
            } else {
              Label(startButtonTitle, systemImage: "play.fill")
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(isStarting || plan.candidates.isEmpty)
        }
        .padding()
        .background(.regularMaterial)
      }
      .alert("無法開始行程", isPresented: errorBinding) {
        Button("好") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "未知錯誤")
      }
    }
    .presentationDetents([.large])
  }

  private var tripSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(plan.destination.name, systemImage: "mappin.circle.fill")
        .font(.title3.bold())
        .foregroundStyle(BliparkStyle.brand)
      HStack(spacing: 18) {
        Label(plan.vehicleType.title, systemImage: plan.vehicleType.symbolName)
        Label("\(plan.candidates.count) 個候選", systemImage: "parkingsign")
      }
      .font(.subheadline)
      Text(plan.strategy.conciseSummary)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .bliparkCard()
  }

  private var modeSelection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("這次要怎麼使用？").font(.headline)
      selectionCard(
        title: "搭配地圖導航",
        message: "先啟動 Blipark PiP 停車引導，再由外部地圖前往目的地。",
        symbol: "map",
        isSelected: usesExternalMap
      ) {
        usesExternalMap = true
      }
      selectionCard(
        title: "只使用 Blipark",
        message: "留在 App 內查看目的地、停車候選並依序切換。",
        symbol: "iphone",
        isSelected: !usesExternalMap
      ) {
        usesExternalMap = false
      }
    }
  }

  private var mapProviderSelection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("選擇地圖 App").font(.headline)
      Picker("地圖 App", selection: $externalMapProvider) {
        ForEach(ExternalMapProvider.allCases, id: \.self) { provider in
          Label(provider.title, systemImage: provider.symbolName).tag(provider)
        }
      }
      .pickerStyle(.segmented)
    }
    .padding(16)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
  }

  private func selectionCard(
    title: String,
    message: String,
    symbol: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? BliparkStyle.brand : .secondary)
        Image(systemName: symbol)
          .frame(width: 24)
          .foregroundStyle(.primary)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.headline).foregroundStyle(.primary)
          Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(16)
      .background(.background, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(isSelected ? BliparkStyle.brand : .clear, lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
  }

  private var startButtonTitle: String {
    usesExternalMap ? "開始並開啟 \(externalMapProvider.title)" : "開始 Blipark 引導"
  }

  @MainActor
  private func startTrip() async {
    isStarting = true
    defer { isStarting = false }

    let mode: GuidanceMode = usesExternalMap
      ? .externalMaps(provider: externalMapProvider)
      : .bliparkOnly
    var session = GuidanceSessionLaunch.makeSession(from: plan, mode: mode)
    if usesExternalMap { session.status = .preparing }
    var didSaveSession = false

    do {
      let externalURL = usesExternalMap
        ? GuidanceSessionLaunch.externalMapURL(
          provider: externalMapProvider,
          destination: plan.destination
        )
        : nil
      if usesExternalMap, externalURL == nil {
        throw GuidanceLaunchError.invalidExternalMapURL
      }

      try await environment.guidanceSessions.save(session)
      didSaveSession = true

      if usesExternalMap {
        async let settings = environment.developerSettings.settings()
        async let preferences = environment.preferences.preferences()
        try await pipRuntime.start(
          session: session,
          settings: settings,
          triggerDistanceMeters: preferences.guidanceTriggerDistanceMeters
        )
        session.status = .active
        session.updatedAt = .now
        try await environment.guidanceSessions.save(session)
      }

      var usedPlan = plan
      usedPlan.lastUsedAt = session.startedAt
      try await environment.plans.save(usedPlan)

      dismiss()
      await Task.yield()
      onStarted(session)

      if let url = externalURL {
        openURL(url)
      }
    } catch {
      pipRuntime.stop()
      if didSaveSession {
        try? await environment.guidanceSessions.clearActiveSession()
      }
      errorMessage = error.localizedDescription
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }
}

private enum GuidanceLaunchError: LocalizedError {
  case invalidExternalMapURL

  var errorDescription: String? {
    "無法建立外部地圖導航連結。"
  }
}
