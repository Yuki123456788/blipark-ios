import CoreGraphics
import Foundation
import MapKit

struct PiPNavigationScenario: Identifiable, Equatable {
  let id: String
  let title: String
  let detail: String
  let source: CLLocationCoordinate2D
  let destination: CLLocationCoordinate2D

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

  static let presets = [
    PiPNavigationScenario(
      id: "A",
      title: "情境 A・簡單路線",
      detail: "臺南車站 → 海安路候選停車點",
      source: NavigationDisplayState.sample.currentLocation,
      destination: NavigationDisplayState.sample.parkingLocation
    ),
    PiPNavigationScenario(
      id: "B",
      title: "情境 B・一般市區",
      detail: "海安路候選停車點 → 林百貨",
      source: NavigationDisplayState.sample.parkingLocation,
      destination: NavigationDisplayState.sample.originalDestination
    ),
    PiPNavigationScenario(
      id: "C",
      title: "情境 C・較多轉彎",
      detail: "林百貨 → 臺南車站",
      source: NavigationDisplayState.sample.originalDestination,
      destination: NavigationDisplayState.sample.currentLocation
    ),
  ]
}

enum PiPNavigationSpeed: Int, CaseIterable, Identifiable {
  case kmh20 = 20
  case kmh40 = 40
  case kmh60 = 60

  var id: Int { rawValue }
  var title: String { "\(rawValue) km/h" }
  var metersPerSecond: Double { Double(rawValue) / 3.6 }
}

struct PiPNavigationRouteStep {
  let distanceMeters: CLLocationDistance
  let coordinates: [CLLocationCoordinate2D]
}

enum PiPNavigationDisplayConfiguration {
  /// Horizontal geographic width rendered into the PiP frame.
  static let viewportWidthMeters: CLLocationDistance = 150
}

enum PiPNavigationMapMode: Equatable {
  case singleSnapshot
  case tileGrid

  var navigationTitle: String {
    switch self {
    case .singleSnapshot: "PiP 模擬導航測試"
    case .tileGrid: "PiP 圖磚模擬導航測試"
    }
  }
}

protocol PiPNavigationProjectionSource: AnyObject, Sendable {
  var fallbackImage: CGImage { get }
  var metersPerPixel: CGFloat { get }

  func imagePoint(for coordinate: CLLocationCoordinate2D) -> CGPoint
  func contains(_ coordinates: [CLLocationCoordinate2D]) -> Bool
}

final class PiPNavigationMapSource: PiPNavigationProjectionSource, @unchecked Sendable {
  let image: CGImage
  let imageSize: CGSize
  let mapRect: MKMapRect
  let projection: PreCapturedRasterProjection
  let geographicWidthMeters: CLLocationDistance
  let center: CLLocationCoordinate2D

  var metersPerPixel: CGFloat {
    CGFloat(geographicWidthMeters) / projection.projectedMapRectWidthPixels
  }

  var fallbackImage: CGImage { image }

  init(
    image: CGImage,
    mapRect: MKMapRect,
    geographicWidthMeters: CLLocationDistance,
    center: CLLocationCoordinate2D,
    projection: PreCapturedRasterProjection? = nil
  ) {
    self.image = image
    imageSize = CGSize(width: image.width, height: image.height)
    self.mapRect = mapRect
    self.projection = projection ?? PreCapturedRasterProjection(
      mapRect: mapRect,
      imageSize: imageSize
    )
    self.geographicWidthMeters = geographicWidthMeters
    self.center = center
  }

  func imagePoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    projection.imagePoint(for: coordinate)
  }

  func contains(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
    coordinates.allSatisfy(projection.contains)
  }
}

struct PiPNavigationRouteAttempt: Identifiable {
  let id = UUID()
  let scenarioID: String
  let startedAt: Date
  let completedAt: Date
  let startedApplicationState: String
  let completedApplicationState: String
  let succeeded: Bool
  let routePointCount: Int
  let routeStepCount: Int
  let errorDescription: String?

  var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }
  var completedInBackground: Bool {
    startedApplicationState == "background" && completedApplicationState == "background"
  }
}

struct PiPNavigationSample {
  let distanceMeters: CLLocationDistance
  let coordinate: CLLocationCoordinate2D
  let imagePoint: CGPoint
  let headingDegrees: CLLocationDirection
  let progress: Double
}

