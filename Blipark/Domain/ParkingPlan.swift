import Foundation

struct ParkingCandidateSnapshot: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  var sourceParkingLocationID: UUID?
  var name: String
  var address: String?
  var type: ParkingType
  var coordinate: GeoCoordinate
  var supportedVehicleTypes: Set<VehicleType>
  var totalSpaceCount: Int?
  var charge: ParkingCharge
  var pricingSummary: String?
  var notes: String?

  init(location: ParkingLocation) {
    id = UUID()
    sourceParkingLocationID = location.id
    name = location.name
    address = location.address
    type = location.type
    coordinate = location.coordinate ?? GeoCoordinate(latitude: 0, longitude: 0)
    supportedVehicleTypes = location.supportedVehicleTypes
    totalSpaceCount = location.totalSpaceCount
    charge = location.charge
    pricingSummary = location.pricingSummary
    notes = location.notes
  }
}

struct ParkingPlan: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var destination: Destination
  var vehicleType: VehicleType
  var candidates: [ParkingCandidateSnapshot]
  var strategy: ParkingStrategy
  var usesGlobalStrategy: Bool
  var scheduledDepartureAt: Date?
  let createdAt: Date
  var updatedAt: Date
  var lastUsedAt: Date?

  init(
    id: UUID = UUID(),
    name: String,
    destination: Destination,
    vehicleType: VehicleType,
    candidates: [ParkingCandidateSnapshot],
    strategy: ParkingStrategy,
    usesGlobalStrategy: Bool,
    scheduledDepartureAt: Date? = nil,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    lastUsedAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.destination = destination
    self.vehicleType = vehicleType
    self.candidates = candidates
    self.strategy = strategy
    self.usesGlobalStrategy = usesGlobalStrategy
    self.scheduledDepartureAt = scheduledDepartureAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastUsedAt = lastUsedAt
  }
}

