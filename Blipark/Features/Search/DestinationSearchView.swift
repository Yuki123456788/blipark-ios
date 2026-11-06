import SwiftUI

struct DestinationSearchView: View {
  @StateObject private var model: DestinationSearchModel
  @State private var query = ""

  private let parkingProvider: any ParkingDataProviding

  init(
    destinationProvider: any DestinationSearchProviding,
    parkingProvider: any ParkingDataProviding
  ) {
    _model = StateObject(wrappedValue: DestinationSearchModel(provider: destinationProvider))
    self.parkingProvider = parkingProvider
  }

  var body: some View {
    Group {
      if query.isEmpty {
        ContentUnavailableView(
          "搜尋目的地",
          systemImage: "magnifyingglass",
          description: Text("輸入地點、地址，或貼上含座標的完整 Apple Maps／Google Maps 連結。")
        )
      } else if model.isSearching && model.results.isEmpty {
        ProgressView("正在搜尋…")
      } else if let error = model.errorMessage {
        ContentUnavailableView(
          "無法使用這個搜尋內容",
          systemImage: "exclamationmark.magnifyingglass",
          description: Text(error)
        )
      } else if model.results.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
        List(model.results) { destination in
          NavigationLink {
            DestinationExploreView(destination: destination, parkingProvider: parkingProvider)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(BliparkStyle.brand)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 3) {
                Text(destination.name).font(.headline)
                Text(destination.address ?? coordinateText(destination.coordinate))
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            .padding(.vertical, 4)
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("搜尋目的地")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: "地點、地址或地圖連結")
    .task(id: query) {
      do {
        try await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await model.search(query)
      } catch {}
    }
  }

  private func coordinateText(_ coordinate: GeoCoordinate) -> String {
    String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
  }
}