final class PiPNavigationPreparedRoute: @unchecked Sendable, Identifiable {
  let scenario: PiPNavigationScenario
  let image: CGImage
  let imageSize: CGSize
  let coordinates: [CLLocationCoordinate2D]
  let imagePoints: [CGPoint]
  let cumulativeDistances: [CLLocationDistance]
  let steps: [PiPNavigationRouteStep]
  let routeDistanceMeters: CLLocationDistance
  let expectedTravelTime: TimeInterval
  let viewportWidthMeters: CLLocationDistance
  let sourceMetersPerPixel: CGFloat
  let tileSource: PiPTileNavigationMapSource?

  var id: String { scenario.id }

  init(
    scenario: PiPNavigationScenario,
    image: CGImage,
    coordinates: [CLLocationCoordinate2D],
    imagePoints: [CGPoint],
    steps: [PiPNavigationRouteStep],
    expectedTravelTime: TimeInterval,
    viewportWidthMeters: CLLocationDistance = PiPNavigationDisplayConfiguration.viewportWidthMeters,
    sourceMetersPerPixel: CGFloat? = nil,
    tileSource: PiPTileNavigationMapSource? = nil
  ) {
    precondition(coordinates.count == imagePoints.count && coordinates.count >= 2)
    self.scenario = scenario
    self.image = image
    imageSize = CGSize(width: image.width, height: image.height)
    self.coordinates = coordinates
    self.imagePoints = imagePoints
    self.steps = steps
    self.expectedTravelTime = expectedTravelTime
    self.viewportWidthMeters = viewportWidthMeters
    self.sourceMetersPerPixel = sourceMetersPerPixel ?? 1
    self.tileSource = tileSource

    var distances = [CLLocationDistance](repeating: 0, count: coordinates.count)
    for index in 1..<coordinates.count {
      distances[index] = distances[index - 1]
        + MKMapPoint(coordinates[index - 1]).distance(to: MKMapPoint(coordinates[index]))
    }
    cumulativeDistances = distances
    routeDistanceMeters = distances.last ?? 0
  }


  convenience init(
    scenario: PiPNavigationScenario,
    source: any PiPNavigationProjectionSource,
    coordinates: [CLLocationCoordinate2D],
    steps: [PiPNavigationRouteStep],
    expectedTravelTime: TimeInterval,
    viewportWidthMeters: CLLocationDistance = PiPNavigationDisplayConfiguration.viewportWidthMeters
  ) {
    self.init(
      scenario: scenario,
      image: source.fallbackImage,
      coordinates: coordinates,
      imagePoints: coordinates.map(source.imagePoint(for:)),
      steps: steps,
      expectedTravelTime: expectedTravelTime,
      viewportWidthMeters: viewportWidthMeters,
      sourceMetersPerPixel: source.metersPerPixel,
      tileSource: source as? PiPTileNavigationMapSource
    )
  }

  convenience init(
    scenario: PiPNavigationScenario,
    source: PiPNavigationMapSource,
    coordinates: [CLLocationCoordinate2D],
    steps: [PiPNavigationRouteStep],
    expectedTravelTime: TimeInterval,
    viewportWidthMeters: CLLocationDistance = PiPNavigationDisplayConfiguration.viewportWidthMeters
  ) {
    self.init(
      scenario: scenario,
      image: source.image,
      coordinates: coordinates,
      imagePoints: coordinates.map(source.imagePoint(for:)),
      steps: steps,
      expectedTravelTime: expectedTravelTime,
      viewportWidthMeters: viewportWidthMeters,
      sourceMetersPerPixel: source.metersPerPixel
    )
  }

