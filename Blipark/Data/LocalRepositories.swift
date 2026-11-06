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

struct UnavailableDestinationSearchProvider: DestinationSearchProviding {
  func searchDestinations(matching query: String) async throws -> [Destination] { [] }
  func destination(id: UUID) async throws -> Destination? { nil }
}

struct UnavailableParkingDataProvider: ParkingDataProviding {
  func parkingLocations(near destination: Destination) async throws -> [ParkingLocation] { [] }
  func parkingLocation(id: UUID) async throws -> ParkingLocation? { nil }
}

