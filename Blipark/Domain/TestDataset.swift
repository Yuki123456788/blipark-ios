import Foundation

struct TestDataset: Codable, Hashable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  let id: UUID
  var schemaVersion: Int
  var destination: Destination
  var parkingLocations: [ParkingLocation]
  var notes: String?
  var isEnabled: Bool
  let createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    schemaVersion: Int = currentSchemaVersion,
    destination: Destination,
    parkingLocations: [ParkingLocation] = [],
    notes: String? = nil,
    isEnabled: Bool = true,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.destination = destination
    self.parkingLocations = parkingLocations
    self.notes = notes
    self.isEnabled = isEnabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

struct TestDatasetArchive: Codable, Sendable {
  let schemaVersion: Int
  let exportedAt: Date
  let datasets: [TestDataset]

  init(datasets: [TestDataset], exportedAt: Date = .now) {
    schemaVersion = TestDataset.currentSchemaVersion
    self.exportedAt = exportedAt
    self.datasets = datasets
  }
}

enum TestDatasetValidator {
  static func validate(_ dataset: TestDataset) throws {
    guard dataset.schemaVersion == TestDataset.currentSchemaVersion else {
      throw RepositoryError.invalidData("不支援的測試資料版本：\(dataset.schemaVersion)。")
    }
    guard !dataset.destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw RepositoryError.invalidData("目的地名稱不可留白。")
    }
    guard dataset.destination.coordinate.isValid else {
      throw RepositoryError.invalidData("目的地座標超出合法範圍。")
    }
    let locationIDs = dataset.parkingLocations.map(\.id)
    guard Set(locationIDs).count == locationIDs.count else {
      throw RepositoryError.invalidData("同一情境內有重複的停車點 ID。")
    }
    for location in dataset.parkingLocations {
      guard !location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw RepositoryError.invalidData("停車點名稱不可留白。")
      }
      guard let coordinate = location.coordinate, coordinate.isValid else {
        throw RepositoryError.invalidData("「\(location.name)」的座標超出合法範圍。")
      }
      if let count = location.totalSpaceCount, count < 0 {
        throw RepositoryError.invalidData("「\(location.name)」的總格位數不可小於 0。")
      }
      guard !location.supportedVehicleTypes.isEmpty else {
        throw RepositoryError.invalidData("「\(location.name)」至少要支援一種車種。")
      }
    }
  }

  static func validateArchive(_ archive: TestDatasetArchive) throws {
    guard archive.schemaVersion == TestDataset.currentSchemaVersion else {
      throw RepositoryError.invalidData("不支援的匯入版本：\(archive.schemaVersion)。")
    }
    let datasetIDs = archive.datasets.map(\.id)
    guard Set(datasetIDs).count == datasetIDs.count else {
      throw RepositoryError.invalidData("匯入檔內有重複的情境 ID。")
    }
    try archive.datasets.forEach(validate)
  }
}

