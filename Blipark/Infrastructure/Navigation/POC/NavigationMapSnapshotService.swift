import MapKit
import UIKit

struct PiPNavigationMapAsset {
  let image: UIImage
  let routePoints: [CGPoint]
  let currentPoint: CGPoint
  let originalDestinationPoint: CGPoint?
  let parkingPoint: CGPoint?
  let cameraHeading: CLLocationDirection
  let navigationProgress: Double
  let isViewportCovered: Bool
  let vehicleRotationDegrees: CLLocationDirection?
  let showsVehicle: Bool

  init(
    image: UIImage,
    routePoints: [CGPoint],
    currentPoint: CGPoint,
    originalDestinationPoint: CGPoint?,
    parkingPoint: CGPoint?,
    cameraHeading: CLLocationDirection,
    navigationProgress: Double,
    isViewportCovered: Bool = true,
    vehicleRotationDegrees: CLLocationDirection? = nil,
    showsVehicle: Bool = true
  ) {
    self.image = image
    self.routePoints = routePoints
    self.currentPoint = currentPoint
    self.originalDestinationPoint = originalDestinationPoint
    self.parkingPoint = parkingPoint
    self.cameraHeading = cameraHeading
    self.navigationProgress = navigationProgress
    self.isViewportCovered = isViewportCovered
    self.vehicleRotationDegrees = vehicleRotationDegrees
    self.showsVehicle = showsVehicle
  }
}

@MainActor
enum NavigationMapSnapshotService {
  static func makeAsset(
    state: NavigationDisplayState,
    mode: NavigationDisplayMode,
    size: CGSize
  ) async throws -> PiPNavigationMapAsset {
    let options = MKMapSnapshotter.Options()
    let camera = cameraState(for: state, mode: mode)
    options.camera = MKMapCamera(
      lookingAtCenter: camera.centerCoordinate,
      fromDistance: camera.distance,
      pitch: camera.pitch,
      heading: camera.heading
    )
    options.size = size
    options.scale = 1
    let mapConfiguration = MKStandardMapConfiguration()
    mapConfiguration.elevationStyle = .flat
    options.preferredConfiguration = mapConfiguration

    let snapshot = try await MKMapSnapshotter(options: options).start()
    let renderedSize = snapshot.image.size
    return PiPNavigationMapAsset(
      image: snapshot.image,
      routePoints: state.remainingRouteCoordinates.map {
        normalized(snapshot.point(for: $0), in: renderedSize, clampsToBounds: false)
      },
      currentPoint: normalized(
        snapshot.point(for: state.currentLocation),
        in: renderedSize,
        clampsToBounds: false
      ),
      originalDestinationPoint: visibleNormalized(
        snapshot.point(for: state.originalDestination),
        in: renderedSize
      ),
      parkingPoint: visibleNormalized(
        snapshot.point(for: state.parkingLocation),
        in: renderedSize
      ),
      cameraHeading: camera.heading,
      navigationProgress: state.navigationProgress
    )
  }

