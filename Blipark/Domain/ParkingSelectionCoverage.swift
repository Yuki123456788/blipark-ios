import MapKit

enum ParkingSelectionCoverage {
  static let widthMeters = 4_000.0

  static func mapRect(centeredAt center: GeoCoordinate) -> MKMapRect {
    let centerPoint = MKMapPoint(center.clLocationCoordinate)
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(center.latitude)
    let sideLength = widthMeters / metersPerMapPoint
    return MKMapRect(
      x: centerPoint.x - sideLength / 2,
      y: centerPoint.y - sideLength / 2,
      width: sideLength,
      height: sideLength
    )
  }

  static func contains(_ coordinate: GeoCoordinate, centeredAt center: GeoCoordinate) -> Bool {
    mapRect(centeredAt: center).contains(MKMapPoint(coordinate.clLocationCoordinate))
  }

  static func boundaryCoordinates(centeredAt center: GeoCoordinate) -> [CLLocationCoordinate2D] {
    let rect = mapRect(centeredAt: center)
    let topLeft = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
    let topRight = MKMapPoint(x: rect.maxX, y: rect.minY).coordinate
    let bottomRight = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
    let bottomLeft = MKMapPoint(x: rect.minX, y: rect.maxY).coordinate
    return [topLeft, topRight, bottomRight, bottomLeft, topLeft]
  }
}
