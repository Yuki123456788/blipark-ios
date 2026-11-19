import CoreLocation
import Foundation
import MapKit
import UIKit

enum PiPRealNavigationState: String {
  case idle = "尚未開始"
  case preparingSession = "正在準備測試"
  case standby = "待機監控中"
  case preparingNavigation = "正在準備導航"
  case navigating = "真實定位導航中"
  case ended = "測試已結束"
  case failed = "測試失敗"
}

enum PiPRealNavigationRenderMode: String, CaseIterable, Identifiable {
  case singleSnapshot = "單張大圖"
  case tileGrid = "圖磚拼接"

  var id: String { rawValue }
}

struct PiPRealNavigationDestination: Identifiable {
  let id = UUID()
  let mapItem: MKMapItem
  let name: String
  let address: String

  var coordinate: CLLocationCoordinate2D { mapItem.placemark.coordinate }

  init(mapItem: MKMapItem, fallbackAddress: String? = nil) {
    self.mapItem = mapItem
    name = mapItem.name ?? "未命名地點"
    address = mapItem.placemark.title ?? fallbackAddress ?? "地址未提供"
  }
}

enum PiPRealParkingKind: String, CaseIterable, Identifiable, Sendable {
  case parkingLot = "停車場"
  case onStreet = "路邊停車格"

  var id: String { rawValue }

  var symbolName: String {
    switch self {
    case .parkingLot: "parkingsign.circle.fill"
    case .onStreet: "road.lanes"
    }
  }
}

enum PiPRealParkingColor: Int, CaseIterable, Sendable {
  case blue
  case amber
  case teal
  case violet

  var uiColor: UIColor {
    switch self {
    case .blue: UIColor(red: 0.12, green: 0.45, blue: 0.83, alpha: 1)
    case .amber: UIColor(red: 0.89, green: 0.55, blue: 0.12, alpha: 1)
    case .teal: UIColor(red: 0.08, green: 0.58, blue: 0.55, alpha: 1)
    case .violet: UIColor(red: 0.50, green: 0.36, blue: 0.78, alpha: 1)
    }
  }

  static func ordered(at index: Int) -> Self {
    allCases[index % allCases.count]
  }
}

struct PiPRealParkingStop: Identifiable {
  let id: UUID
  let destination: PiPRealNavigationDestination
  let kind: PiPRealParkingKind
  let color: PiPRealParkingColor

  var name: String { destination.name }
  var address: String { destination.address }
  var coordinate: CLLocationCoordinate2D { destination.coordinate }

  init(
    id: UUID = UUID(),
    destination: PiPRealNavigationDestination,
    kind: PiPRealParkingKind,
    color: PiPRealParkingColor
  ) {
    self.id = id
    self.destination = destination
    self.kind = kind
    self.color = color
  }
}

struct PiPRealParkingRenderStop: Sendable {
  let name: String
  let kind: PiPRealParkingKind
  let color: PiPRealParkingColor
  let imagePoint: CGPoint
  let isCurrent: Bool
}

struct PiPRealNavigationRenderOverlay: @unchecked Sendable {
  let currentStop: PiPRealParkingRenderStop
  let upcomingStops: [PiPRealParkingRenderStop]
  let remainingRouteDistanceMeters: CLLocationDistance
  let previewRoute: PiPNavigationPreparedRoute?
}

struct PiPRealNavigationSettings {
  static let snapshotCoverageWidthMeters: CLLocationDistance = 4_000
  static let snapshotPixelSize = CGSize(width: 3_072, height: 3_072)

  static func snapshotMapRect(center: CLLocationCoordinate2D) -> MKMapRect {
    PreCapturedRasterNavigationRenderer.sourceMapRect(
      center: center,
      widthMeters: snapshotCoverageWidthMeters,
      aspectRatio: Double(snapshotPixelSize.width / snapshotPixelSize.height)
    )
  }

