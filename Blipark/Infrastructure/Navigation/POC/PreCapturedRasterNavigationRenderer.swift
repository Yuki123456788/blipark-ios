import MapKit
import UIKit

struct PreCapturedRasterProjection: @unchecked Sendable {
  let mapRect: MKMapRect
  let imageSize: CGSize
  private let imageOrigin: CGPoint
  private let imageXAxis: CGVector
  private let imageYAxis: CGVector

  var projectedMapRectWidthPixels: CGFloat {
    max(hypot(imageXAxis.dx, imageXAxis.dy), .ulpOfOne)
  }

  init(
    mapRect: MKMapRect,
    imageSize: CGSize,
    imageOrigin: CGPoint,
    imageXAxis: CGVector,
    imageYAxis: CGVector
  ) {
    self.mapRect = mapRect
    self.imageSize = imageSize
    self.imageOrigin = imageOrigin
    self.imageXAxis = imageXAxis
    self.imageYAxis = imageYAxis
  }

  init(mapRect: MKMapRect, imageSize: CGSize) {
    self.init(
      mapRect: mapRect,
      imageSize: imageSize,
      imageOrigin: .zero,
      imageXAxis: CGVector(dx: imageSize.width, dy: 0),
      imageYAxis: CGVector(dx: 0, dy: imageSize.height)
    )
  }

  @MainActor
  init(snapshot: MKMapSnapshotter.Snapshot, requestedMapRect: MKMapRect) {
    let image = snapshot.image
    let imageSize = CGSize(
      width: image.cgImage?.width ?? Int(image.size.width * image.scale),
      height: image.cgImage?.height ?? Int(image.size.height * image.scale)
    )
    let pointScale = CGSize(
      width: imageSize.width / max(image.size.width, 1),
      height: imageSize.height / max(image.size.height, 1)
    )
    func nativeImagePoint(_ mapPoint: MKMapPoint) -> CGPoint {
      let point = snapshot.point(for: mapPoint.coordinate)
      return CGPoint(x: point.x * pointScale.width, y: point.y * pointScale.height)
    }

    let topLeft = MKMapPoint(x: requestedMapRect.minX, y: requestedMapRect.minY)
    let topRight = MKMapPoint(x: requestedMapRect.maxX, y: requestedMapRect.minY)
    let bottomLeft = MKMapPoint(x: requestedMapRect.minX, y: requestedMapRect.maxY)
    let origin = nativeImagePoint(topLeft)
    let right = nativeImagePoint(topRight)
    let bottom = nativeImagePoint(bottomLeft)
    self.init(
      mapRect: requestedMapRect,
      imageSize: imageSize,
      imageOrigin: origin,
      imageXAxis: CGVector(dx: right.x - origin.x, dy: right.y - origin.y),
      imageYAxis: CGVector(dx: bottom.x - origin.x, dy: bottom.y - origin.y)
    )
  }

  func imagePoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    let point = MKMapPoint(coordinate)
    let horizontal = (point.x - mapRect.minX) / max(mapRect.width, .ulpOfOne)
    let vertical = (point.y - mapRect.minY) / max(mapRect.height, .ulpOfOne)
    return CGPoint(
      x: imageOrigin.x + horizontal * imageXAxis.dx + vertical * imageYAxis.dx,
      y: imageOrigin.y + horizontal * imageXAxis.dy + vertical * imageYAxis.dy
    )
  }

  func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
    let point = imagePoint(for: coordinate)
    return point.x >= 0 && point.x <= imageSize.width
      && point.y >= 0 && point.y <= imageSize.height
  }
}

struct PreCapturedRasterMapAsset {
  let image: UIImage
  let mapRect: MKMapRect
  let projection: PreCapturedRasterProjection
  let geographicWidthMeters: CLLocationDistance
  let hidesPointsOfInterest: Bool
  let capturedAt: Date

  var estimatedDecodedBytes: Int {
    let width = image.cgImage?.width ?? Int(image.size.width * image.scale)
    let height = image.cgImage?.height ?? Int(image.size.height * image.scale)
    return width * height * 4
  }
}

