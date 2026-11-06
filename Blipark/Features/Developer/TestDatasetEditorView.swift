import SwiftUI

struct TestDatasetEditorView: View {
  @Environment(\.dismiss) private var dismiss

  private let repository: any TestDatasetRepository
  private let datasetID: UUID
  private let destinationID: UUID
  private let createdAt: Date
  private let onSaved: () -> Void

  @State private var destinationName: String
  @State private var destinationAddress: String
  @State private var destinationCoordinate: GeoCoordinate
  @State private var notes: String
  @State private var isEnabled: Bool
  @State private var parkingLocations: [ParkingLocation]
  @State private var showsDestinationMap = false
  @State private var showsParkingEditor = false
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
    _destinationName = State(initialValue: dataset?.destination.name ?? "")
    _destinationAddress = State(initialValue: dataset?.destination.address ?? "")
    _destinationCoordinate = State(
      initialValue: dataset?.destination.coordinate
        ?? GeoCoordinate(latitude: 22.9910, longitude: 120.2040)
    )
    _notes = State(initialValue: dataset?.notes ?? "")
    _isEnabled = State(initialValue: dataset?.isEnabled ?? true)
    _parkingLocations = State(initialValue: dataset?.parkingLocations ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("目的地") {
          TextField("名稱", text: $destinationName)
          TextField("地址（選填）", text: $destinationAddress, axis: .vertical)
          coordinateFields
          Button("在地圖搜尋或選取", systemImage: "map") { showsDestinationMap = true }
        }

        Section {
          if parkingLocations.isEmpty {
            Text("尚未加入停車點")
              .foregroundStyle(.secondary)
          } else {
            ForEach(parkingLocations) { location in
              Button { editingParkingLocation = location } label: {
                HStack {
                  Image(systemName: location.type.symbolName)
                    .foregroundStyle(BliparkStyle.brand)
                  VStack(alignment: .leading) {
                    Text(location.name).foregroundStyle(.primary)
                    Text(location.type.title).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
              }
              .buttonStyle(.plain)
            }
            .onDelete { parkingLocations.remove(atOffsets: $0) }
            .onMove { parkingLocations.move(fromOffsets: $0, toOffset: $1) }
          }
          Button("新增停車點", systemImage: "plus") { showsParkingEditor = true }
        } header: {
          HStack {
            Text("附近停車點")
            Spacer()
            if parkingLocations.count > 1 { EditButton().textCase(nil) }
          }
        } footer: {
          Text("這些資料模擬未來 API 的回應，不會自動建立使用者計畫。")
        }

        Section("情境") {
          Toggle("啟用於正式搜尋", isOn: $isEnabled)
          TextField("備註（選填）", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle(destinationName.isEmpty ? "新增測試情境" : destinationName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("儲存") { save() }
            .disabled(isSaving)
        }
      }
      .sheet(isPresented: $showsDestinationMap) {
        MapLocationPicker(
          title: "選擇目的地",
          name: destinationName,
          address: destinationAddress.nilIfBlank,
          coordinate: destinationCoordinate
        ) { name, address, coordinate in
          if !name.isEmpty { destinationName = name }
          if let address { destinationAddress = address }
          destinationCoordinate = coordinate
        }
      }
      .sheet(isPresented: $showsParkingEditor) {
        ParkingLocationEditorView(center: destinationCoordinate) { parkingLocations.append($0) }
      }
      .sheet(item: $editingParkingLocation) { location in
        ParkingLocationEditorView(location: location, center: destinationCoordinate) { updated in
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

  private var coordinateFields: some View {
    Group {
      LabeledContent("緯度") {
        TextField("緯度", value: latitudeBinding, format: .number.precision(.fractionLength(0...6)))
          .multilineTextAlignment(.trailing)
          .keyboardType(.numbersAndPunctuation)
      }
      LabeledContent("經度") {
        TextField("經度", value: longitudeBinding, format: .number.precision(.fractionLength(0...6)))
          .multilineTextAlignment(.trailing)
          .keyboardType(.numbersAndPunctuation)
      }
    }
  }

  private var latitudeBinding: Binding<Double> {
    Binding(get: { destinationCoordinate.latitude }) {
      destinationCoordinate = GeoCoordinate(latitude: $0, longitude: destinationCoordinate.longitude)
    }
  }

  private var longitudeBinding: Binding<Double> {
    Binding(get: { destinationCoordinate.longitude }) {
      destinationCoordinate = GeoCoordinate(latitude: destinationCoordinate.latitude, longitude: $0)
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    let destination = Destination(
      id: destinationID,
      name: destinationName.trimmingCharacters(in: .whitespacesAndNewlines),
      address: destinationAddress.nilIfBlank,
      coordinate: destinationCoordinate,
      sourceReference: "local-test-dataset"
    )
    let dataset = TestDataset(
      id: datasetID,
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
}

extension String {
  var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}

