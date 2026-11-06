import XCTest
@testable import Blipark

final class SearchAndExploreTests: XCTestCase {
  func testAppleMapsLinkParsesCoordinate() throws {
    let destination = try XCTUnwrap(
      ExternalMapLinkParser.parse(
        "https://maps.apple.com/?q=%E8%87%BA%E5%8D%97%E7%BE%8E%E8%A1%93%E9%A4%A8&ll=22.9908,120.1996"
      )
    )

    XCTAssertEqual(destination.coordinate.latitude, 22.9908, accuracy: 0.000_001)
    XCTAssertEqual(destination.coordinate.longitude, 120.1996, accuracy: 0.000_001)
  }

  func testAppleMapsPlaceLinkParsesCoordinateNameAndAddress() throws {
    let destination = try XCTUnwrap(
      ExternalMapLinkParser.parse(
        "https://maps.apple.com/place?coordinate=22.9908,120.1996&name=%E8%87%BA%E5%8D%97%E7%BE%8E%E8%A1%93%E9%A4%A8&address=%E5%8F%B0%E5%8D%97%E5%B8%82"
      )
    )

    XCTAssertEqual(destination.name, "臺南美術館")
    XCTAssertEqual(destination.address, "台南市")
    XCTAssertEqual(destination.coordinate.latitude, 22.9908, accuracy: 0.000_001)
  }

  func testGoogleMapsSelectedPlaceCoordinateParses() throws {
    let destination = try XCTUnwrap(
      ExternalMapLinkParser.parse(
        "https://www.google.com/maps/place/Test/data=!3d22.9912!4d120.2012"
      )
    )

    XCTAssertEqual(destination.coordinate.latitude, 22.9912, accuracy: 0.000_001)
    XCTAssertEqual(destination.coordinate.longitude, 120.2012, accuracy: 0.000_001)
  }

  func testAppleMapsPlaceIdentifierIsRecognized() throws {
    let url = try XCTUnwrap(URL(string: "https://maps.apple.com/place?place-id=I123456789"))

    XCTAssertEqual(ExternalMapLinkParser.applePlaceIdentifier(from: url), "I123456789")
  }

  func testGoogleShortLinkReturnsHonestError() {
    XCTAssertThrowsError(try ExternalMapLinkParser.parse("https://maps.app.goo.gl/abc")) { error in
      XCTAssertEqual(error as? ExternalMapLinkError, .shortenedLinkNeedsResolution)
    }
  }

  @MainActor
  func testExplorePreservesProviderOrderAndWaitsForManualSelection() async {
    let destination = Destination(name: "目的地", coordinate: coordinate)
    let near = ParkingLocation(
      name: "近路邊",
      type: .onStreet,
      coordinate: GeoCoordinate(latitude: 22.9910, longitude: 120.1996)
    )
    let far = ParkingLocation(
      name: "遠停車場",
      type: .parkingLot,
      coordinate: GeoCoordinate(latitude: 23.0010, longitude: 120.1996)
    )
    let model = DestinationExploreModel(
      destination: destination,
      provider: FixedParkingProvider(locations: [far, near])
    )

    await model.load()

    XCTAssertEqual(model.visibleLocations.map(\.location.name), ["遠停車場", "近路邊"])
    XCTAssertNil(model.selectedID)
  }

  private var coordinate: GeoCoordinate {
    GeoCoordinate(latitude: 22.9908, longitude: 120.1996)
  }
}

private struct FixedParkingProvider: ParkingDataProviding {
  let locations: [ParkingLocation]

  func parkingLocations(near destination: Destination) async throws -> [ParkingLocation] {
    locations
  }

  func parkingLocation(id: UUID) async throws -> ParkingLocation? {
    locations.first { $0.id == id }
  }
}

