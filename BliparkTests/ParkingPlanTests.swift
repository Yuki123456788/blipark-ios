import XCTest
@testable import Blipark

final class ParkingPlanTests: XCTestCase {
  func testFreePreferenceDoesNotTreatUnknownAsFree() {
    let destination = Destination(name: "目的地", coordinate: coordinate)
    let free = location(name: "免費", charge: .free, latitudeOffset: 0.003)
    let unknown = location(name: "未知", charge: .unknown, latitudeOffset: 0.002)
    let paid = location(name: "收費", charge: .paid, latitudeOffset: 0.001)
    var strategy = ParkingStrategy.standard
    strategy.pricingPreference = .preferFree
    strategy.maximumStraightLineDistanceMeters = nil

    let result = ParkingRecommendationService()
      .recommend([paid, unknown, free], near: destination, using: strategy)

    XCTAssertEqual(result.map(\.location.name), ["免費", "未知", "收費"])
  }

  func testRecommendationFiltersVehicleAndStraightLineDistance() {
    let destination = Destination(name: "目的地", coordinate: coordinate)
    let nearbyCar = location(name: "汽車", charge: .paid, latitudeOffset: 0.001)
    let scooterOnly = ParkingLocation(
      name: "機車",
      type: .parkingLot,
      coordinate: coordinate,
      supportedVehicleTypes: [.scooter]
    )
    let distantCar = location(name: "太遠", charge: .paid, latitudeOffset: 0.02)
    var strategy = ParkingStrategy.standard
    strategy.maximumStraightLineDistanceMeters = 500

    let result = ParkingRecommendationService()
      .recommend([distantCar, scooterOnly, nearbyCar], near: destination, using: strategy)

    XCTAssertEqual(result.map(\.location.name), ["汽車"])
  }

  func testPlanSnapshotIsNotOverwrittenByDatasetUpdate() async throws {
    let directory = temporaryDirectory()
    let datasets = LocalTestDatasetRepository(directory: directory)
    let plans = LocalPlanRepository(directory: directory)
    let destination = Destination(name: "目的地", coordinate: coordinate)
    var original = location(name: "原始名稱", charge: .unknown, latitudeOffset: 0.001)
    try await datasets.save(TestDataset(destination: destination, parkingLocations: [original]))

    let plan = ParkingPlan(
      name: "測試計畫",
      destination: destination,
      vehicleType: .car,
      candidates: [ParkingCandidateSnapshot(location: original)],
      strategy: .standard,
      usesGlobalStrategy: true
    )
    try await plans.save(plan)

    original.name = "資料來源已更新"
    try await datasets.save(TestDataset(destination: destination, parkingLocations: [original]))

    let reloaded = try await plans.plan(id: plan.id)
    XCTAssertEqual(reloaded?.candidates.first?.name, "原始名稱")
  }

  func testPlansWithFutureDepartureSortBeforeRecentlyEditedUnscheduledPlans() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let destination = Destination(name: "目的地", coordinate: coordinate)
    let future = plan(
      name: "未來",
      destination: destination,
      departure: now.addingTimeInterval(3_600),
      updatedAt: now.addingTimeInterval(-10_000)
    )
    let recent = plan(
      name: "最近修改",
      destination: destination,
      departure: nil,
      updatedAt: now
    )

    XCTAssertEqual(ParkingPlanSorter.sorted([recent, future], now: now).map(\.name), ["未來", "最近修改"])
  }

  private var coordinate: GeoCoordinate {
    GeoCoordinate(latitude: 22.9908, longitude: 120.1996)
  }

  private func location(
    name: String,
    charge: ParkingCharge,
    latitudeOffset: Double
  ) -> ParkingLocation {
    ParkingLocation(
      name: name,
      type: .parkingLot,
      coordinate: GeoCoordinate(
        latitude: coordinate.latitude + latitudeOffset,
        longitude: coordinate.longitude
      ),
      charge: charge
    )
  }

  private func plan(
    name: String,
    destination: Destination,
    departure: Date?,
    updatedAt: Date
  ) -> ParkingPlan {
    ParkingPlan(
      name: name,
      destination: destination,
      vehicleType: .car,
      candidates: [],
      strategy: .standard,
      usesGlobalStrategy: true,
      scheduledDepartureAt: departure,
      createdAt: updatedAt,
      updatedAt: updatedAt
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("BliparkPlanTests-\(UUID().uuidString)", isDirectory: true)
  }
}

