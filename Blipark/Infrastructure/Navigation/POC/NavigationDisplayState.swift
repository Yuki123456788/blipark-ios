import Foundation
import MapKit

enum NavigationDisplayMode: String, CaseIterable, Identifiable {
  case fullMap
  case guidance
  case hybrid

  var id: Self { self }

  var code: String {
    switch self {
    case .fullMap: "M1"
    case .guidance: "M2"
    case .hybrid: "M3"
    }
  }

  var title: String {
    switch self {
    case .fullMap: "完整地圖"
    case .guidance: "方向提示"
    case .hybrid: "混合模式"
    }
  }

  var scenarioOption: String { "\(code) \(title)" }

  init?(scenarioOption: String) {
    guard let mode = Self.allCases.first(where: { scenarioOption.hasPrefix($0.code) }) else {
      return nil
    }
    self = mode
  }
}

enum ManeuverType: String, CaseIterable, Identifiable {
  case straight
  case left
  case right
  case uTurn

  var id: Self { self }

  var title: String {
    switch self {
    case .straight: "直行"
    case .left: "左轉"
    case .right: "右轉"
    case .uTurn: "迴轉"
    }
  }

  var symbolName: String {
    switch self {
    case .straight: "arrow.up"
    case .left: "arrow.turn.up.left"
    case .right: "arrow.turn.up.right"
    case .uTurn: "arrow.uturn.left"
    }
  }

  var sampleDistanceMeters: Int {
    switch self {
    case .straight: 300
    case .left: 80
    case .right: 150
    case .uTurn: 60
    }
  }

  var sampleInstruction: String {
    switch self {
    case .straight: "繼續直行"
    case .left: "左轉進入中正路"
    case .right: "右轉進入海安路"
    case .uTurn: "前方路口迴轉"
    }
  }

  init?(title: String) {
    guard let maneuver = Self.allCases.first(where: { $0.title == title }) else {
      return nil
    }
    self = maneuver
  }

  init(navigationInstruction instruction: String) {
    let normalized = instruction
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()

    if Self.uTurnTerms.contains(where: normalized.contains) {
      self = .uTurn
    } else if Self.rightTurnTerms.contains(where: normalized.contains) {
      self = .right
    } else if Self.leftTurnTerms.contains(where: normalized.contains) {
      self = .left
    } else {
      self = .straight
    }
  }

  private static let uTurnTerms = [
    "迴轉", "回轉", "掉頭", "u-turn", "u turn", "make a u",
  ]

  private static let rightTurnTerms = [
    "右轉", "向右", "靠右", "右側", "turn right", "bear right", "keep right",
    "slight right", "sharp right", "take the right",
  ]

  private static let leftTurnTerms = [
    "左轉", "向左", "靠左", "左側", "turn left", "bear left", "keep left",
    "slight left", "sharp left", "take the left",
  ]
}

struct NavigationRouteStep: Equatable {
  let instruction: String
  let distanceMeters: CLLocationDistance
  let maneuver: ManeuverType
}

struct NavigationDisplayState {
  var currentLocation: CLLocationCoordinate2D
  let originalDestination: CLLocationCoordinate2D
  var parkingLocation: CLLocationCoordinate2D
  var routeCoordinates: [CLLocationCoordinate2D]
  var routeSteps: [NavigationRouteStep]
  var maneuver: ManeuverType
  var maneuverDistanceMeters: Int
  var instruction: String
  var routeDistanceMeters: CLLocationDistance?
  var expectedTravelTime: TimeInterval?
  var navigationProgress: Double

  static let sample = NavigationDisplayState(
    currentLocation: CLLocationCoordinate2D(latitude: 22.9972, longitude: 120.2127),
    originalDestination: CLLocationCoordinate2D(latitude: 22.9913, longitude: 120.2026),
    parkingLocation: CLLocationCoordinate2D(latitude: 22.9947, longitude: 120.1972),
    routeCoordinates: [],
    routeSteps: [],
    maneuver: .right,
    maneuverDistanceMeters: ManeuverType.right.sampleDistanceMeters,
    instruction: ManeuverType.right.sampleInstruction,
    routeDistanceMeters: nil,
    expectedTravelTime: nil,
    navigationProgress: 0
  )

  var maneuverDistanceText: String {
    "\(maneuverDistanceMeters) m"
  }

  mutating func selectManeuver(_ maneuver: ManeuverType) {
    self.maneuver = maneuver
    maneuverDistanceMeters = maneuver.sampleDistanceMeters
    instruction = maneuver.sampleInstruction
  }

  mutating func selectRouteStep(_ step: NavigationRouteStep) {
    maneuver = step.maneuver
    maneuverDistanceMeters = max(0, Int(step.distanceMeters.rounded()))
    instruction = step.instruction
  }

  mutating func prepareForLateRoute() {
    currentLocation = originalDestination
    parkingLocation = originalDestination
    routeCoordinates = []
    routeSteps = []
    routeDistanceMeters = nil
    expectedTravelTime = nil
    navigationProgress = 0
    maneuver = .straight
    maneuverDistanceMeters = 0
    instruction = "等待背景路線"
  }

