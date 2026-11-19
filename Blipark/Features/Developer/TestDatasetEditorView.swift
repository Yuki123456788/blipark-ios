import MapKit
import SwiftUI

struct TestDatasetEditorView: View {
  @Environment(\.dismiss) private var dismiss

  private let repository: any TestDatasetRepository
  private let datasetID: UUID
  private let destinationID: UUID
  private let createdAt: Date
  private let onSaved: () -> Void

  @State private var scenarioName: String
  @State private var destination: Destination?
  @State private var notes: String
  @State private var isEnabled: Bool
  @State private var parkingLocations: [ParkingLocation]
  @State private var destinationMapLink = ""
  @State private var parkingMapLink = ""
  @State private var showsDestinationPicker = false
  @State private var pendingParkingDestination: Destination?
  @State private var editingParkingLocation: ParkingLocation?
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    dataset: TestDataset? = nil,
    repository: any TestDatasetRepository,
    onSaved: @escaping () -> Void
  ) {
    self.repository = repository
    datasetID = dataset?.id ?? UUID()
    destinationID = dataset?.destination.id ?? UUID()
    createdAt = dataset?.createdAt ?? .now
    self.onSaved = onSaved
    _scenarioName = State(initialValue: dataset?.displayName ?? "")
    _destination = State(initialValue: dataset?.destination)
    _notes = State(initialValue: dataset?.notes ?? "")
    _isEnabled = State(initialValue: dataset?.isEnabled ?? true)
    _parkingLocations = State(initialValue: dataset?.parkingLocations ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        scenarioSection
        destinationSection
        parkingSection
      }
      .navigationTitle(scenarioName.isEmpty ? "新增測試情境" : scenarioName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("儲存") { save() }
            .disabled(isSaving)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { dismissKeyboard() }
        }
      }
      .sheet(isPresented: $showsDestinationPicker) {
        MapLocationPicker(
          title: "選擇最終目的地",
          destination: destination,
          defaultCoordinate: destination?.coordinate ?? .tainanCenter
        ) { selected in
          setDestination(selected)
        }
      }
      .sheet(item: $pendingParkingDestination) { selected in
        ParkingLocationEditorView(
          selectedDestination: selected,
          center: destination?.coordinate ?? .tainanCenter
        ) { location in
          parkingLocations.append(location)
          parkingMapLink = ""
        }
      }
      .sheet(item: $editingParkingLocation) { location in
        ParkingLocationEditorView(
          location: location,
          center: destination?.coordinate ?? .tainanCenter
        ) { updated in
          guard let index = parkingLocations.firstIndex(where: { $0.id == updated.id }) else { return }
          parkingLocations[index] = updated
        }
      }
      .alert("無法儲存", isPresented: errorBinding) {
        Button("好") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "未知錯誤")
      }
    }
  }

  private var scenarioSection: some View {
    Section {
      TextField("例如：週末去美術館測試", text: $scenarioName)
      Toggle("啟用於 App 搜尋", isOn: $isEnabled)
      TextField("備註（選填）", text: $notes, axis: .vertical)
    } header: {
      Text("測試情境")
    } footer: {
      Text("情境名稱只用來辨識這筆測資，不會取代最終目的地的地標名稱。")
    }
  }

  private var destinationSection: some View {
    Section {
      if let destination {
        Map(
          initialPosition: .region(
            MKCoordinateRegion(
              center: destination.coordinate.clLocationCoordinate,
              latitudinalMeters: 700,
              longitudinalMeters: 700
            )
          )
        ) {
          Marker(destination.name, coordinate: destination.coordinate.clLocationCoordinate)
            .tint(.red)
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        Label(destination.name, systemImage: "flag.checkered")
          .font(.headline)
        if let address = destination.address {
          Text(address).font(.subheadline).foregroundStyle(.secondary)
        }
        Button("重新搜尋或在地圖選取", systemImage: "map") {
          showsDestinationPicker = true
        }
      } else {
        ContentUnavailableView(
          "尚未選擇目的地",
          systemImage: "flag.checkered",
          description: Text("先搜尋地標、點擊地圖地標，或長按地圖任意位置。")
        )
        Button("搜尋或在地圖選取", systemImage: "map") {
          showsDestinationPicker = true
        }
      }

      MapLinkImportField(link: $destinationMapLink) { imported in
        setDestination(imported)
      }
    } header: {
      Text("最終目的地")
    } footer: {
      Text("Apple Maps／Google Maps 連結會直接帶入地標名稱與位置，不需要手動填地址或經緯度。")
    }
  }

  @ViewBuilder
  private var parkingSection: some View {
    Section {
      if let destination {
        DeveloperParkingMapPicker(
          destination: destination,
          parkingLocations: parkingLocations
        ) { pendingParkingDestination = $0 }
        .id(destination.coordinate)

        MapLinkImportField(
          link: $parkingMapLink,
          prompt: "貼上要加入的停車點連結"
        ) { imported in
          guard ParkingSelectionCoverage.contains(
            imported.coordinate,
            centeredAt: destination.coordinate
          ) else {
            errorMessage = "這個停車點超出導航 Snapshot 可用範圍。"
            return
          }
          pendingParkingDestination = imported
        }

        if parkingLocations.isEmpty {
          Text("尚未加入停車點")
            .foregroundStyle(.secondary)
        } else {
          ForEach(parkingLocations) { location in
            Button { editingParkingLocation = location } label: {
              HStack(spacing: 10) {
                Image(systemName: location.type.symbolName)
                  .foregroundStyle(BliparkStyle.brand)
                VStack(alignment: .leading, spacing: 3) {
                  Text(location.name).foregroundStyle(.primary)
                  Text("\(location.type.title)・\(location.charge.title)")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }
            }
            .buttonStyle(.plain)
          }
          .onDelete { parkingLocations.remove(atOffsets: $0) }
        }
      } else {
        Label("先選擇最終目的地，才能建立附近停車點。", systemImage: "1.circle")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("附近停車點")
    } footer: {
      Text("點地標會直接選取；只有地標以外的位置才使用長按放圖釘。選定後再確認停車類型、收費與適用車種。")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func setDestination(_ selected: Destination) {
    destination = Destination(
      id: destinationID,
      name: selected.name,
      address: selected.address,
      coordinate: selected.coordinate,
      externalPlaceID: selected.externalPlaceID,
      sourceReference: selected.sourceReference ?? "local-test-dataset"
    )
  }

  private func save() {
    guard let destination else {
      errorMessage = "請先選擇最終目的地。"
      return
    }
    guard scenarioName.nilIfBlank != nil else {
      errorMessage = "請輸入測試情境名稱。"
      return
    }
    let dataset = TestDataset(
      id: datasetID,
      name: scenarioName.nilIfBlank,
      destination: destination,
      parkingLocations: parkingLocations,
      notes: notes.nilIfBlank,
      isEnabled: isEnabled,
      createdAt: createdAt,
      updatedAt: .now
    )
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await repository.save(dataset)
        onSaved()
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

extension String {
  var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
