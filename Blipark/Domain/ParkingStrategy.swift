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
  /// Width of the destination-centered square used to discover parking information.
  /// Optional so plans and preferences written before this field was introduced still decode.
  var informationRangeWidthMeters: Double?
  var sortingPreference: ParkingSortingPreference

  init(
    vehicleType: VehicleType,
    preferredParkingTypes: Set<ParkingType>,
    pricingPreference: PricingPreference,
    maximumStraightLineDistanceMeters: Double?,
    informationRangeWidthMeters: Double? = nil,
    sortingPreference: ParkingSortingPreference
  ) {
    self.vehicleType = vehicleType
    self.preferredParkingTypes = preferredParkingTypes
    self.pricingPreference = pricingPreference
    self.maximumStraightLineDistanceMeters = maximumStraightLineDistanceMeters
    self.informationRangeWidthMeters = informationRangeWidthMeters
    self.sortingPreference = sortingPreference
  }

  static let standard = ParkingStrategy(
    vehicleType: .car,
    preferredParkingTypes: Set(ParkingType.allCases),
    pricingPreference: .any,
    maximumStraightLineDistanceMeters: 800,
    informationRangeWidthMeters: nil,
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

