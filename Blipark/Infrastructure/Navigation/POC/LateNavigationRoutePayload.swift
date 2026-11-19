import CoreLocation
import Foundation

/// Compatibility value used by the POC renderer's legacy route-state adapter.
/// The production launch path feeds prepared MapKit routes directly.
struct LateNavigationRoutePayload {
  let identifier: String
  let sourceCoordinate: CLLocationCoordinate2D
  let destinationCoordinate: CLLocationCoordinate2D
  let routeCoordinates: [CLLocationCoordinate2D]
  let routeSteps: [NavigationRouteStep]
  let distanceMeters: CLLocationDistance?
  let expectedTravelTime: TimeInterval?
  let generatedAt: Date
}
