import Foundation

enum NavigationMapRenderMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case singleSnapshot
  case tileGrid

  var id: String { rawValue }
  var title: String { self == .singleSnapshot ? "單張大圖" : "圖磚拼接" }
}

enum NavigationZoomMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case fixed
  case dynamic

  var id: String { rawValue }
  var title: String { self == .fixed ? "固定視角" : "動態縮放" }
}

struct DeveloperNavigationSettings: Codable, Equatable, Sendable {
  var renderMode: NavigationMapRenderMode
  var tileGridSize: Int
  var zoomMode: NavigationZoomMode
  var fixedLookAheadMeters: Double
  var locationDistanceFilterMeters: Double
  var positionPredictionLimitSeconds: Double
  var maximumHorizontalAccuracyMeters: Double
  var offRouteThresholdMeters: Double
  var nextRoutePreviewDistanceMeters: Double
  var pitchDegrees: Double
  var pipControlsStyle: Int
  var showsTileBoundaries: Bool

  static let standard = DeveloperNavigationSettings(
    renderMode: .tileGrid,
    tileGridSize: 5,
    zoomMode: .fixed,
    fixedLookAheadMeters: 80,
    locationDistanceFilterMeters: 10,
    positionPredictionLimitSeconds: 2,
    maximumHorizontalAccuracyMeters: 100,
    offRouteThresholdMeters: 75,
    nextRoutePreviewDistanceMeters: 120,
    pitchDegrees: 35,
    pipControlsStyle: 2,
    showsTileBoundaries: false
  )
}

