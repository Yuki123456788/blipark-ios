import MapKit

struct MapKitDestinationSearchProvider: DestinationSearchProviding {
  func searchDestinations(matching query: String) async throws -> [Destination] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 22.9999, longitude: 120.2269),
      latitudinalMeters: 80_000,
      longitudinalMeters: 80_000
    )
    let response = try await MKLocalSearch(request: request).start()
    return response.mapItems.prefix(8).map { item in
      Destination(
        name: item.name ?? query,
        address: item.placemark.title,
        coordinate: GeoCoordinate(
          latitude: item.placemark.coordinate.latitude,
          longitude: item.placemark.coordinate.longitude
        ),
        sourceReference: "mapkit-search"
      )
    }
  }

  func destination(id: UUID) async throws -> Destination? { nil }
}

struct CompositeDestinationSearchProvider: DestinationSearchProviding {
  let preferred: any DestinationSearchProviding
  let fallback: any DestinationSearchProviding

  func searchDestinations(matching query: String) async throws -> [Destination] {
    let preferredResults = try await preferred.searchDestinations(matching: query)
    let fallbackResults = (try? await fallback.searchDestinations(matching: query)) ?? []
    return (preferredResults + fallbackResults).reduce(into: []) { unique, candidate in
      let isDuplicate = unique.contains { existing in
        existing.coordinate.straightLineDistance(to: candidate.coordinate) < 30
          && existing.name.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame
      }
      if !isDuplicate { unique.append(candidate) }
    }
  }

  func destination(id: UUID) async throws -> Destination? {
    if let value = try await preferred.destination(id: id) { return value }
    return try await fallback.destination(id: id)
  }
}

