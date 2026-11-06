import MapKit
import SwiftUI

struct DestinationExploreView: View {
  @StateObject private var model: DestinationExploreModel
  @State private var camera: MapCameraPosition
  @State private var detailItem: ExploredParkingLocation?

  init(destination: Destination, parkingProvider: any ParkingDataProviding) {
    _model = StateObject(
      wrappedValue: DestinationExploreModel(destination: destination, provider: parkingProvider)
    )
    _camera = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: destination.coordinate.clLocationCoordinate,
          latitudinalMeters: 2_000,
          longitudinalMeters: 2_000
        )
      )
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      parkingMap
        .frame(height: 300)
      controls
      content
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(model.destination.name)
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load(); fitAllLocations() }
    .sheet(item: $detailItem) { ParkingLocationDetailView(item: $0) }
    .alert("無法取得停車資料", isPresented: errorBinding) {
      Button("重試") { Task { await model.load() } }
      Button("取消", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "未知錯誤")
    }
  }

  private var parkingMap: some View {
    Map(position: $camera, selection: $model.selectedID) {
      Marker(model.destination.name, systemImage: "flag.fill", coordinate: model.destination.coordinate.clLocationCoordinate)
        .tint(.red)
      ForEach(model.locations) { item in
        if let coordinate = item.location.coordinate {
          Marker(
            item.location.name,
            systemImage: item.location.type.symbolName,
            coordinate: coordinate.clLocationCoordinate
          )
          .tint(BliparkStyle.brand)
          .tag(item.id)
        }
      }
    }
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .onChange(of: model.selectedID) { _, id in
      guard let coordinate = model.item(id: id)?.location.coordinate else { return }
      withAnimation {
        camera = .region(
          MKCoordinateRegion(
            center: coordinate.clLocationCoordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
          )
        )
      }
    }
  }

  private var controls: some View {
    HStack {
      Picker("類型", selection: $model.filter) {
        ForEach(ParkingListFilter.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)

      Menu {
        Picker("排序", selection: $model.sort) {
          ForEach(ParkingListSort.allCases) { Text($0.title).tag($0) }
        }
      } label: {
        Label(model.sort.title, systemImage: "arrow.up.arrow.down")
      }
    }
    .padding()
    .background(.bar)
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading && model.locations.isEmpty {
      Spacer()
      ProgressView("正在取得停車候選…")
      Spacer()
    } else if model.visibleLocations.isEmpty {
      BliparkEmptyState(
        title: "沒有停車資料",
        message: "這個目的地目前沒有符合條件的候選停車點，不會自動產生虛假資料。",
        symbol: "parkingsign.circle"
      )
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            HStack {
              Text("候選停車點")
                .font(.headline)
              Spacer()
              Text("\(model.visibleLocations.count) 個")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.visibleLocations) { item in
              Button {
                model.selectedID = item.id
                detailItem = item
              } label: {
                ParkingLocationCard(item: item, isSelected: model.selectedID == item.id)
              }
              .buttonStyle(.plain)
              .id(item.id)
            }
          }
          .padding()
        }
        .onChange(of: model.selectedID) { _, id in
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
  }

  private func fitAllLocations() {
    let coordinates = [model.destination.coordinate] + model.locations.compactMap(\.location.coordinate)
    guard let minLatitude = coordinates.map(\.latitude).min(),
      let maxLatitude = coordinates.map(\.latitude).max(),
      let minLongitude = coordinates.map(\.longitude).min(),
      let maxLongitude = coordinates.map(\.longitude).max()
    else { return }
    let center = CLLocationCoordinate2D(
      latitude: (minLatitude + maxLatitude) / 2,
      longitude: (minLongitude + maxLongitude) / 2
    )
    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLatitude - minLatitude) * 1.5, 0.008),
      longitudeDelta: max((maxLongitude - minLongitude) * 1.5, 0.008)
    )
    camera = .region(MKCoordinateRegion(center: center, span: span))
  }
}

