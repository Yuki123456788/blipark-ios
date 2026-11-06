import SwiftUI

struct ParkingLocationEditorView: View {
  @Environment(\.dismiss) private var dismiss

  private let id: UUID
  private let onSave: (ParkingLocation) -> Void

  @State private var name: String
  @State private var address: String
  @State private var type: ParkingType
  @State private var coordinate: GeoCoordinate
  @State private var vehicles: Set<VehicleType>
  @State private var totalSpaceCount: String
  @State private var charge: ParkingCharge
  @State private var pricingSummary: String
  @State private var notes: String
  @State private var showsMap = false
  @State private var errorMessage: String?

  init(
    location: ParkingLocation? = nil,
    center: GeoCoordinate,
    onSave: @escaping (ParkingLocation) -> Void
  ) {
    id = location?.id ?? UUID()
    self.onSave = onSave
    _name = State(initialValue: location?.name ?? "")
    _address = State(initialValue: location?.address ?? "")
    _type = State(initialValue: location?.type ?? .parkingLot)
    _coordinate = State(initialValue: location?.coordinate ?? center)
    _vehicles = State(initialValue: location?.supportedVehicleTypes ?? [.car])
    _totalSpaceCount = State(initialValue: location?.totalSpaceCount.map(String.init) ?? "")
    _charge = State(initialValue: location?.charge ?? .unknown)
    _pricingSummary = State(initialValue: location?.pricingSummary ?? "")
    _notes = State(initialValue: location?.notes ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("基本資料") {
          TextField("名稱", text: $name)
          TextField("地址（選填）", text: $address, axis: .vertical)
          Picker("類型", selection: $type) {
            ForEach(ParkingType.allCases) { Text($0.title).tag($0) }
          }
          Button("在地圖搜尋或選取", systemImage: "map") { showsMap = true }
          Text(String(format: "座標 %.6f, %.6f", coordinate.latitude, coordinate.longitude))
            .font(.caption).foregroundStyle(.secondary)
        }

        Section("支援車種") {
          ForEach(VehicleType.allCases) { vehicle in
            Toggle(vehicle.title, isOn: vehicleBinding(vehicle))
          }
        }

        Section("停車資訊") {
          TextField("總格位數（未知請留白）", text: $totalSpaceCount)
            .keyboardType(.numberPad)
          Picker("收費", selection: $charge) {
            ForEach(ParkingCharge.allCases) { Text($0.title).tag($0) }
          }
          TextField("費率摘要（選填）", text: $pricingSummary, axis: .vertical)
          TextField("備註（選填）", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle(name.isEmpty ? "新增停車點" : name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("加入") { save() } }
      }
      .sheet(isPresented: $showsMap) {
        MapLocationPicker(
          title: "選擇停車位置",
          name: name,
          address: address.nilIfBlank,
          coordinate: coordinate
        ) { selectedName, selectedAddress, selectedCoordinate in
          if !selectedName.isEmpty { name = selectedName }
          if let selectedAddress { address = selectedAddress }
          coordinate = selectedCoordinate
        }
      }
      .alert("資料有誤", isPresented: errorBinding) {
        Button("好") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "未知錯誤")
      }
    }
  }

  private func vehicleBinding(_ vehicle: VehicleType) -> Binding<Bool> {
    Binding(
      get: { vehicles.contains(vehicle) },
      set: { enabled in
        if enabled { vehicles.insert(vehicle) } else { vehicles.remove(vehicle) }
      }
    )
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "請輸入停車點名稱。"
      return
    }
    guard coordinate.isValid else {
      errorMessage = "座標超出合法範圍。"
      return
    }
    guard !vehicles.isEmpty else {
      errorMessage = "請至少選擇一種車種。"
      return
    }
    let count: Int?
    if totalSpaceCount.nilIfBlank == nil {
      count = nil
    } else if let value = Int(totalSpaceCount), value >= 0 {
      count = value
    } else {
      errorMessage = "總格位數必須是 0 以上的整數，未知時請留白。"
      return
    }
    onSave(
      ParkingLocation(
        id: id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        address: address.nilIfBlank,
        type: type,
        coordinate: coordinate,
        supportedVehicleTypes: vehicles,
        totalSpaceCount: count,
        charge: charge,
        pricingSummary: pricingSummary.nilIfBlank,
        notes: notes.nilIfBlank,
        sourceReference: "local-test-dataset"
      )
    )
    dismiss()
  }
}

