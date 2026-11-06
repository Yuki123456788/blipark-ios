import Foundation

enum PricingPreference: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case any
  case preferFree

  var id: String { rawValue }

  var title: String {
    switch self {
    case .any: "不限定收費方式"
    case .preferFree: "優先免費"
    }
  }
}

enum ParkingSortingPreference: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case preferenceThenDistance
  case distance

  var id: String { rawValue }

  var title: String {
    switch self {
    case .preferenceThenDistance: "符合偏好優先"
    case .distance: "距離優先"
    }
  }
}

struct ParkingStrategy: Codable, Hashable, Sendable {
  var vehicleType: VehicleType
  var preferredParkingTypes: Set<ParkingType>
  var pricingPreference: PricingPreference
  var maximumStraightLineDistanceMeters: Double?
  var sortingPreference: ParkingSortingPreference

  static let standard = ParkingStrategy(
    vehicleType: .car,
    preferredParkingTypes: Set(ParkingType.allCases),
    pricingPreference: .any,
    maximumStraightLineDistanceMeters: 800,
    sortingPreference: .preferenceThenDistance
  )
}

struct AppPreferences: Codable, Equatable, Sendable {
  var guidanceTriggerDistanceMeters: Double
  var globalParkingStrategy: ParkingStrategy

  static let standard = AppPreferences(
    guidanceTriggerDistanceMeters: 2_000,
    globalParkingStrategy: .standard
  )
}

