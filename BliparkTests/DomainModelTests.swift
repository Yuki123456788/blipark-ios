import XCTest
@testable import Blipark

final class DomainModelTests: XCTestCase {
  func testCoordinateValidation() {
    XCTAssertTrue(GeoCoordinate(latitude: 22.9908, longitude: 120.1996).isValid)
    XCTAssertFalse(GeoCoordinate(latitude: 91, longitude: 120).isValid)
  }

  func testUnknownParkingChargeStaysUnknown() throws {
    let location = ParkingLocation(
      name: "測試停車場",
      type: .parkingLot,
      coordinate: GeoCoordinate(latitude: 22.99, longitude: 120.20)
    )

    let data = try JSONEncoder().encode(location)
    let decoded = try JSONDecoder().decode(ParkingLocation.self, from: data)

    XCTAssertEqual(decoded.charge, .unknown)
    XCTAssertNil(decoded.totalSpaceCount)
  }

  func testPlanSnapshotsCandidateData() {
    let location = ParkingLocation(
      name: "A 停車場",
      type: .parkingLot,
      coordinate: GeoCoordinate(latitude: 22.99, longitude: 120.20),
      totalSpaceCount: 30,
      charge: .paid
    )

    let snapshot = ParkingCandidateSnapshot(location: location)

    XCTAssertEqual(snapshot.sourceParkingLocationID, location.id)
    XCTAssertEqual(snapshot.name, location.name)
    XCTAssertEqual(snapshot.totalSpaceCount, 30)
  }
}

