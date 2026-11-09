import MapKit

enum PiPNavigationPreparationError: LocalizedError {
  case noRoute(String)
  case tooFewRoutePoints(String)
  case missingImage
  case routeOutsideSnapshot(String)

  var errorDescription: String? {
    switch self {
    case .noRoute(let title): "找不到「\(title)」的駕車路線。"
    case .tooFewRoutePoints(let title): "「\(title)」沒有足夠的 route polyline points。"
    case .missingImage: "無法建立最終目的地周邊的地圖 CGImage。"
    case .routeOutsideSnapshot(let title): "「\(title)」超出前景預擷取地圖範圍。"
    }
  }
}

enum PiPNavigationRoutePreparationService {
  static let snapshotCenter = NavigationDisplayState.sample.originalDestination
  static let snapshotCoverageMeters: CLLocationDistance = 4_000
  static let snapshotSize = CGSize(width: 4_096, height: 2_304)

  @MainActor
  static func captureDestinationSnapshot() async throws -> PiPNavigationMapSource {
    let asset = try await PreCapturedRasterNavigationRenderer.capture(
      center: snapshotCenter,
      widthMeters: snapshotCoverageMeters,
      pixelSize: snapshotSize,
      hidesPointsOfInterest: true
    )
    guard let image = asset.image.cgImage else {
      throw PiPNavigationPreparationError.missingImage
    }
    return PiPNavigationMapSource(
      image: image,
      mapRect: asset.mapRect,
      geographicWidthMeters: asset.geographicWidthMeters,
      center: snapshotCenter,
      projection: asset.projection
    )
  }

  /// Intentionally called only after the app reports `.background`. This
  /// performs MKDirections and route geometry preparation without requesting
  /// another snapshot; the caller records the real application state at both
  /// ends so a request resumed in foreground cannot be reported as background success.
  static func calculateRoute(
    scenario: PiPNavigationScenario,
    source: any PiPNavigationProjectionSource
  ) async throws -> PiPNavigationPreparedRoute {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: scenario.source))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: scenario.destination))
    request.transportType = .automobile
    request.requestsAlternateRoutes = false

    let directions = MKDirections(request: request)
    return try await withTaskCancellationHandler {
      let response = try await directions.calculate()
      try Task.checkCancellation()
      guard let route = response.routes.first else {
        throw PiPNavigationPreparationError.noRoute(scenario.title)
      }
      let coordinates = route.polyline.pipNavigationCoordinates
      guard coordinates.count >= 2 else {
        throw PiPNavigationPreparationError.tooFewRoutePoints(scenario.title)
      }
      guard source.contains(coordinates) else {
        throw PiPNavigationPreparationError.routeOutsideSnapshot(scenario.title)
      }
      let steps = route.steps.compactMap { step -> PiPNavigationRouteStep? in
        let stepCoordinates = step.polyline.pipNavigationCoordinates
        guard step.distance > 0, stepCoordinates.count >= 2 else { return nil }
        return PiPNavigationRouteStep(
          distanceMeters: step.distance,
          coordinates: stepCoordinates
        )
      }
      return PiPNavigationPreparedRoute(
        scenario: scenario,
        source: source,
        coordinates: coordinates,
        steps: steps,
        expectedTravelTime: route.expectedTravelTime
      )
    } onCancel: {
      directions.cancel()
    }
  }
}

private extension MKPolyline {
  var pipNavigationCoordinates: [CLLocationCoordinate2D] {
    var values = [CLLocationCoordinate2D](
      repeating: CLLocationCoordinate2D(),
      count: pointCount
    )
    getCoordinates(&values, range: NSRange(location: 0, length: pointCount))
    return values
  }
}
