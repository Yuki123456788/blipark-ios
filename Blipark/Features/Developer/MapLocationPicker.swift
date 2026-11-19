import CoreLocation
import MapKit
import SwiftUI

struct MapLocationPicker: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var searchModel = PlaceSearchModel()
  @State private var query = ""
  @State private var camera: MapCameraPosition
  @State private var selectedFeature: MapFeature?
  @State private var pendingDestination: Destination?
  @State private var isResolving = false
  @State private var errorMessage: String?
  @State private var pressOrigin: CGPoint?
  @State private var longPressTask: Task<Void, Never>?
  @State private var resolutionTask: Task<Void, Never>?

  let title: String
  let onSelect: (Destination) -> Void

  init(
    title: String,
    destination: Destination?,
    defaultCoordinate: GeoCoordinate,
    onSelect: @escaping (Destination) -> Void
  ) {
    self.title = title
    self.onSelect = onSelect
    _pendingDestination = State(initialValue: destination)
    let center = destination?.coordinate ?? defaultCoordinate
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: center.clLocationCoordinate,
          latitudinalMeters: destination == nil ? 8_000 : 1_200,
          longitudinalMeters: destination == nil ? 8_000 : 1_200
        )
      )
    )
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchPanel
        locationMap
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { dismissKeyboard() }
        }
      }
    }
    .onDisappear {
      longPressTask?.cancel()
      resolutionTask?.cancel()
    }
  }

  private var locationMap: some View {
    MapReader { proxy in
      Map(
        position: $camera,
        interactionModes: [.pan, .zoom],
        selection: $selectedFeature
      ) {
        if let pendingDestination {
          Marker(
            pendingDestination.name,
            systemImage: "mappin.circle.fill",
            coordinate: pendingDestination.coordinate.clLocationCoordinate
          )
          .tint(BliparkStyle.brand)
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
      .overlay(alignment: .bottom) { selectionCard }
    }
  }

  private var searchPanel: some View {
    VStack(spacing: 8) {
      HStack {
        TextField("搜尋地標或地址", text: $query)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.search)
          .onSubmit {
            dismissKeyboard()
            Task { await searchModel.search(query, near: pendingDestination?.coordinate ?? .tainanCenter) }
          }
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
    .padding()
    .background(Color(.systemGroupedBackground))
  }

  @ViewBuilder
  private var selectionCard: some View {
    if let pendingDestination {
      VStack(alignment: .leading, spacing: 7) {
        Label(pendingDestination.name, systemImage: "mappin.circle.fill")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        if let address = pendingDestination.address {
          Text(address)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        HStack {
          Button("使用這個目的地", systemImage: "checkmark.circle.fill") {
            onSelect(pendingDestination)
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          Button("取消選取") {
            self.pendingDestination = nil
            selectedFeature = nil
          }
          .buttonStyle(.bordered)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      .padding(10)
    } else if isResolving {
      HStack(spacing: 8) {
        ProgressView()
        Text("正在取得地點資訊…").font(.footnote.weight(.medium))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(.regularMaterial, in: Capsule())
      .padding(10)
    } else if let errorMessage {
      Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.red)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
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
        let movement = hypot(
          value.location.x - pressOrigin.x,
          value.location.y - pressOrigin.y
        )
        if movement > 12 {
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
      if #available(iOS 18.0, *),
        let item = try? await MKMapItemRequest(feature: feature).mapItem
      {
        guard !Task.isCancelled else { return }
        select(Destination(mapItem: item))
      } else {
        select(
          Destination(
            name: feature.title ?? "地圖上的地點",
            coordinate: GeoCoordinate(
              latitude: feature.coordinate.latitude,
              longitude: feature.coordinate.longitude
            ),
            sourceReference: "map-feature"
          )
        )
      }
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
      do {
        let placemark = try await CLGeocoder()
          .reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
          .first
        try Task.checkCancellation()
        select(
          Destination(
            name: placemark?.name ?? "自訂位置",
            address: address(from: placemark),
            coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            sourceReference: "map-long-press"
          )
        )
      } catch is CancellationError {
        return
      } catch {
        select(
          Destination(
            name: "自訂位置",
            coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            sourceReference: "map-long-press"
          )
        )
      }
      isResolving = false
    }
  }

  private func select(_ destination: Destination) {
    pendingDestination = destination
    errorMessage = nil
    isResolving = false
    camera = .region(
      MKCoordinateRegion(
        center: destination.coordinate.clLocationCoordinate,
        latitudinalMeters: 1_200,
        longitudinalMeters: 1_200
      )
    )
  }

  private func address(from placemark: CLPlacemark?) -> String? {
    guard let placemark else { return nil }
    let parts = [placemark.administrativeArea, placemark.locality, placemark.subLocality, placemark.thoroughfare]
      .compactMap { $0?.nilIfBlank }
    return parts.isEmpty ? nil : parts.joined()
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

extension Destination {
  init(mapItem: MKMapItem) {
    self.init(
      name: mapItem.name?.nilIfBlank ?? "未命名地點",
      address: mapItem.placemark.title?.nilIfBlank,
      coordinate: GeoCoordinate(
        latitude: mapItem.placemark.coordinate.latitude,
        longitude: mapItem.placemark.coordinate.longitude
      ),
      sourceReference: "mapkit"
    )
  }
}

extension GeoCoordinate {
  static let tainanCenter = GeoCoordinate(latitude: 22.9910, longitude: 120.2040)
}
