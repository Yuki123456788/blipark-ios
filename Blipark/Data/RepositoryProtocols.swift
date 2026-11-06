import Foundation

protocol DestinationSearchProviding: Sendable {
  func searchDestinations(matching query: String) async throws -> [Destination]
  func destination(id: UUID) async throws -> Destination?
}

protocol ParkingDataProviding: Sendable {
  func parkingLocations(near destination: Destination) async throws -> [ParkingLocation]
  func parkingLocation(id: UUID) async throws -> ParkingLocation?
}

protocol PlanRepository: Sendable {
  func plans() async throws -> [ParkingPlan]
  func plan(id: UUID) async throws -> ParkingPlan?
  func save(_ plan: ParkingPlan) async throws
  func delete(id: UUID) async throws
}

protocol PreferencesRepository: Sendable {
  func preferences() async throws -> AppPreferences
  func save(_ preferences: AppPreferences) async throws
}

protocol GuidanceSessionRepository: Sendable {
  func activeSession() async throws -> ParkingGuidanceSession?
  func save(_ session: ParkingGuidanceSession) async throws
  func clearActiveSession() async throws
}

enum RepositoryError: LocalizedError, Equatable {
  case invalidData(String)
  case notFound
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .invalidData(let message): message
    case .notFound: "找不到指定資料。"
    case .unavailable(let message): message
    }
  }
}

