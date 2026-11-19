import CoreLocation
import Foundation

struct GeoCoordinate: Codable, Hashable, Sendable {
  let latitude: Double
  let longitude: Double

  init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  var isValid: Bool {
    (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }

  var clLocationCoordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  func straightLineDistance(to other: GeoCoordinate) -> CLLocationDistance {
    CLLocation(latitude: latitude, longitude: longitude)
      .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
  }
}

