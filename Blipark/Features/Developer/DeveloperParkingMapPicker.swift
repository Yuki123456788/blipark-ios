import CoreLocation
import MapKit
import SwiftUI

struct DeveloperParkingMapPicker: View {
  @StateObject private var searchModel = PlaceSearchModel()
  @State private var query = ""
  @State private var camera: MapCameraPosition
  @State private var selectedFeature: MapFeature?
  @State private var isResolving = false
  @State private var errorMessage: String?
  @State private var pressOrigin: CGPoint?
  @State private var longPressTask: Task<Void, Never>?
  @State private var resolutionTask: Task<Void, Never>?

  let destination: Destination
  let parkingLocations: [ParkingLocation]
  let onSelect: (Destination) -> Void

  init(
    destination: Destination,
    parkingLocations: [ParkingLocation],
    onSelect: @escaping (Destination) -> Void
  ) {
    self.destination = destination
    self.parkingLocations = parkingLocations
    self.onSelect = onSelect
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: destination.coordinate.clLocationCoordinate,
          latitudinalMeters: 4_800,
          longitudinalMeters: 4_800
        )
      )
    )
  }

  var body: some View {
    VStack(spacing: 10) {
      searchPanel
      MapReader { proxy in
        Map(
          position: $camera,
          interactionModes: [.pan, .zoom],
          selection: $selectedFeature
        ) {
          let boundary = ParkingSelectionCoverage.boundaryCoordinates(
            centeredAt: destination.coordinate
          )
          MapPolygon(coordinates: boundary)
            .foregroundStyle(BliparkStyle.brand.opacity(0.05))
          MapPolyline(coordinates: boundary)
            .stroke(
              BliparkStyle.brand.opacity(0.55),
              style: StrokeStyle(lineWidth: 2, dash: [7, 5])
            )

          Marker(
            destination.name,
            systemImage: "flag.checkered",
            coordinate: destination.coordinate.clLocationCoordinate
          )
          .tint(.red)

          ForEach(parkingLocations) { location in
            if let coordinate = location.coordinate {
              Marker(
                location.name,
                systemImage: location.type.symbolName,
                coordinate: coordinate.clLocationCoordinate
              )
              .tint(BliparkStyle.brand)
            }
          }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
        .mapControls {
          MapCompass()
          MapScaleView()
        }
        .simultaneousGesture(longPressGesture(proxy: proxy))
        .onChange(of: selectedFeature) { _, feature in
          guard let feature else { return }
          resolve(feature: feature)
        }
        .overlay(alignment: .topLeading) {
          Label("點地標・長按放圖釘", systemImage: "hand.tap.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
        }
        .overlay(alignment: .bottom) {
          if isResolving {
            HStack(spacing: 8) {
              ProgressView()
              Text("正在取得停車點資訊…").font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
          } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption.weight(.medium))
              .foregroundStyle(.orange)
              .padding(10)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
              .padding(10)
          }
        }
      }
      .frame(height: 340)
      .clipShape(RoundedRectangle(cornerRadius: 14))

      Text("虛線是導航 Snapshot 可用範圍，只用於建立測試資料。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .onDisappear {
      longPressTask?.cancel()
      resolutionTask?.cancel()
    }
  }

  private var searchPanel: some View {
    VStack(spacing: 8) {
      HStack {
        TextField("搜尋停車場、道路或地址", text: $query)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .onSubmit { Task { await searchModel.search(query, near: destination.coordinate) } }
        if searchModel.isSearching { ProgressView() }
      }
      if let searchError = searchModel.errorMessage {
        Text(searchError).font(.caption).foregroundStyle(.red)
      }
      if !searchModel.results.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(searchModel.results) { result in
              Button {
                select(
                  Destination(
                    name: result.name,
                    address: result.address,
                    coordinate: result.coordinate,
                    sourceReference: "mapkit-search"
                  )
                )
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(result.name).font(.subheadline.weight(.medium)).lineLimit(1)
                  if let address = result.address {
                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                  }
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
  }

  private func longPressGesture(proxy: MapProxy) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        if pressOrigin == nil {
          pressOrigin = value.startLocation
          longPressTask?.cancel()
          longPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, let pressOrigin,
              let coordinate = proxy.convert(pressOrigin, from: .local)
            else { return }
            resolve(coordinate: coordinate)
          }
        }
        guard let pressOrigin else { return }
        if hypot(value.location.x - pressOrigin.x, value.location.y - pressOrigin.y) > 12 {
          longPressTask?.cancel()
          longPressTask = nil
          self.pressOrigin = nil
        }
      }
      .onEnded { _ in
        longPressTask?.cancel()
        longPressTask = nil
        pressOrigin = nil
      }
  }

  private func resolve(feature: MapFeature) {
    resolutionTask?.cancel()
    isResolving = true
    errorMessage = nil
    resolutionTask = Task { @MainActor in
      let destination: Destination
      if #available(iOS 18.0, *),
        let item = try? await MKMapItemRequest(feature: feature).mapItem
      {
        destination = Destination(mapItem: item)
      } else {
        destination = Destination(
          name: feature.title ?? "地圖上的地點",
          coordinate: GeoCoordinate(
            latitude: feature.coordinate.latitude,
            longitude: feature.coordinate.longitude
          ),
          sourceReference: "map-feature"
        )
      }
      guard !Task.isCancelled else { return }
      select(destination)
      isResolving = false
    }
  }

  private func resolve(coordinate: CLLocationCoordinate2D) {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return }
    selectedFeature = nil
    resolutionTask?.cancel()
    isResolving = true
    errorMessage = nil
    resolutionTask = Task { @MainActor in
      let placemark = try? await CLGeocoder()
        .reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        .first
      guard !Task.isCancelled else { return }
      select(
        Destination(
          name: placemark?.name ?? "自訂停車點",
          address: address(from: placemark),
          coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
          sourceReference: "map-long-press"
        )
      )
      isResolving = false
    }
  }

  private func select(_ selected: Destination) {
    guard ParkingSelectionCoverage.contains(selected.coordinate, centeredAt: destination.coordinate) else {
      errorMessage = "這個位置超出導航 Snapshot 可用範圍。"
      isResolving = false
      return
    }
    errorMessage = nil
    onSelect(selected)
  }

  private func address(from placemark: CLPlacemark?) -> String? {
    guard let placemark else { return nil }
    let parts = [placemark.administrativeArea, placemark.locality, placemark.subLocality, placemark.thoroughfare]
      .compactMap { $0?.nilIfBlank }
    return parts.isEmpty ? nil : parts.joined()
  }
}
