import SwiftUI

struct PlanComposerView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: PlanComposerModel
  private let onSaved: (ParkingPlan) -> Void

  init(
    destination: Destination,
    knownLocations: [ParkingLocation],
    initiallySelectedLocationIDs: [UUID] = [],
    existingPlan: ParkingPlan? = nil,
    parkingProvider: any ParkingDataProviding,
    preferencesRepository: any PreferencesRepository,
    planRepository: any PlanRepository,
    onSaved: @escaping (ParkingPlan) -> Void
  ) {
    _model = StateObject(
      wrappedValue: PlanComposerModel(
        destination: destination,
        knownLocations: knownLocations,
        initiallySelectedLocationIDs: initiallySelectedLocationIDs,
        existingPlan: existingPlan,
        parkingProvider: parkingProvider,
        preferencesRepository: preferencesRepository,
        planRepository: planRepository
      )
    )
    self.onSaved = onSaved
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("計畫") {
          TextField("計畫名稱", text: $model.planName)
          Toggle("設定出發時間", isOn: $model.hasScheduledDeparture)
          if model.hasScheduledDeparture {
            DatePicker(
              "預計出發",
              selection: $model.scheduledDepartureAt,
              displayedComponents: [.date, .hourAndMinute]
            )
          }
        }

        strategySection
        selectedCandidatesSection
        availableCandidatesSection
      }
      .navigationTitle("停車策略與候選")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("儲存") {
            Task {
              if let plan = await model.save() {
                onSaved(plan)
                dismiss()
              }
            }
          }
          .disabled(model.isSaving || model.isLoading)
        }
      }
      .task { await model.load() }
      .overlay { if model.isLoading { ProgressView().controlSize(.large) } }
      .alert("無法完成計畫", isPresented: errorBinding) {
        Button("好") { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "未知錯誤")
      }
    }
  }

  private var strategySection: some View {
    Section {
      Picker("車種", selection: $model.strategy.vehicleType) {
        ForEach(VehicleType.allCases) { Text($0.title).tag($0) }
      }
      ForEach(ParkingType.allCases) { type in
        Toggle(type.title, isOn: parkingTypeBinding(type))
      }
      Picker("收費偏好", selection: $model.strategy.pricingPreference) {
        ForEach(PricingPreference.allCases) { Text($0.title).tag($0) }
      }
      Picker("距離範圍", selection: $model.strategy.maximumStraightLineDistanceMeters) {
        Text("直線 300 m 內").tag(Optional(300.0))
        Text("直線 500 m 內").tag(Optional(500.0))
        Text("直線 800 m 內").tag(Optional(800.0))
        Text("直線 1,200 m 內").tag(Optional(1_200.0))
        Text("不限").tag(Optional<Double>.none)
      }
    } header: {
      Text("本次停車策略")
    } footer: {
      Text("目前保留偏好設定，但不會自動套用推薦或改變下方停車點。")
    }
  }

  private var selectedCandidatesSection: some View {
    Section {
      if model.selectedLocations.isEmpty {
        Text("尚未選擇候選停車點").foregroundStyle(.secondary)
      } else {
        ForEach(model.selectedLocations) { location in
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(BliparkStyle.brand)
            VStack(alignment: .leading) {
              Text(location.name)
              Text(distanceText(location)).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .onDelete(perform: model.remove)
      }
    } header: {
      Text("已選停車點")
    } footer: {
      Text("這裡不代表推薦排名或引導順序。")
    }
  }

  private var availableCandidatesSection: some View {
    Section("其他停車點") {
      if model.unselectedLocations.isEmpty {
        Text("沒有其他可加入的停車點").foregroundStyle(.secondary)
      } else {
        ForEach(model.unselectedLocations) { location in
          Button {
            model.add(location)
          } label: {
            HStack {
              Image(systemName: "plus.circle.fill")
              VStack(alignment: .leading) {
                Text(location.name).foregroundStyle(.primary)
                Text(distanceText(location)).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
  }

  private func parkingTypeBinding(_ type: ParkingType) -> Binding<Bool> {
    Binding(
      get: { model.strategy.preferredParkingTypes.contains(type) },
      set: { enabled in
        if enabled {
          model.strategy.preferredParkingTypes.insert(type)
        } else if model.strategy.preferredParkingTypes.count > 1 {
          model.strategy.preferredParkingTypes.remove(type)
        }
      }
    )
  }

  private func distanceText(_ location: ParkingLocation) -> String {
    let distance = model.distance(for: location)
    return distance >= 1_000
      ? String(format: "直線約 %.1f km", distance / 1_000)
      : "直線約 \(Int(distance.rounded())) m"
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
  }
}