  static func makeLiveActivityImage(
    state: NavigationDisplayState,
    size: CGSize = CGSize(width: 640, height: 240)
  ) async throws -> UIImage {
    let asset = try await makeAsset(state: state, mode: .fullMap, size: size)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true

    return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
      asset.image.draw(in: CGRect(origin: .zero, size: size))
      let context = rendererContext.cgContext

      let routePoints = asset.routePoints.map {
        CGPoint(x: $0.x * size.width, y: $0.y * size.height)
      }
      if let first = routePoints.first {
        let route = UIBezierPath()
        route.move(to: first)
        for point in routePoints.dropFirst() {
          route.addLine(to: point)
        }
        route.lineCapStyle = .round
        route.lineJoinStyle = .round
        UIColor.white.withAlphaComponent(0.85).setStroke()
        route.lineWidth = 14
        route.stroke()
        UIColor.systemCyan.setStroke()
        route.lineWidth = 8
        route.stroke()
      }

      drawMarker(
        at: CGPoint(x: asset.currentPoint.x * size.width, y: asset.currentPoint.y * size.height),
        fill: .systemBlue,
        in: context
      )
      if let parkingPoint = asset.parkingPoint {
        drawMarker(
          at: CGPoint(x: parkingPoint.x * size.width, y: parkingPoint.y * size.height),
          fill: .systemGreen,
          in: context
        )
      }
    }
  }

  struct CameraState {
    let centerCoordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let pitch: CGFloat
    let heading: CLLocationDirection
  }

  static func cameraState(
    for state: NavigationDisplayState,
    mode: NavigationDisplayMode
  ) -> CameraState {
    let route = state.remainingRouteCoordinates
    let headingTarget = coordinate(along: route, distanceMeters: 40) ?? state.currentLocation
    let centerDistance: CLLocationDistance = mode == .hybrid ? 48 : 58
    let center = coordinate(along: route, distanceMeters: centerDistance) ?? state.currentLocation
    let distance: CLLocationDistance = mode == .hybrid ? 285 : 320
    return CameraState(
      centerCoordinate: center,
      distance: state.navigationProgress >= 0.9 ? distance * 0.82 : distance,
      pitch: 25,
      heading: bearing(from: state.currentLocation, to: headingTarget)
    )
  }

  static func coordinate(
    along coordinates: [CLLocationCoordinate2D],
    distanceMeters: CLLocationDistance
  ) -> CLLocationCoordinate2D? {
    guard let first = coordinates.first else { return nil }
    guard coordinates.count > 1, distanceMeters > 0 else { return first }

    var remainingDistance = distanceMeters
    let points = coordinates.map(MKMapPoint.init)
    for (start, end) in zip(points, points.dropFirst()) {
      let segmentDistance = start.distance(to: end)
      if remainingDistance <= segmentDistance {
        let fraction = segmentDistance > 0 ? remainingDistance / segmentDistance : 0
        return MKMapPoint(
          x: start.x + (end.x - start.x) * fraction,
          y: start.y + (end.y - start.y) * fraction
        ).coordinate
      }
      remainingDistance -= segmentDistance
    }
    return coordinates.last
  }

  static func bearing(
    from start: CLLocationCoordinate2D,
    to end: CLLocationCoordinate2D
  ) -> CLLocationDirection {
    let latitude1 = start.latitude * .pi / 180
    let latitude2 = end.latitude * .pi / 180
    let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
    let y = sin(longitudeDelta) * cos(latitude2)
    let x = cos(latitude1) * sin(latitude2)
      - sin(latitude1) * cos(latitude2) * cos(longitudeDelta)
    guard abs(x) > .ulpOfOne || abs(y) > .ulpOfOne else { return 0 }
    return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
  }

  private static func normalized(
    _ point: CGPoint,
    in size: CGSize,
    clampsToBounds: Bool
  ) -> CGPoint {
    let x = point.x / max(size.width, 1)
    let y = point.y / max(size.height, 1)
    return CGPoint(
      x: clampsToBounds ? min(1, max(0, x)) : x,
      y: clampsToBounds ? min(1, max(0, y)) : y
    )
  }

  private static func visibleNormalized(_ point: CGPoint, in size: CGSize) -> CGPoint? {
    guard CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1).contains(point) else {
      return nil
    }
    return normalized(point, in: size, clampsToBounds: true)
  }

  private static func drawMarker(at point: CGPoint, fill: UIColor, in context: CGContext) {
    let radius: CGFloat = 12
    let rect = CGRect(
      x: point.x - radius,
      y: point.y - radius,
      width: radius * 2,
      height: radius * 2
    )
    context.setFillColor(fill.cgColor)
    context.fillEllipse(in: rect)
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(4)
    context.strokeEllipse(in: rect)
  }
}
