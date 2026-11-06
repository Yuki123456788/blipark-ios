import Foundation

struct Destination: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  var name: String
  var address: String?
  var coordinate: GeoCoordinate
  var externalPlaceID: String?
  var sourceReference: String?

  init(
    id: UUID = UUID(),
    name: String,
    address: String? = nil,
    coordinate: GeoCoordinate,
    externalPlaceID: String? = nil,
    sourceReference: String? = nil
  ) {
    self.id = id
    self.name = name
    self.address = address
    self.coordinate = coordinate
    self.externalPlaceID = externalPlaceID
    self.sourceReference = sourceReference
  }
}

