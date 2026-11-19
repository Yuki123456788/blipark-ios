import Foundation

struct ParkingRecommendation: Identifiable, Equatable {
  let location: ParkingLocation
  let straightLineDistanceMeters: Double
  var id: UUID { location.id }
}

struct ParkingRecommendationService {
  func recommend(
    _ locations: [ParkingLocation],
    near destination: Destination,
    using strategy: ParkingStrategy
  ) -> [ParkingRecommendation] {
    locations.compactMap { location -> ParkingRecommendation? in
      guard location.supportedVehicleTypes.contains(strategy.vehicleType),
        strategy.preferredParkingTypes.isEmpty
          || strategy.preferredParkingTypes.contains(location.type),
        let coordinate = location.coordinate
      else { return nil }
      let distance = destination.coordinate.straightLineDistance(to: coordinate)
      if let maximum = strategy.maximumStraightLineDistanceMeters, distance > maximum {
        return nil
      }
      return ParkingRecommendation(location: location, straightLineDistanceMeters: distance)
    }
    .sorted { lhs, rhs in
      if strategy.sortingPreference == .preferenceThenDistance {
        let leftPrice = pricingRank(lhs.location.charge, preference: strategy.pricingPreference)
        let rightPrice = pricingRank(rhs.location.charge, preference: strategy.pricingPreference)
        if leftPrice != rightPrice { return leftPrice < rightPrice }
      }
      if lhs.straightLineDistanceMeters != rhs.straightLineDistanceMeters {
        return lhs.straightLineDistanceMeters < rhs.straightLineDistanceMeters
      }
      return lhs.location.id.uuidString < rhs.location.id.uuidString
    }
  }

  private func pricingRank(_ charge: ParkingCharge, preference: PricingPreference) -> Int {
    guard preference == .preferFree else { return 0 }
    switch charge {
    case .free: return 0
    case .unknown: return 1
    case .paid: return 2
    }
  }
}

enum ParkingPlanSorter {
  static func sorted(_ plans: [ParkingPlan], now: Date = .now) -> [ParkingPlan] {
    plans.sorted { lhs, rhs in
      let leftFuture = lhs.scheduledDepartureAt.map { $0 >= now } == true
      let rightFuture = rhs.scheduledDepartureAt.map { $0 >= now } == true
      if leftFuture != rightFuture { return leftFuture }
      if leftFuture, let leftDate = lhs.scheduledDepartureAt, let rightDate = rhs.scheduledDepartureAt,
        leftDate != rightDate
      {
        return leftDate < rightDate
      }
      let leftRecent = lhs.lastUsedAt ?? lhs.updatedAt
      let rightRecent = rhs.lastUsedAt ?? rhs.updatedAt
      if leftRecent != rightRecent { return leftRecent > rightRecent }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
}

extension ParkingStrategy {
  var conciseSummary: String {
    let types = preferredParkingTypes.count == ParkingType.allCases.count
      ? "不限類型"
      : preferredParkingTypes.map(\.title).sorted().joined(separator: "、")
    let distance = maximumStraightLineDistanceMeters.map { "直線 \(Int($0)) m 內" } ?? "不限距離"
    return "\(types)・\(pricingPreference.title)・\(distance)"
  }
}

