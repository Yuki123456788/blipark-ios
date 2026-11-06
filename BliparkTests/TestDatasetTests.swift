import XCTest
@testable import Blipark

final class TestDatasetTests: XCTestCase {
  func testValidatorRejectsNegativeSpaceCount() {
    let dataset = makeDataset(
      locations: [
        ParkingLocation(
          name: "無效停車場",
          type: .parkingLot,
          coordinate: coordinate,
          totalSpaceCount: -1
        )
      ]
    )

    XCTAssertThrowsError(try TestDatasetValidator.validate(dataset))
  }

  func testRepositoryPersistsDataset() async throws {
    let directory = temporaryDirectory()
    let repository = LocalTestDatasetRepository(directory: directory)
    let dataset = makeDataset()

    try await repository.save(dataset)

    let reloaded = LocalTestDatasetRepository(directory: directory)
    let values = try await reloaded.datasets(includeDisabled: true)
    XCTAssertEqual(values, [dataset])
  }

  func testImportRejectsExistingDatasetIDWithoutOverwriting() async throws {
    let firstDirectory = temporaryDirectory()
    let secondDirectory = temporaryDirectory()
    let existingRepository = LocalTestDatasetRepository(directory: firstDirectory)
    let exportingRepository = LocalTestDatasetRepository(directory: secondDirectory)
    let dataset = makeDataset()
    try await existingRepository.save(dataset)
    try await exportingRepository.save(dataset)
    let archive = try await exportingRepository.exportArchive()

    do {
      try await existingRepository.importArchive(archive)
      XCTFail("Expected duplicate IDs to be rejected")
    } catch {
      let remaining = try await existingRepository.datasets(includeDisabled: true)
      XCTAssertEqual(remaining, [dataset])
    }
  }

  func testDeveloperNavigationDefaultsMatchApprovedConfiguration() {
    let settings = DeveloperNavigationSettings.standard
    XCTAssertEqual(settings.renderMode, .tileGrid)
    XCTAssertEqual(settings.tileGridSize, 5)
    XCTAssertEqual(settings.fixedLookAheadMeters, 80)
    XCTAssertEqual(settings.pipControlsStyle, 2)
  }

  private var coordinate: GeoCoordinate {
    GeoCoordinate(latitude: 22.9908, longitude: 120.1996)
  }

  private func makeDataset(locations: [ParkingLocation]? = nil) -> TestDataset {
    TestDataset(
      destination: Destination(name: "臺南美術館", coordinate: coordinate),
      parkingLocations: locations
        ?? [ParkingLocation(name: "美術館停車場", type: .parkingLot, coordinate: coordinate)]
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("BliparkTests-\(UUID().uuidString)", isDirectory: true)
  }
}

