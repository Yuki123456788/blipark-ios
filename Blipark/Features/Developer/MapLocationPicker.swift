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

  let title: String
  let onSelect: (String, String?, GeoCoordinate) -> Void

  init(
    title: String,
    name: String,
    address: String?,
    coordinate: GeoCoordinate,
    onSelect: @escaping (String, String?, GeoCoordinate) -> Void
  ) {
    self.title = title
    _selection = State(initialValue: coordinate)
    _selectedName = State(initialValue: name)
    _selectedAddress = State(initialValue: address)
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: coordinate.clLocationCoordinate,
          latitudinalMeters: 2_000,
          longitudinalMeters: 2_000
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
            Marker(selectedName.isEmpty ? "選取位置" : selectedName, coordinate: selection.clLocationCoordinate)
              .tint(BliparkStyle.brand)
          }
          .mapControls {
            MapCompass()
            MapScaleView()
          }
          .onTapGesture { point in
            guard let coordinate = proxy.convert(point, from: .local) else { return }
            selection = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            selectedAddress = nil
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
          Button("使用這個位置") {
            onSelect(selectedName, selectedAddress, selection)
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity, alignment: .trailing)
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
                selectedName = result.name
                selectedAddress = result.address
                selection = result.coordinate
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
}