  var triggerDistanceMeters: CLLocationDistance = 2_000
  var zoomMode: PiPDynamicZoomMode = .fixed
  var renderMode: PiPRealNavigationRenderMode = .singleSnapshot
  var tileGrid: PiPTileNavigationGridPreset = .three
  var cameraConfiguration: PiPDynamicCameraConfiguration = {
    var configuration = PiPDynamicCameraConfiguration()
    configuration.fixedLookAheadMeters = 300
    configuration.lookAheadSeconds = 18
    configuration.safetyDistanceMeters = 100
    configuration.cityMinimumLookAheadMeters = 220
    configuration.turnMinimumLookAheadMeters = 110
    configuration.pitchDegrees = 35
    return configuration
  }()
  var locationDistanceFilter = 10.0
  var maximumHorizontalAccuracy = 100.0
  var offRouteThresholdMeters = 75.0
  var offRouteConfirmationCount = 3
  var rerouteCooldownSeconds = 30.0
  var positionPredictionLimitSeconds = 2.0
  var routeOverviewDurationSeconds = 2.0
  var routeOverviewTransitionSeconds = 1.2
  var rerouteOverviewDurationSeconds = 0.8
  var rerouteOverviewTransitionSeconds = 0.8
  var nextRoutePreviewDistanceMeters: CLLocationDistance = 120
  var parkingArrivalRadiusMeters: CLLocationDistance = 55
  var parkingDepartureDeltaMeters: CLLocationDistance = 35
  var parkingDepartureConfirmationCount = 2
  var showsDebugTileBoundaries = false
}

extension PiPTileNavigationGridPreset {
  var realNavigationSquareConfiguration: PiPTileNavigationConfiguration {
    PiPTileNavigationConfiguration(
      columns: rawValue,
      rows: rawValue,
      tilePixelSize: CGSize(width: 1_536, height: 1_536),
      coverageWidthMeters: PiPRealNavigationSettings.snapshotCoverageWidthMeters,
      seamBleedPixels: 0.75
    )
  }
}

struct PiPRealParkingAdvanceDetector {
  private(set) var hasEnteredArrivalZone = false
  private(set) var closestDistanceMeters = CLLocationDistance.greatestFiniteMagnitude
  private(set) var departureCount = 0

  mutating func reset() {
    hasEnteredArrivalZone = false
    closestDistanceMeters = .greatestFiniteMagnitude
    departureCount = 0
  }

  mutating func observe(
    distanceMeters: CLLocationDistance,
    speedMetersPerSecond: CLLocationSpeed,
    arrivalRadiusMeters: CLLocationDistance,
    departureDeltaMeters: CLLocationDistance,
    confirmationCount: Int
  ) -> Bool {
    guard distanceMeters.isFinite, distanceMeters >= 0 else { return false }
    closestDistanceMeters = min(closestDistanceMeters, distanceMeters)
    if distanceMeters <= arrivalRadiusMeters {
      hasEnteredArrivalZone = true
      departureCount = 0
      return false
    }
    guard hasEnteredArrivalZone else { return false }

    let hasClearlyDeparted =
      distanceMeters >= closestDistanceMeters + departureDeltaMeters
      && distanceMeters >= arrivalRadiusMeters + departureDeltaMeters * 0.5
      && speedMetersPerSecond >= 1.5
    if hasClearlyDeparted {
      departureCount += 1
    } else {
      departureCount = 0
    }
    return departureCount >= max(confirmationCount, 1)
  }
}

struct PiPRealMotionObservation {
  let sample: PiPNavigationSample
  let speedMetersPerSecond: CLLocationSpeed
  let hasMeasuredCourse: Bool
  let observedAtUptime: TimeInterval
}

struct PiPRealMotionInterpolator {
  private(set) var displayedImagePoint: CGPoint?
  private var lastFrameTime: TimeInterval?

  mutating func reset() {
    displayedImagePoint = nil
    lastFrameTime = nil
  }

  mutating func sample(
    for observation: PiPRealMotionObservation,
    sourceMetersPerPixel: CGFloat,
    predictionLimitSeconds: TimeInterval,
    at time: TimeInterval
  ) -> PiPNavigationSample {
    let predictionLimit = min(max(predictionLimitSeconds, 0), 4)
    let speed = max(observation.speedMetersPerSecond, 0)
    let predictionAge =
      observation.hasMeasuredCourse && speed >= 0.8
      ? min(max(time - observation.observedAtUptime, 0), predictionLimit)
      : 0
    let distancePixels =
      speed * predictionAge / Double(max(sourceMetersPerPixel, .ulpOfOne))
    let radians = observation.sample.headingDegrees * .pi / 180
    let predictedPoint = CGPoint(
      x: observation.sample.imagePoint.x + sin(radians) * distancePixels,
      y: observation.sample.imagePoint.y - cos(radians) * distancePixels
    )

    if predictionLimit == 0 {
      displayedImagePoint = observation.sample.imagePoint
    } else if displayedImagePoint == nil {
      displayedImagePoint = predictedPoint
    } else {
      let deltaTime = max(0, min(time - (lastFrameTime ?? time), 0.25))
      let alpha = deltaTime > 0 ? 1 - exp(-deltaTime / 0.28) : 0
      displayedImagePoint!.x += (predictedPoint.x - displayedImagePoint!.x) * alpha
      displayedImagePoint!.y += (predictedPoint.y - displayedImagePoint!.y) * alpha
    }
    lastFrameTime = time

    return PiPNavigationSample(
      distanceMeters: observation.sample.distanceMeters,
      coordinate: observation.sample.coordinate,
      imagePoint: displayedImagePoint ?? predictedPoint,
      headingDegrees: observation.sample.headingDegrees,
      progress: observation.sample.progress
    )
  }
}