@MainActor
enum PreCapturedRasterNavigationRenderer {
  static func capture(
    center: CLLocationCoordinate2D,
    widthMeters: CLLocationDistance,
    pixelSize: CGSize,
    hidesPointsOfInterest: Bool
  ) async throws -> PreCapturedRasterMapAsset {
    let mapRect = sourceMapRect(
      center: center,
      widthMeters: widthMeters,
      aspectRatio: Double(pixelSize.width / max(pixelSize.height, 1))
    )
    let options = MKMapSnapshotter.Options()
    options.mapRect = mapRect
    options.size = pixelSize
    options.scale = 1
    let mapConfiguration = MKStandardMapConfiguration()
    mapConfiguration.elevationStyle = .flat
    mapConfiguration.showsTraffic = false
    mapConfiguration.pointOfInterestFilter = hidesPointsOfInterest ? .excludingAll : .includingAll
    options.preferredConfiguration = mapConfiguration

    let snapshot = try await MKMapSnapshotter(options: options).start()
    return PreCapturedRasterMapAsset(
      image: snapshot.image,
      mapRect: mapRect,
      projection: PreCapturedRasterProjection(
        snapshot: snapshot,
        requestedMapRect: mapRect
      ),
      geographicWidthMeters: widthMeters,
      hidesPointsOfInterest: hidesPointsOfInterest,
      capturedAt: Date()
    )
  }

  static func render(
    source: PreCapturedRasterMapAsset,
    state: NavigationDisplayState,
    mode: NavigationDisplayMode,
    viewportWidthMeters: CLLocationDistance,
    outputSize: CGSize,
    followsVehicleHeading: Bool
  ) -> PiPNavigationMapAsset {
    let remainingRoute = state.remainingRouteCoordinates
    let hasRoute = remainingRoute.count > 1
    let headingTarget = NavigationMapSnapshotService.coordinate(
      along: remainingRoute,
      distanceMeters: 40
    ) ?? state.currentLocation
    let vehicleHeading = hasRoute
      ? NavigationMapSnapshotService.bearing(
        from: state.currentLocation,
        to: headingTarget
      )
      : 0
    let cameraHeading = followsVehicleHeading ? vehicleHeading : 0
    let centerDistance: CLLocationDistance = mode == .hybrid ? 48 : 58
    let cameraCenter = hasRoute
      ? NavigationMapSnapshotService.coordinate(
        along: remainingRoute,
        distanceMeters: centerDistance
      ) ?? state.currentLocation
      : state.originalDestination
    let effectiveViewportWidth = state.navigationProgress >= 0.9
      ? viewportWidthMeters * 0.82
      : viewportWidthMeters

    let background = renderBackground(
      source: source,
      cameraCenter: cameraCenter,
      headingDegrees: cameraHeading,
      viewportWidthMeters: effectiveViewportWidth,
      outputSize: outputSize
    )
    let projection = Projection(
      cameraCenter: cameraCenter,
      headingDegrees: cameraHeading,
      viewportWidthMeters: effectiveViewportWidth,
      outputSize: outputSize
    )
    let routePoints = remainingRoute.map { projection.normalizedPoint(for: $0) }
    let currentPoint = projection.normalizedPoint(for: state.currentLocation)
    let parkingPoint = hasRoute
      ? visible(projection.normalizedPoint(for: state.parkingLocation))
      : nil

    return PiPNavigationMapAsset(
      image: background,
      routePoints: routePoints,
      currentPoint: currentPoint,
      originalDestinationPoint: visible(
        projection.normalizedPoint(for: state.originalDestination)
      ),
      parkingPoint: parkingPoint,
      cameraHeading: cameraHeading,
      navigationProgress: state.navigationProgress,
      isViewportCovered: projection.viewportIsCovered(by: source.mapRect),
      vehicleRotationDegrees: vehicleHeading - cameraHeading,
      showsVehicle: hasRoute
    )
  }

  nonisolated static func sourceMapRect(
    center: CLLocationCoordinate2D,
    widthMeters: CLLocationDistance,
    aspectRatio: Double
  ) -> MKMapRect {
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(center.latitude)
    let width = widthMeters / metersPerMapPoint
    let height = width / max(aspectRatio, 0.01)
    let centerPoint = MKMapPoint(center)
    return MKMapRect(
      x: centerPoint.x - width / 2,
      y: centerPoint.y - height / 2,
      width: width,
      height: height
    )
  }

