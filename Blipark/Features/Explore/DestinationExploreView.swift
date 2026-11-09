import MapKit
import SwiftUI

struct DestinationExploreView: View {
  @Environment(\.appEnvironment) private var environment
  @StateObject private var model: DestinationExploreModel
  @State private var camera: MapCameraPosition
  @State private var detailItem: ExploredParkingLocation?
  @State private var showsPlanComposer = false
  @State private var savedPlan: ParkingPlan?
  @State private var planToStart: ParkingPlan?
  @State private var presentedSession: ParkingGuidanceSession?

  init(destination: Destination, parkingProvider: any ParkingDataProviding) {
    _model = StateObject(
      wrappedValue: DestinationExploreModel(destination: destination, provider: parkingProvider)
    )
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: destination.coordinate.clLocationCoordinate,
          latitudinalMeters: 2_400,
          longitudinalMeters: 2_400
        )
      )
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      parkingMap
        .frame(height: 300)
      content
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(model.destination.name)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await model.load(preferencesRepository: environment.preferences)
      fitExplorationArea()
    }
    .onChange(of: model.explorationAreaWidthMeters) { _, _ in fitExplorationArea() }
    .sheet(item: $detailItem) { ParkingLocationDetailView(item: $0) }
    .sheet(isPresented: $showsPlanComposer) {
      PlanComposerView(
        destination: model.destination,
        knownLocations: model.locations.map(\.location),
        initiallySelectedLocationIDs: model.selectedLocationIDs,
        initialStrategy: model.strategy,
        showsStrategyEditor: false,
        parkingProvider: environment.parkingData,
        preferencesRepository: environment.preferences,
        planRepository: environment.plans
      ) { plan in
        savedPlan = plan
      }
    }
    .sheet(item: $planToStart) { plan in
      DepartureConfirmationView(plan: plan) { session in
        if case .bliparkOnly = session.mode {
          presentedSession = session
        }
      }
    }
    .fullScreenCover(item: $presentedSession) { session in
      GuidanceSessionView(session: session) {
        presentedSession = nil
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !model.locations.isEmpty {
        Button {
          showsPlanComposer = true
        } label: {
          Label(
            model.selectedLocationIDs.isEmpty
              ? "選擇候選停車點"
              : "確認策略並儲存計畫（\(model.selectedLocationIDs.count)）",
            systemImage: "bookmark.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.selectedLocationIDs.isEmpty)
        .padding()
        .background(.regularMaterial)
      }
    }
    .alert("無法載入探索資料", isPresented: errorBinding) {
      Button("重試") {
        Task { await model.load(preferencesRepository: environment.preferences) }
      }
      Button("取消", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "未知錯誤")
    }
    .alert("計畫已儲存", isPresented: savedBinding) {
      Button("開始行程") {
        let plan = savedPlan
        savedPlan = nil
        Task { @MainActor in
          await Task.yield()
          planToStart = plan
        }
      }
      Button("稍後", role: .cancel) { savedPlan = nil }
    } message: {
      Text("「\(savedPlan?.name ?? "停車計畫")」已加入計畫列表與首頁。")
    }
  }

  private var parkingMap: some View {
    Map(position: $camera, selection: $model.focusedID) {
      let boundary = SquareMapCoverage.boundaryCoordinates(
        centeredAt: model.destination.coordinate,
        widthMeters: model.explorationAreaWidthMeters
      )
      MapPolygon(coordinates: boundary)
        .foregroundStyle(BliparkStyle.brand.opacity(0.06))
      MapPolyline(coordinates: boundary)
        .stroke(
          BliparkStyle.brand.opacity(0.8),
          style: StrokeStyle(lineWidth: 2, dash: [7, 5])
        )

      Marker(
        model.destination.name,
        systemImage: "flag.fill",
        coordinate: model.destination.coordinate.clLocationCoordinate
      )
      .tint(.red)

      ForEach(model.visibleLocations) { item in
        if let coordinate = item.location.coordinate,
          let order = model.selectionOrder(for: item.id)
        {
          Annotation(item.location.name, coordinate: coordinate.clLocationCoordinate) {
            Text("\(order)")
              .font(.caption.bold())
              .foregroundStyle(.white)
              .frame(width: 30, height: 30)
              .background(BliparkStyle.brand, in: Circle())
              .overlay { Circle().stroke(.white, lineWidth: 2) }
          }
          .tag(item.id)
        } else if let coordinate = item.location.coordinate {
          Marker(
            item.location.name,
            systemImage: item.location.type.symbolName,
            coordinate: coordinate.clLocationCoordinate
          )
          .tint(.gray)
          .tag(item.id)
        }
      }
    }
    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .overlay(alignment: .topLeading) {
      Text(explorationAreaTitle)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading && model.locations.isEmpty {
      Spacer()
      ProgressView("正在取得停車資訊…")
      Spacer()
    } else if model.locations.isEmpty {
      BliparkEmptyState(
        title: "沒有停車資料",
        message: "這個目的地目前沒有可供比較的停車資訊。",
        symbol: "parkingsign.circle"
      )
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 14) {
            if let focused = model.item(id: model.focusedID) {
              focusedPreview(focused)
                .id("focused-preview")
            }
            strategySection
            selectedOrderSection
            parkingListSection
          }
          .padding()
        }
        .onChange(of: model.focusedID) { _, id in
          guard id != nil else { return }
          withAnimation { proxy.scrollTo("focused-preview", anchor: .top) }
        }
      }
    }
  }

  private func focusedPreview(_ item: ExploredParkingLocation) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ParkingStreetViewPlaceholder(locationName: item.location.name, height: 130)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.location.name).font(.headline)
          Text("\(item.location.type.title)・\(item.location.charge.title)・\(distanceText(item))")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        VStack(spacing: 8) {
          Button(model.selectionOrder(for: item.id) == nil ? "加入候選" : "取消候選") {
            model.toggleSelection(item.id)
          }
          .buttonStyle(.borderedProminent)
          Button("詳細資訊") { detailItem = item }
            .buttonStyle(.bordered)
        }
      }
    }
    .padding(12)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
  }

  private var strategySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("停車偏好與查看範圍", systemImage: "slider.horizontal.3")
        .font(.headline)

      Picker("車種", selection: $model.strategy.vehicleType) {
        ForEach(VehicleType.allCases) { Text($0.title).tag($0) }
      }

      HStack {
        Text("停車類型")
        Spacer()
        ForEach(ParkingType.allCases) { type in
          Toggle(type.title, isOn: parkingTypeBinding(type))
            .toggleStyle(.button)
        }
      }

      Picker("收費偏好", selection: $model.strategy.pricingPreference) {
        ForEach(PricingPreference.allCases) { Text($0.title).tag($0) }
      }

      Picker("查看範圍", selection: $model.strategy.informationRangeWidthMeters) {
        Text("1 × 1 km").tag(Optional(1_000.0))
        Text("2 × 2 km").tag(Optional(2_000.0))
        Text("3 × 3 km").tag(Optional(3_000.0))
        Text("4 × 4 km").tag(Optional(4_000.0))
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Text("這裡不會自動推薦或重排停車點；你勾選的先後與上方調整結果就是本次候選順序。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
  }

  @ViewBuilder
  private var selectedOrderSection: some View {
    if !model.selectedLocations.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("已選候選與嘗試順序").font(.headline)
        ForEach(Array(model.selectedLocations.enumerated()), id: \.element.id) { index, item in
          HStack(spacing: 10) {
            Text("\(index + 1)")
              .font(.caption.bold()).foregroundStyle(.white)
              .frame(width: 26, height: 26)
              .background(BliparkStyle.brand, in: Circle())
            Text(item.location.name).lineLimit(1)
            Spacer()
            Button { model.moveSelected(id: item.id, offset: -1) } label: {
              Image(systemName: "arrow.up")
            }
            .disabled(index == 0)
            Button { model.moveSelected(id: item.id, offset: 1) } label: {
              Image(systemName: "arrow.down")
            }
            .disabled(index == model.selectedLocations.count - 1)
            Button(role: .destructive) { model.toggleSelection(item.id) } label: {
              Image(systemName: "xmark.circle")
            }
          }
        }
      }
      .padding(14)
      .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private var parkingListSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("附近停車資訊").font(.headline)
        Spacer()
        Text("\(model.visibleLocations.count) 個")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      if model.visibleLocations.isEmpty {
        ContentUnavailableView(
          "這個範圍沒有符合偏好的停車點",
          systemImage: "line.3.horizontal.decrease.circle",
          description: Text("可放大查看範圍或調整車種與停車類型。")
        )
      } else {
        ForEach(model.visibleLocations) { item in
          Button {
            model.toggleSelection(item.id)
          } label: {
            ParkingLocationCard(
              item: item,
              selectionOrder: model.selectionOrder(for: item.id)
            )
          }
          .buttonStyle(.plain)
          .id(item.id)
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

  private var explorationAreaTitle: String {
    let kilometers = model.explorationAreaWidthMeters / 1_000
    return String(format: "%.0f × %.0f km 查看範圍", kilometers, kilometers)
  }

  private func distanceText(_ item: ExploredParkingLocation) -> String {
    item.straightLineDistanceMeters >= 1_000
      ? String(format: "直線約 %.1f km", item.straightLineDistanceMeters / 1_000)
      : "直線約 \(Int(item.straightLineDistanceMeters.rounded())) m"
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
  }

  private var savedBinding: Binding<Bool> {
    Binding(get: { savedPlan != nil }, set: { if !$0 { savedPlan = nil } })
  }

  private func fitExplorationArea() {
    let width = max(model.explorationAreaWidthMeters * 1.2, 1_200)
    camera = .region(
      MKCoordinateRegion(
        center: model.destination.coordinate.clLocationCoordinate,
        latitudinalMeters: width,
        longitudinalMeters: width
      )
    )
  }
}
