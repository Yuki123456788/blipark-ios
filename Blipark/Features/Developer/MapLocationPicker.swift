import MapKit
import SwiftUI

struct MapLocationPicker: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var searchModel = PlaceSearchModel()
  @State private var query = ""
  @State private var selection: GeoCoordinate
  @State private var selectedName: String
  @State private var selectedAddress: String?
  @State private var camera: MapCameraPosition
  @State private var selectionError: String?

  let title: String
  let coverageCenter: GeoCoordinate?
  let onSelect: (String, String?, GeoCoordinate) -> Void

  init(
    title: String,
    name: String,
    address: String?,
    coordinate: GeoCoordinate,
    coverageCenter: GeoCoordinate? = nil,
    onSelect: @escaping (String, String?, GeoCoordinate) -> Void
  ) {
    self.title = title
    self.coverageCenter = coverageCenter
    _selection = State(initialValue: coordinate)
    _selectedName = State(initialValue: name)
    _selectedAddress = State(initialValue: address)
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: coordinate.clLocationCoordinate,
          latitudinalMeters: coverageCenter == nil ? 2_000 : 5_000,
          longitudinalMeters: coverageCenter == nil ? 2_000 : 5_000
        )
      )
    )
    self.onSelect = onSelect
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchPanel
        MapReader { proxy in
          Map(position: $camera) {
            if let coverageCenter {
              MapPolyline(coordinates: ParkingSelectionCoverage.boundaryCoordinates(centeredAt: coverageCenter))
                .stroke(
                  BliparkStyle.brand,
                  style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
            }
            Marker(selectedName.isEmpty ? "選取位置" : selectedName, coordinate: selection.clLocationCoordinate)
              .tint(BliparkStyle.brand)
          }
          .mapControls {
            MapCompass()
            MapScaleView()
          }
          .onTapGesture { point in
            guard let coordinate = proxy.convert(point, from: .local) else { return }
            let value = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard isInsideCoverage(value) else {
              selectionError = "停車點必須位於目的地周圍 4 × 4 公里的方框內。"
              return
            }
            selection = value
            selectedAddress = nil
            selectionError = nil
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Text(selectedName.isEmpty ? "自訂位置" : selectedName)
            .font(.headline)
          Text(selectedAddress ?? coordinateText)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let selectionError {
            Text(selectionError).font(.caption).foregroundStyle(.red)
          } else if coverageCenter != nil {
            Text("虛線範圍為目的地周圍 4 × 4 公里")
              .font(.caption).foregroundStyle(.secondary)
          }
          Button("使用這個位置") {
            onSelect(selectedName, selectedAddress, selection)
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .disabled(!isInsideCoverage(selection))
        }
        .padding()
        .background(.regularMaterial)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") {
            UIApplication.shared.sendAction(
              #selector(UIResponder.resignFirstResponder),
              to: nil,
              from: nil,
              for: nil
            )
          }
        }
      }
    }
  }

  private var searchPanel: some View {
    VStack(spacing: 8) {
      HStack {
        TextField("搜尋地點或地址", text: $query)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .onSubmit { Task { await searchModel.search(query, near: selection) } }
        if searchModel.isSearching { ProgressView() }
      }
      if let error = searchModel.errorMessage {
        Text(error).font(.caption).foregroundStyle(.red)
      }
      if !searchModel.results.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(searchModel.results) { result in
              Button {
                guard isInsideCoverage(result.coordinate) else {
                  selectionError = "這個地點超出目的地周圍 4 × 4 公里的方框。"
                  return
                }
                selectedName = result.name
                selectedAddress = result.address
                selection = result.coordinate
                selectionError = nil
                camera = .region(
                  MKCoordinateRegion(
                    center: result.coordinate.clLocationCoordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                  )
                )
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(result.name).font(.subheadline.weight(.medium)).lineLimit(1)
                  Text(result.address ?? "地址未提供").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(10)
                .frame(width: 220, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
  }

  private var coordinateText: String {
    String(format: "%.6f, %.6f", selection.latitude, selection.longitude)
  }

  private func isInsideCoverage(_ coordinate: GeoCoordinate) -> Bool {
    guard let coverageCenter else { return true }
    return ParkingSelectionCoverage.contains(coordinate, centeredAt: coverageCenter)
  }
}

