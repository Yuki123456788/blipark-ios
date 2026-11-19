import Foundation

enum GuidanceSessionLaunch {
  static func makeSession(
    from plan: ParkingPlan,
    mode: GuidanceMode,
    now: Date = .now
  ) -> ParkingGuidanceSession {
    ParkingGuidanceSession(
      id: UUID(),
      sourcePlanID: plan.id,
      destination: plan.destination,
      orderedCandidates: plan.candidates,
      currentCandidateIndex: 0,
      mode: mode,
      status: .active,
      startedAt: now,
      updatedAt: now
    )
  }

  static func externalMapURL(
    provider: ExternalMapProvider,
    destination: Destination
  ) -> URL? {
    let coordinate = destination.coordinate
    let value = "\(coordinate.latitude),\(coordinate.longitude)"
    var components: URLComponents

    switch provider {
    case .appleMaps:
      components = URLComponents()
      components.scheme = "https"
      components.host = "maps.apple.com"
      components.path = "/"
      components.queryItems = [
        URLQueryItem(name: "daddr", value: value),
        URLQueryItem(name: "dirflg", value: "d"),
      ]
    case .googleMaps:
      components = URLComponents()
      components.scheme = "https"
      components.host = "www.google.com"
      components.path = "/maps/dir/"
      components.queryItems = [
        URLQueryItem(name: "api", value: "1"),
        URLQueryItem(name: "destination", value: value),
        URLQueryItem(name: "travelmode", value: "driving"),
      ]
    }

    return components.url
  }
}

extension ExternalMapProvider {
  var title: String {
    switch self {
    case .appleMaps: "Apple 地圖"
    case .googleMaps: "Google Maps"
    }
  }

  var symbolName: String {
    switch self {
    case .appleMaps: "map.fill"
    case .googleMaps: "location.fill"
    }
  }
}
