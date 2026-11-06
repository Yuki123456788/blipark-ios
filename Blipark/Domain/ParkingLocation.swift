import Foundation

enum VehicleType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case car
  case scooter
  case heavyMotorcycle

  var id: String { rawValue }

  var title: String {
    switch self {
    case .car: "汽車"
    case .scooter: "機車"
    case .heavyMotorcycle: "大型重機"
    }
  }

  var symbolName: String {
    switch self {
    case .car: "car.fill"
    case .scooter: "scooter"
    case .heavyMotorcycle: "motorcycle.fill"
    }
  }
}

enum ParkingType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case parkingLot
  case onStreet

  var id: String { rawValue }

  var title: String {
    switch self {
    case .parkingLot: "停車場"
    case .onStreet: "路邊停車"
    }
  }

  var symbolName: String {
    switch self {
    case .parkingLot: "parkingsign.circle.fill"
    case .onStreet: "road.lanes"
    }
  }
}

enum ParkingCharge: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case free
  case paid
  case unknown

  var id: String { rawValue }

  var title: String {
    switch self {
    case .free: "免費"
    case .paid: "收費"
    case .unknown: "費率未知"
    }
  }
}

enum ParkingGeometry: Codable, Hashable, Sendable {
  case point(GeoCoordinate)
  case segment([GeoCoordinate])

  var representativeCoordinate: GeoCoordinate? {
    switch self {
    case .point(let coordinate): coordinate
    case .segment(let coordinates): coordinates.first
    }
  }
}

struct ParkingLocation: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var address: String?
  var type: ParkingType
  var geometry: ParkingGeometry
  var supportedVehicleTypes: Set<VehicleType>
  var totalSpaceCount: Int?
  var charge: ParkingCharge
  var pricingSummary: String?
  var notes: String?
  var sourceReference: String?

  init(
    id: UUID = UUID(),
    name: String,
    address: String? = nil,
    type: ParkingType,
    coordinate: GeoCoordinate,
    supportedVehicleTypes: Set<VehicleType> = [.car],
    totalSpaceCount: Int? = nil,
    charge: ParkingCharge = .unknown,
    pricingSummary: String? = nil,
    notes: String? = nil,
    sourceReference: String? = nil
  ) {
    self.id = id
    self.name = name
    self.address = address
    self.type = type
    geometry = .point(coordinate)
    self.supportedVehicleTypes = supportedVehicleTypes
    self.totalSpaceCount = totalSpaceCount
    self.charge = charge
    self.pricingSummary = pricingSummary
    self.notes = notes
    self.sourceReference = sourceReference
  }

  var coordinate: GeoCoordinate? { geometry.representativeCoordinate }
}

