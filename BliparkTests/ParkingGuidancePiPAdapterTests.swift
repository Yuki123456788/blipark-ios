import XCTest
@testable import Blipark

final class ParkingGuidancePiPAdapterTests: XCTestCase {
  func testAdapterPreservesRemainingCandidateOrderAndKinds() {
    let destination = Destination(
      name: "台南美術館",
      address: "台南市中西區",
      coordinate: GeoCoordinate(latitude: 22.991, longitude: 120.201)
    )
    let skipped = candidate(name: "已略過", type: .parkingLot, offset: 0.001)
    let street = candidate(name: "路邊停車", type: .onStreet, offset: 0.002)
    let lot = candidate(name: "地下停車場", type: .parkingLot, offset: 0.003)
    let session = ParkingGuidanceSession(
      id: UUID(),
      sourcePlanID: nil,
      destination: destination,
      orderedCandidates: [skipped, street, lot],
      currentCandidateIndex: 1,
      mode: .externalMaps(provider: .appleMaps),
      status: .preparing,
      startedAt: .now,
      updatedAt: .now
    )

    let payload = ParkingGuidancePiPAdapter.payload(for: session)

    XCTAssertEqual(payload.destination.name, destination.name)
    XCTAssertEqual(payload.parkingStops.map(\.id), [street.id, lot.id])
    XCTAssertEqual(payload.parkingStops.map(\.name), [street.name, lot.name])
    XCTAssertEqual(payload.parkingStops.map(\.kind), [.onStreet, .parkingLot])
    XCTAssertEqual(payload.parkingStops[0].coordinate.latitude, street.coordinate.latitude)
    XCTAssertEqual(payload.parkingStops[0].coordinate.longitude, street.coordinate.longitude)
  }

  private func candidate(
    name: String,
    type: ParkingType,
    offset: Double
  ) -> ParkingCandidateSnapshot {
    ParkingCandidateSnapshot(
      location: ParkingLocation(
        name: name,
        type: type,
        coordinate: GeoCoordinate(latitude: 22.991 + offset, longitude: 120.201)
      )
    )
  }
}