  struct Projection {
    let cameraCenter: CLLocationCoordinate2D
    let headingDegrees: CLLocationDirection
    let viewportWidthMeters: CLLocationDistance
    let outputSize: CGSize

    private var cameraPoint: MKMapPoint { MKMapPoint(cameraCenter) }

    private var mapPointsPerOutputPixel: Double {
      let metersPerMapPoint = MKMetersPerMapPointAtLatitude(cameraCenter.latitude)
      return viewportWidthMeters / metersPerMapPoint / max(outputSize.width, 1)
    }

    func normalizedPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
      let point = MKMapPoint(coordinate)
      let deltaX = point.x - cameraPoint.x
      let deltaY = point.y - cameraPoint.y
      let radians = headingDegrees * .pi / 180
      let rotatedX = cos(radians) * deltaX + sin(radians) * deltaY
      let rotatedY = -sin(radians) * deltaX + cos(radians) * deltaY
      return CGPoint(
        x: 0.5 + rotatedX / mapPointsPerOutputPixel / max(outputSize.width, 1),
        y: 0.5 + rotatedY / mapPointsPerOutputPixel / max(outputSize.height, 1)
      )
    }

    func viewportIsCovered(by sourceRect: MKMapRect) -> Bool {
      viewportCornerMapPoints.allSatisfy(sourceRect.contains)
    }

    private var viewportCornerMapPoints: [MKMapPoint] {
      let halfWidth = Double(outputSize.width) * mapPointsPerOutputPixel / 2
      let halfHeight = Double(outputSize.height) * mapPointsPerOutputPixel / 2
      let radians = headingDegrees * .pi / 180
      return [
        (-halfWidth, -halfHeight),
        (halfWidth, -halfHeight),
        (halfWidth, halfHeight),
        (-halfWidth, halfHeight),
      ].map { rotatedX, rotatedY in
        let deltaX = cos(radians) * rotatedX - sin(radians) * rotatedY
        let deltaY = sin(radians) * rotatedX + cos(radians) * rotatedY
        return MKMapPoint(x: cameraPoint.x + deltaX, y: cameraPoint.y + deltaY)
      }
    }
  }

  private static func renderBackground(
    source: PreCapturedRasterMapAsset,
    cameraCenter: CLLocationCoordinate2D,
    headingDegrees: CLLocationDirection,
    viewportWidthMeters: CLLocationDistance,
    outputSize: CGSize
  ) -> UIImage {
    let sourceSize = source.image.size
    let cameraPoint = MKMapPoint(cameraCenter)
    let cameraPixel = CGPoint(
      x: (cameraPoint.x - source.mapRect.minX) / source.mapRect.width * sourceSize.width,
      y: (cameraPoint.y - source.mapRect.minY) / source.mapRect.height * sourceSize.height
    )
    let sourcePixelsPerMapPoint = sourceSize.width / source.mapRect.width
    let viewportMapPointWidth = viewportWidthMeters
      / MKMetersPerMapPointAtLatitude(cameraCenter.latitude)
    let outputPixelsPerMapPoint = outputSize.width / viewportMapPointWidth
    let scale = outputPixelsPerMapPoint / sourcePixelsPerMapPoint
    let radians = headingDegrees * .pi / 180

    var transform = CGAffineTransform(
      translationX: outputSize.width / 2,
      y: outputSize.height / 2
    )
    transform = transform.rotated(by: -radians)
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -cameraPixel.x, y: -cameraPixel.y)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: outputSize, format: format).image { rendererContext in
      UIColor.black.setFill()
      UIRectFill(CGRect(origin: .zero, size: outputSize))
      rendererContext.cgContext.concatenate(transform)
      source.image.draw(at: .zero)
    }
  }

  private static func visible(_ point: CGPoint) -> CGPoint? {
    let bounds = CGRect(x: -0.02, y: -0.02, width: 1.04, height: 1.04)
    return bounds.contains(point) ? point : nil
  }
}
