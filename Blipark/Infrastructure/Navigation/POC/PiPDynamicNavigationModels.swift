import CoreLocation
import Foundation

enum PiPDynamicRenderMode: String, CaseIterable, Identifiable {
  case singleSnapshot = "單張大圖"
  case tileGrid = "圖磚拼接"

  var id: String { rawValue }
}

enum PiPDynamicZoomMode: String, CaseIterable, Identifiable {
  case fixed = "固定縮放"
  case dynamic = "動態縮放"

  var id: String { rawValue }
}

enum PiPDynamicRoadEnvironment: String {
  case city
  case highway
}

enum PiPDynamicNavigationScenario: String, CaseIterable, Identifiable {
  case city = "一般市區行駛"
  case highway = "高速巡航"
  case highwayExit = "高速接近出口"
  case singleTurn = "一般路口轉彎"
  case consecutiveTurns = "連續轉彎"
  case destination = "接近目的地"
  case changingSpeed = "速度變化"

  var id: String { rawValue }

  var detail: String {
    switch self {
    case .city: "中速巡航，沿路保留數個一般轉彎。"
    case .highway: "以高速與較長前視距測試小視窗可讀性。"
    case .highwayExit: "先拉遠巡航，再於出口前平滑拉近。"
    case .singleTurn: "接近一個主要路口、完成轉彎後恢復巡航。"
    case .consecutiveTurns: "一次容納短距離內的三個轉向，避免逐次抽動。"
    case .destination: "隨剩餘距離縮短逐步顯示終點周邊細節。"
    case .changingSpeed: "依進度模擬 20 → 40 → 60 → 90 → 40 km/h。"
    }
  }

  var routeScenario: PiPNavigationScenario {
    switch self {
    case .highway, .highwayExit:
      PiPNavigationScenario.presets[0]
    case .city, .singleTurn, .consecutiveTurns, .destination, .changingSpeed:
      PiPNavigationScenario.presets[2]
    }
  }

  func sample(
    distanceMeters: CLLocationDistance,
    routeDistanceMeters: CLLocationDistance,
    selectedSpeedKmh: Double
  ) -> PiPDynamicScenarioSample {
    let total = max(routeDistanceMeters, 1)
    let distance = min(max(distanceMeters, 0), total)
    let progress = distance / total
    let remaining = max(0, total - distance)
    var speed = selectedSpeedKmh
    var road: PiPDynamicRoadEnvironment = .city
    var turns: [CLLocationDistance] = []

    switch self {
    case .city:
      turns = [0.30, 0.58, 0.78].map { $0 * total }
    case .highway:
      road = .highway
      speed = max(selectedSpeedKmh, 90)
    case .highwayExit:
      road = progress < 0.72 ? .highway : .city
      speed = progress < 0.60 ? max(selectedSpeedKmh, 90) : max(35, selectedSpeedKmh * 0.55)
      turns = [0.72 * total]
    case .singleTurn:
      turns = [0.52 * total]
    case .consecutiveTurns:
      turns = [0.38, 0.47, 0.56].map { $0 * total }
    case .destination:
      break
    case .changingSpeed:
      let speeds = [20.0, 40.0, 60.0, 90.0, 40.0]
      speed = speeds[min(Int(progress * Double(speeds.count)), speeds.count - 1)]
      road = speed >= 80 ? .highway : .city
      turns = [0.74 * total]
    }

    let upcoming = turns.filter { $0 >= distance }
    let nextTurn = upcoming.first.map { $0 - distance }
    let complexSpan: CLLocationDistance?
    if self == .consecutiveTurns,
      let first = turns.first,
      let last = turns.last,
      distance >= max(0, first - 500),
      distance <= last + 120
    {
      complexSpan = max(0, last - distance)
    } else {
      complexSpan = nil
    }

    return PiPDynamicScenarioSample(
      speedKmh: speed,
      roadEnvironment: road,
      nextTurnDistanceMeters: nextTurn,
      complexManeuverSpanMeters: complexSpan,
      remainingDistanceMeters: remaining,
      isDestinationFocused: self == .destination
    )
  }
}

struct PiPDynamicScenarioSample {
  let speedKmh: Double
  let roadEnvironment: PiPDynamicRoadEnvironment
  let nextTurnDistanceMeters: CLLocationDistance?
  let complexManeuverSpanMeters: CLLocationDistance?
  let remainingDistanceMeters: CLLocationDistance
  let isDestinationFocused: Bool
}

enum PiPDynamicCameraMode: String, Equatable {
  case fixed = "固定"
  case cruise = "市區巡航"
  case highway = "高速巡航"
  case turnApproach = "接近轉彎"
  case complexManeuver = "連續轉彎"
  case destinationApproach = "接近目的地"
  case arrived = "已到達"

  var priority: Int {
    switch self {
    case .fixed: 0
    case .cruise, .highway: 1
    case .turnApproach: 2
    case .complexManeuver: 3
    case .destinationApproach: 4
    case .arrived: 5
    }
  }
}

struct PiPDynamicCameraConfiguration: Equatable {
  var lookAheadSeconds = 25.0
  var safetyDistanceMeters = 140.0
  var responseDuration = 0.9
  var hysteresisRatio = 0.12
  var minimumStateDuration = 0.8
  var fixedLookAheadMeters = 500.0
  var cityMinimumLookAheadMeters = 300.0
  var turnMinimumLookAheadMeters = 160.0
  var destinationTriggerMeters = 400.0
  var turnTriggerSeconds = 18.0
  var pitchDegrees = 0.0
}

struct PiPDynamicCameraInput {
  let speedKmh: Double
  let roadEnvironment: PiPDynamicRoadEnvironment
  let nextTurnDistanceMeters: CLLocationDistance?
  let complexManeuverSpanMeters: CLLocationDistance?
  let remainingDistanceMeters: CLLocationDistance
  let isDestinationFocused: Bool
  let bearingDegrees: CLLocationDirection
}

struct PiPDynamicCameraState {
  let mode: PiPDynamicCameraMode
  let bearingDegrees: CLLocationDirection
  let metersPerPoint: CGFloat
  let currentLookAheadMeters: CLLocationDistance
  let targetLookAheadMeters: CLLocationDistance
  var pitchDegrees = 0.0
}

struct PiPDynamicCameraDebugSnapshot {
  let mode: PiPDynamicCameraMode
  let speedKmh: Double
  let nextTurnDistanceMeters: CLLocationDistance?
  let remainingDistanceMeters: CLLocationDistance
  let currentLookAheadMeters: CLLocationDistance
  let targetLookAheadMeters: CLLocationDistance
  let metersPerPoint: CGFloat

  static let empty = PiPDynamicCameraDebugSnapshot(
    mode: .fixed,
    speedKmh: 0,
    nextTurnDistanceMeters: nil,
    remainingDistanceMeters: 0,
    currentLookAheadMeters: 0,
    targetLookAheadMeters: 0,
    metersPerPoint: 0
  )
}
