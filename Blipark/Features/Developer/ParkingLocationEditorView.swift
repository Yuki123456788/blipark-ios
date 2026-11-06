import SwiftUI

struct ParkingLocationEditorView: View {
  @Environment(\.dismiss) private var dismiss

  private let id: UUID
  private let center: GeoCoordinate
  private let coordinate: GeoCoordinate
  private let name: String
  private let address: String?
  private let onSave: (ParkingLocation) -> Void

  @State private var type: ParkingType
  @State private var vehicles: Set<VehicleType>
  @State private var totalSpaceCount: String
  @State private var charge: ParkingCharge
  @State private var pricingSummary: String
  @State private var notes: String
  @State private var errorMessage: String?

  init(
    location: ParkingLocation? = nil,
    selectedDestination: Destination? = nil,
    center: GeoCoordinate,
    onSave: @escaping (ParkingLocation) -> Void
  ) {
    let selectedCoordinate = location?.coordinate ?? selectedDestination?.coordinate ?? center
    id = location?.id ?? UUID()
    self.center = center
    coordinate = selectedCoordinate
    name = location?.name ?? selectedDestination?.name ?? "自訂停車點"
    address = location?.address ?? selectedDestination?.address
    self.onSave = onSave
    _type = State(initialValue: location?.type ?? .parkingLot)
    _vehicles = State(initialValue: location?.supportedVehicleTypes ?? [.car])
    _totalSpaceCount = State(initialValue: location?.totalSpaceCount.map(String.init) ?? "")
    _charge = State(initialValue: location?.charge ?? .unknown)
    _pricingSummary = State(initialValue: location?.pricingSummary ?? "")
    _notes = State(initialValue: location?.notes ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("選取位置") {
          Label(name, systemImage: "mappin.circle.fill")
            .font(.headline)
          if let address {
            Text(address).font(.subheadline).foregroundStyle(.secondary)
          }
        }

        Section("停車類型") {
          Picker("類型", selection: $type) {
            ForEach(ParkingType.allCases) { parkingType in
              Label(parkingType.title, systemImage: parkingType.symbolName).tag(parkingType)
            }
          }
          .pickerStyle(.segmented)
        }

        Section("適用車種") {
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
      .navigationTitle("設定停車資訊")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("確認") { save() } }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { dismissKeyboard() }
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
    guard ParkingSelectionCoverage.contains(coordinate, centeredAt: center) else {
      errorMessage = "停車點超出導航 Snapshot 可用範圍。"
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
        name: name,
        address: address,
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

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}