  func sample(at requestedDistance: CLLocationDistance) -> PiPNavigationSample {
    let distance = min(max(0, requestedDistance), routeDistanceMeters)
    let segmentIndex = segment(containing: distance)
    let lowerDistance = cumulativeDistances[segmentIndex]
    let upperDistance = cumulativeDistances[segmentIndex + 1]
    let segmentLength = max(upperDistance - lowerDistance, .ulpOfOne)
    let fraction = (distance - lowerDistance) / segmentLength

    let startMapPoint = MKMapPoint(coordinates[segmentIndex])
    let endMapPoint = MKMapPoint(coordinates[segmentIndex + 1])
    let mapPoint = MKMapPoint(
      x: startMapPoint.x + (endMapPoint.x - startMapPoint.x) * fraction,
      y: startMapPoint.y + (endMapPoint.y - startMapPoint.y) * fraction
    )
    let startImagePoint = imagePoints[segmentIndex]
    let endImagePoint = imagePoints[segmentIndex + 1]
    let imagePoint = CGPoint(
      x: startImagePoint.x + (endImagePoint.x - startImagePoint.x) * fraction,
      y: startImagePoint.y + (endImagePoint.y - startImagePoint.y) * fraction
    )

    // A short look-behind/look-ahead chord avoids unstable headings on MapKit's
    // very short adjacent polyline segments and handles north crossing naturally.
    let headingStart = coordinate(at: max(0, distance - 12))
    let headingEnd = coordinate(at: min(routeDistanceMeters, distance + 28))
    let heading = Self.bearing(from: headingStart, to: headingEnd)

    return PiPNavigationSample(
      distanceMeters: distance,
      coordinate: mapPoint.coordinate,
      imagePoint: imagePoint,
      headingDegrees: heading,
      progress: routeDistanceMeters > 0 ? distance / routeDistanceMeters : 1
    )
  }

  func coordinate(at requestedDistance: CLLocationDistance) -> CLLocationCoordinate2D {
    let distance = min(max(0, requestedDistance), routeDistanceMeters)
    let index = segment(containing: distance)
    let lowerDistance = cumulativeDistances[index]
    let upperDistance = cumulativeDistances[index + 1]
    let fraction = (distance - lowerDistance) / max(upperDistance - lowerDistance, .ulpOfOne)
    let start = MKMapPoint(coordinates[index])
    let end = MKMapPoint(coordinates[index + 1])
    return MKMapPoint(
      x: start.x + (end.x - start.x) * fraction,
      y: start.y + (end.y - start.y) * fraction
    ).coordinate
  }

  private func segment(containing distance: CLLocationDistance) -> Int {
    guard cumulativeDistances.count > 2 else { return 0 }
    var lower = 0
    var upper = cumulativeDistances.count - 1
    while lower + 1 < upper {
      let middle = (lower + upper) / 2
      if cumulativeDistances[middle] <= distance {
        lower = middle
      } else {
        upper = middle
      }
    }
    return min(lower, cumulativeDistances.count - 2)
  }

  private static func bearing(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
  ) -> CLLocationDirection {
    let latitude1 = start.latitude * .pi / 180
    let latitude2 = end.latitude * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(latitude2)
    let x = cos(latitude1) * sin(latitude2)
      - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
    guard abs(x) > .ulpOfOne || abs(y) > .ulpOfOne else { return 0 }
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
  }
}

struct PiPNavigationSequenceSample {
  let routeIndex: Int
  let route: PiPNavigationPreparedRoute
  let sample: PiPNavigationSample
  let sequenceDistanceMeters: CLLocationDistance
  let totalDistanceMeters: CLLocationDistance
  let isComplete: Bool
}

enum PiPNavigationSequenceSampler {
  static func sample(
    routes: [PiPNavigationPreparedRoute],
    startingAt startIndex: Int,
    traveledDistance: CLLocationDistance
  ) -> PiPNavigationSequenceSample? {
    guard routes.indices.contains(startIndex) else { return nil }
    let activeRoutes = Array(routes[startIndex...])
    let total = activeRoutes.reduce(0) { $0 + $1.routeDistanceMeters }
    let clamped = min(max(0, traveledDistance), total)
    var remaining = clamped

    for (offset, route) in activeRoutes.enumerated() {
      let isLast = offset == activeRoutes.count - 1
      if remaining < route.routeDistanceMeters || isLast {
        return PiPNavigationSequenceSample(
          routeIndex: startIndex + offset,
          route: route,
          sample: route.sample(at: remaining),
          sequenceDistanceMeters: clamped,
          totalDistanceMeters: total,
          isComplete: clamped >= total
        )
      }
      remaining -= route.routeDistanceMeters
    }
    return nil
  }
}
