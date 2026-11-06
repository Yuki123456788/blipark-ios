import Foundation

actor LocalPlanRepository: PlanRepository {
  private let store: JSONFileStore<[ParkingPlan]>

  init(directory: URL) {
    store = JSONFileStore(fileURL: directory.appendingPathComponent("plans-v1.json"))
  }

  func plans() async throws -> [ParkingPlan] {
    try await store.load(or: [])
  }

  func plan(id: UUID) async throws -> ParkingPlan? {
    try await plans().first { $0.id == id }
  }

  func save(_ plan: ParkingPlan) async throws {
    var values = try await plans()
    if let index = values.firstIndex(where: { $0.id == plan.id }) {
      values[index] = plan
    } else {
      values.append(plan)
    }
    try await store.save(values)
  }

  func delete(id: UUID) async throws {
    let values = try await plans().filter { $0.id != id }
    try await store.save(values)
  }
}

actor LocalPreferencesRepository: PreferencesRepository {
  private let store: JSONFileStore<AppPreferences>

  init(directory: URL) {
    store = JSONFileStore(fileURL: directory.appendingPathComponent("preferences-v1.json"))
  }

  func preferences() async throws -> AppPreferences {
    try await store.load(or: .standard)
  }

  func save(_ preferences: AppPreferences) async throws {
    try await store.save(preferences)
  }
}

actor LocalGuidanceSessionRepository: GuidanceSessionRepository {
  private let store: JSONFileStore<ParkingGuidanceSession?>

  init(directory: URL) {
    store = JSONFileStore(fileURL: directory.appendingPathComponent("active-session-v1.json"))
  }

  func activeSession() async throws -> ParkingGuidanceSession? {
    try await store.load(or: nil)
  }

  func save(_ session: ParkingGuidanceSession) async throws {
    try await store.save(session)
  }

  func clearActiveSession() async throws {
    try await store.save(nil)
  }
}

actor LocalTestDatasetRepository: TestDatasetRepository {
  private let store: JSONFileStore<[TestDataset]>
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(directory: URL) {
    store = JSONFileStore(fileURL: directory.appendingPathComponent("test-datasets-v1.json"))
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func datasets(includeDisabled: Bool) async throws -> [TestDataset] {
    let values = try await store.load(or: [])
    return includeDisabled ? values : values.filter(\.isEnabled)
  }

  func dataset(id: UUID) async throws -> TestDataset? {
    try await datasets(includeDisabled: true).first { $0.id == id }
  }

  func save(_ dataset: TestDataset) async throws {
    try TestDatasetValidator.validate(dataset)
    var values = try await datasets(includeDisabled: true)
    if let index = values.firstIndex(where: { $0.id == dataset.id }) {
      values[index] = dataset
    } else {
      values.append(dataset)
    }
    try await store.save(values)
  }

  func delete(id: UUID) async throws {
    let values = try await datasets(includeDisabled: true).filter { $0.id != id }
    try await store.save(values)
  }

  func exportArchive() async throws -> Data {
    let values = try await datasets(includeDisabled: true)
    return try encoder.encode(TestDatasetArchive(datasets: values))
  }

  func importArchive(_ data: Data) async throws {
    let archive: TestDatasetArchive
    do {
      archive = try decoder.decode(TestDatasetArchive.self, from: data)
    } catch {
      throw RepositoryError.invalidData("JSON 格式無法解析：\(error.localizedDescription)")
    }
    try TestDatasetValidator.validateArchive(archive)
    let existing = try await datasets(includeDisabled: true)
    let collisions = Set(existing.map(\.id)).intersection(archive.datasets.map(\.id))
    guard collisions.isEmpty else {
      throw RepositoryError.invalidData("匯入資料含有已存在的情境 ID，未覆蓋任何資料。")
    }
    try await store.save(existing + archive.datasets)
  }
}

actor LocalDeveloperSettingsRepository: DeveloperSettingsRepository {
  private let store: JSONFileStore<DeveloperNavigationSettings>

  init(directory: URL) {
    store = JSONFileStore(fileURL: directory.appendingPathComponent("developer-navigation-v1.json"))
  }

  func settings() async throws -> DeveloperNavigationSettings {
    try await store.load(or: .standard)
  }

  func save(_ settings: DeveloperNavigationSettings) async throws {
    try await store.save(settings)
  }
}

struct TestDatasetDestinationSearchProvider: DestinationSearchProviding {
  let repository: any TestDatasetRepository

  func searchDestinations(matching query: String) async throws -> [Destination] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return [] }
    return try await repository.datasets(includeDisabled: false)
      .map(\.destination)
      .filter {
        $0.name.localizedStandardContains(normalized)
          || ($0.address?.localizedStandardContains(normalized) == true)
      }
  }

  func destination(id: UUID) async throws -> Destination? {
    try await repository.datasets(includeDisabled: false)
      .map(\.destination)
      .first { $0.id == id }
  }
}

struct TestDatasetParkingDataProvider: ParkingDataProviding {
  let repository: any TestDatasetRepository

  func parkingLocations(near destination: Destination) async throws -> [ParkingLocation] {
    try await repository.datasets(includeDisabled: false)
      .first { $0.destination.id == destination.id }?
      .parkingLocations ?? []
  }

  func parkingLocation(id: UUID) async throws -> ParkingLocation? {
    try await repository.datasets(includeDisabled: false)
      .lazy
      .flatMap(\.parkingLocations)
      .first { $0.id == id }
  }
}

struct UnavailableDestinationSearchProvider: DestinationSearchProviding {
  func searchDestinations(matching query: String) async throws -> [Destination] { [] }
  func destination(id: UUID) async throws -> Destination? { nil }
}

struct UnavailableParkingDataProvider: ParkingDataProviding {
  func parkingLocations(near destination: Destination) async throws -> [ParkingLocation] { [] }
  func parkingLocation(id: UUID) async throws -> ParkingLocation? { nil }
}

