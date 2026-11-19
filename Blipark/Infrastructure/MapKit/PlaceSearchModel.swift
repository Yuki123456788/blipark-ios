import MapKit

struct PlaceSearchResult: Identifiable {
  let id = UUID()
  let name: String
  let address: String?
  let coordinate: GeoCoordinate
}

@MainActor
final class PlaceSearchModel: ObservableObject {
  @Published private(set) var results: [PlaceSearchResult] = []
  @Published private(set) var isSearching = false
  @Published var errorMessage: String?

  func search(_ query: String, near coordinate: GeoCoordinate?) async {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      results = []
      return
    }
    isSearching = true
    errorMessage = nil
    defer { isSearching = false }

    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = normalized
    if let coordinate {
      request.region = MKCoordinateRegion(
        center: coordinate.clLocationCoordinate,
        latitudinalMeters: 20_000,
        longitudinalMeters: 20_000
      )
    }
    do {
      let response = try await MKLocalSearch(request: request).start()
      results = response.mapItems.prefix(8).map { item in
        PlaceSearchResult(
          name: item.name ?? normalized,
          address: item.placemark.title,
          coordinate: GeoCoordinate(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
          )
        )
      }
    } catch {
      results = []
      errorMessage = "地點搜尋失敗：\(error.localizedDescription)"
    }
  }
}