enum PiPRealRoutePresentationTimeline {
  static func presentation(
    startedAt: TimeInterval,
    overviewDuration: TimeInterval,
    transitionDuration: TimeInterval,
    at time: TimeInterval
  ) -> PiPDynamicRoutePresentation {
    let elapsed = max(0, time - startedAt)
    let hold = max(overviewDuration, 0)
    let transition = max(transitionDuration, 0.01)
    guard elapsed > hold else {
      return PiPDynamicRoutePresentation(
        overviewToNavigationProgress: 0,
        promptAlpha: 1
      )
    }
    let linearProgress = min(max((elapsed - hold) / transition, 0), 1)
    let easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
    return PiPDynamicRoutePresentation(
      overviewToNavigationProgress: easedProgress,
      promptAlpha: 1 - linearProgress
    )
  }
}

struct PiPRealNavigationRouteMatch {
  let distanceFromRouteMeters: CLLocationDistance
  let distanceAlongRouteMeters: CLLocationDistance
  let routeHeadingDegrees: CLLocationDirection
}

enum PiPRealNavigationRouteMatcher {
  static func match(
    coordinate: CLLocationCoordinate2D,
    route: PiPNavigationPreparedRoute
  ) -> PiPRealNavigationRouteMatch {
    let point = MKMapPoint(coordinate)
    var bestDistance = CLLocationDistance.greatestFiniteMagnitude
    var bestAlong: CLLocationDistance = 0
    var bestHeading: CLLocationDirection = 0

    for index in 0..<(route.coordinates.count - 1) {
      let start = MKMapPoint(route.coordinates[index])
      let end = MKMapPoint(route.coordinates[index + 1])
      let dx = end.x - start.x
      let dy = end.y - start.y
      let lengthSquared = dx * dx + dy * dy
      let fraction: Double
      if lengthSquared <= .ulpOfOne {
        fraction = 0
      } else {
        fraction = min(
          max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
      }
      let projected = MKMapPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
      let distance = point.distance(to: projected)
      guard distance < bestDistance else { continue }
      bestDistance = distance
      let segmentLength = start.distance(to: end)
      bestAlong = route.cumulativeDistances[index] + segmentLength * fraction
      bestHeading = bearing(from: route.coordinates[index], to: route.coordinates[index + 1])
    }

    return PiPRealNavigationRouteMatch(
      distanceFromRouteMeters: bestDistance,
      distanceAlongRouteMeters: bestAlong,
      routeHeadingDegrees: bestHeading
    )
  }

  private static func bearing(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
  ) -> CLLocationDirection {
    let latitude1 = start.latitude * .pi / 180
    let latitude2 = end.latitude * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(latitude2)
    let x =
      cos(latitude1) * sin(latitude2)
      - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
    guard abs(x) > .ulpOfOne || abs(y) > .ulpOfOne else { return 0 }
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
  }
}

struct PiPRealNavigationDebugSnapshot {
  var latitude: Double?
  var longitude: Double?
  var horizontalAccuracy: CLLocationAccuracy?
  var speedKmh: Double?
  var course: CLLocationDirection?
  var deviceHeading: CLLocationDirection?
  var vehicleHeadingSource = "—"
  var locationTimestamp: Date?
  var straightLineDistanceMeters: CLLocationDistance?
  var routeDistanceMeters: CLLocationDistance?
  var distanceFromRouteMeters: CLLocationDistance?
  var cameraMode: String = "—"
  var cameraLookAheadMeters: CLLocationDistance?
  var cameraPitchDegrees: Double?
  var cameraBearingDegrees: CLLocationDirection?
  var vehicleWorldHeadingDegrees: CLLocationDirection?
  var vehicleScreenRotationDegrees: CLLocationDirection?
  var displayedPositionMode = "GPS 原始點"
  var renderFPS = 0.0
  var mapCoverage = "尚未準備"
  var lastRerouteAt: Date?
  var routeStatus = "尚未建立"
  var activeParkingStop = "—"
  var nextRouteStatus = "尚未預載"
  var applicationState = "active"
}