  mutating func apply(_ payload: LateNavigationRoutePayload) {
    currentLocation = payload.sourceCoordinate
    parkingLocation = payload.destinationCoordinate
    routeCoordinates = payload.routeCoordinates
    routeSteps = payload.routeSteps
    routeDistanceMeters = payload.distanceMeters
    expectedTravelTime = payload.expectedTravelTime
    navigationProgress = 0
    setNavigationProgress(0)
  }

  mutating func setNavigationProgress(_ progress: Double, updatesManeuver: Bool = true) {
    navigationProgress = min(1, max(0, progress))
    if let current = remainingRouteCoordinates.first {
      currentLocation = current
    }
    guard updatesManeuver else { return }

    if navigationProgress >= 1 {
      maneuver = .straight
      maneuverDistanceMeters = 0
      instruction = "已抵達推薦停車點"
      return
    }

    let totalStepDistance = routeSteps.reduce(0) { $0 + max(0, $1.distanceMeters) }
    guard totalStepDistance > 0, !routeSteps.isEmpty else {
      maneuver = .straight
      maneuverDistanceMeters = max(
        0,
        Int(((routeDistanceMeters ?? 0) * (1 - navigationProgress)).rounded())
      )
      instruction = "MKRoute 未提供逐步導航指示"
      return
    }

    let traveledStepDistance = totalStepDistance * navigationProgress
    var stepStartDistance: CLLocationDistance = 0
    for (index, step) in routeSteps.enumerated() {
      let stepEndDistance = stepStartDistance + max(0, step.distanceMeters)
      if traveledStepDistance < stepEndDistance || index == routeSteps.indices.last {
        maneuver = step.maneuver
        maneuverDistanceMeters = max(
          0,
          Int((stepEndDistance - traveledStepDistance).rounded())
        )
        instruction = step.instruction
        return
      }
      stepStartDistance = stepEndDistance
    }
  }

  var remainingRouteCoordinates: [CLLocationCoordinate2D] {
    guard routeCoordinates.count > 1 else { return routeCoordinates }

    let points = routeCoordinates.map(MKMapPoint.init)
    let segmentDistances = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
    let totalDistance = segmentDistances.reduce(0, +)
    guard totalDistance > 0 else { return routeCoordinates }

    let targetDistance = totalDistance * min(1, max(0, navigationProgress))
    var traversedDistance = 0.0

    for index in segmentDistances.indices {
      let segmentDistance = segmentDistances[index]
      let nextDistance = traversedDistance + segmentDistance
      if targetDistance <= nextDistance || index == segmentDistances.indices.last {
        let fraction = segmentDistance > 0
          ? min(1, max(0, (targetDistance - traversedDistance) / segmentDistance))
          : 0
        let start = points[index]
        let end = points[index + 1]
        let currentPoint = MKMapPoint(
          x: start.x + (end.x - start.x) * fraction,
          y: start.y + (end.y - start.y) * fraction
        )
        let nextCoordinateIndex = fraction >= 0.999_999 ? index + 2 : index + 1
        return [currentPoint.coordinate] + Array(routeCoordinates.dropFirst(nextCoordinateIndex))
      }
      traversedDistance = nextDistance
    }

    return routeCoordinates.last.map { [$0] } ?? []
  }

  var remainingRouteDistanceMeters: CLLocationDistance? {
    routeDistanceMeters.map { $0 * (1 - min(1, max(0, navigationProgress))) }
  }

  var remainingExpectedTravelTime: TimeInterval? {
    expectedTravelTime.map { $0 * (1 - min(1, max(0, navigationProgress))) }
  }

  var routePolyline: MKPolyline {
    let coordinates = remainingRouteCoordinates
    return MKPolyline(coordinates: coordinates, count: coordinates.count)
  }

  var navigationMapRect: MKMapRect {
    navigationMapRect(aspectRatio: 4 / 3)
  }

  func navigationMapRect(aspectRatio: CGFloat) -> MKMapRect {
    let metersPerPoint = MKMetersPerMapPointAtLatitude(currentLocation.latitude)
    let heightMeters = navigationProgress >= 0.85 ? 180.0 : 260.0
    let widthMeters = max(heightMeters, heightMeters * max(1, Double(aspectRatio)))
    let width = widthMeters / metersPerPoint
    let height = heightMeters / metersPerPoint
    let currentPoint = MKMapPoint(currentLocation)

    return MKMapRect(
      x: currentPoint.x - width / 2,
      y: currentPoint.y - height / 2,
      width: width,
      height: height
    )
  }

  var routeOverviewMapRect: MKMapRect {
    let coordinates = routeCoordinates + [
      NavigationDisplayState.sample.currentLocation,
      originalDestination,
      parkingLocation,
    ]
    guard let first = coordinates.first else { return .world }

    let firstPoint = MKMapPoint(first)
    var rect = MKMapRect(x: firstPoint.x, y: firstPoint.y, width: 1, height: 1)
    for coordinate in coordinates.dropFirst() {
      let point = MKMapPoint(coordinate)
      rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
    }

    let metersPerPoint = MKMetersPerMapPointAtLatitude(currentLocation.latitude)
    let padding = 400 / metersPerPoint
    return rect.insetBy(dx: -padding, dy: -padding)
  }
}
