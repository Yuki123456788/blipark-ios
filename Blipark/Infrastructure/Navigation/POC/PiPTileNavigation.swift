import CoreGraphics
import MapKit
import UIKit

enum PiPTileNavigationGridPreset: Int, CaseIterable, Identifiable, Sendable {
  case two = 2
  case three = 3
  case four = 4
  case five = 5

  var id: Int { rawValue }
  var title: String { "\(rawValue) × \(rawValue)" }
  var tileCount: Int { rawValue * rawValue }

  var configuration: PiPTileNavigationConfiguration {
    PiPTileNavigationConfiguration(
      columns: rawValue,
      rows: rawValue,
      tilePixelSize: CGSize(width: 2_048, height: 1_152),
      coverageWidthMeters: 4_000,
      seamBleedPixels: 0.75
    )
  }
}

struct PiPTileNavigationConfiguration: Equatable, Sendable {
  static let standard = PiPTileNavigationGridPreset.three.configuration

  let columns: Int
  let rows: Int
  let tilePixelSize: CGSize
  let coverageWidthMeters: CLLocationDistance
  let seamBleedPixels: CGFloat

  var tileCount: Int { columns * rows }
  var canvasPixelSize: CGSize {
    CGSize(
      width: tilePixelSize.width * CGFloat(columns),
      height: tilePixelSize.height * CGFloat(rows)
    )
  }

  var estimatedDecodedBytes: Int {
    Int(tilePixelSize.width * tilePixelSize.height) * tileCount * 4
  }

  var sourceMetersPerPixel: Double {
    coverageWidthMeters / Double(max(canvasPixelSize.width, 1))
  }

  var densityComparedWithSingleSnapshot: Double {
    Double(canvasPixelSize.width / PiPNavigationRoutePreparationService.snapshotSize.width)
  }
}

struct PiPTileNavigationPreparationProgress: Equatable {
  let completed: Int
  let succeeded: Int
  let failed: Int
  let total: Int
  let message: String
}

struct PiPTileNavigationTile: @unchecked Sendable, Identifiable {
  var id: Int { row * 100 + column }
  let row: Int
  let column: Int
  let image: CGImage
  let mapRect: MKMapRect
  let canvasRect: CGRect
  let calibrationErrorPixels: CGFloat

  var label: String { "\(row + 1),\(column + 1)" }
}

final class PiPTileNavigationMapSource: PiPNavigationProjectionSource, @unchecked Sendable {
  let configuration: PiPTileNavigationConfiguration
  let mapRect: MKMapRect
  let tiles: [PiPTileNavigationTile]
  let center: CLLocationCoordinate2D
  let captureDuration: TimeInterval

  var fallbackImage: CGImage { tiles[tiles.count / 2].image }
  var metersPerPixel: CGFloat {
    CGFloat(configuration.coverageWidthMeters) / configuration.canvasPixelSize.width
  }
  var estimatedDecodedBytes: Int {
    tiles.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
  }
  var maximumCalibrationErrorPixels: CGFloat {
    tiles.map(\.calibrationErrorPixels).max() ?? 0
  }

  init(
    configuration: PiPTileNavigationConfiguration,
    mapRect: MKMapRect,
    tiles: [PiPTileNavigationTile],
    center: CLLocationCoordinate2D,
    captureDuration: TimeInterval
  ) {
    precondition(tiles.count == configuration.tileCount)
    self.configuration = configuration
    self.mapRect = mapRect
    self.tiles = tiles
    self.center = center
    self.captureDuration = captureDuration
  }

  func imagePoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    let point = MKMapPoint(coordinate)
    return CGPoint(
      x: (point.x - mapRect.minX) / mapRect.width * configuration.canvasPixelSize.width,
      y: (point.y - mapRect.minY) / mapRect.height * configuration.canvasPixelSize.height
    )
  }

  func contains(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
    coordinates.allSatisfy { mapRect.contains(MKMapPoint($0)) }
  }

  func visibleTiles(cameraTransform: CGAffineTransform, outputSize: CGSize)
    -> [PiPTileNavigationTile]
  {
    guard cameraTransform.isInvertible else { return tiles }
    let inverse = cameraTransform.inverted()
    let outputCorners = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: outputSize.width, y: 0),
      CGPoint(x: outputSize.width, y: outputSize.height),
      CGPoint(x: 0, y: outputSize.height),
    ].map { $0.applying(inverse) }
    let visibleBounds = outputCorners.reduce(CGRect.null) { bounds, point in
      bounds.union(CGRect(origin: point, size: .zero))
    }
    return tiles.filter { $0.canvasRect.intersects(visibleBounds) }
  }
}

enum PiPTileNavigationError: LocalizedError {
  case incompleteCapture(failed: Int, details: String)
  case missingImage(Int)
  case invalidSnapshotGeometry(Int)

  var errorDescription: String? {
    switch self {
    case .incompleteCapture(let failed, let details):
      "有 \(failed) 張圖磚擷取失敗。\(details)"
    case .missingImage(let index):
      "第 \(index) 張 MapKit Snapshot 沒有 CGImage。"
    case .invalidSnapshotGeometry(let index):
      "第 \(index) 張圖磚的 Snapshot 座標校正範圍無效。"
    }
  }
}

@MainActor
enum PiPTileNavigationSnapshotService {
  typealias ProgressHandler = (PiPTileNavigationPreparationProgress) -> Void

  static func capture(
    center: CLLocationCoordinate2D,
    configuration: PiPTileNavigationConfiguration = .standard,
    progress: ProgressHandler
  ) async throws -> PiPTileNavigationMapSource {
    let canvasSize = configuration.canvasPixelSize
    let coverageRect = PreCapturedRasterNavigationRenderer.sourceMapRect(
      center: center,
      widthMeters: configuration.coverageWidthMeters,
      aspectRatio: Double(canvasSize.width / max(canvasSize.height, 1))
    )
    let tileMapWidth = coverageRect.width / Double(configuration.columns)
    let tileMapHeight = coverageRect.height / Double(configuration.rows)
    let startedAt = Date()
    var tiles: [PiPTileNavigationTile] = []
    var failures: [String] = []

    for row in 0..<configuration.rows {
      for column in 0..<configuration.columns {
        try Task.checkCancellation()
        let index = row * configuration.columns + column + 1
        progress(
          PiPTileNavigationPreparationProgress(
            completed: tiles.count + failures.count,
            succeeded: tiles.count,
            failed: failures.count,
            total: configuration.tileCount,
            message: "正在擷取圖磚 \(index)/\(configuration.tileCount)"
          )
        )
        let tileRect = MKMapRect(
          x: coverageRect.minX + Double(column) * tileMapWidth,
          y: coverageRect.minY + Double(row) * tileMapHeight,
          width: tileMapWidth,
          height: tileMapHeight
        )
        do {
          let tile = try await captureTile(
            row: row,
            column: column,
            index: index,
            mapRect: tileRect,
            configuration: configuration
          )
          tiles.append(tile)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          failures.append("#\(index): \(error.localizedDescription)")
        }
      }
    }

    progress(
      PiPTileNavigationPreparationProgress(
        completed: configuration.tileCount,
        succeeded: tiles.count,
        failed: failures.count,
        total: configuration.tileCount,
        message: failures.isEmpty
          ? "\(configuration.tileCount) 張圖磚已完成" : "圖磚擷取不完整"
      )
    )
    guard failures.isEmpty else {
      throw PiPTileNavigationError.incompleteCapture(
        failed: failures.count,
        details: failures.joined(separator: "；")
      )
    }

    return PiPTileNavigationMapSource(
      configuration: configuration,
      mapRect: coverageRect,
      tiles: tiles.sorted { $0.id < $1.id },
      center: center,
      captureDuration: Date().timeIntervalSince(startedAt)
    )
  }

  private static func captureTile(
    row: Int,
    column: Int,
    index: Int,
    mapRect: MKMapRect,
    configuration: PiPTileNavigationConfiguration
  ) async throws -> PiPTileNavigationTile {
    let options = MKMapSnapshotter.Options()
    options.mapRect = mapRect
    options.size = configuration.tilePixelSize
    options.scale = 1
    let mapConfiguration = MKStandardMapConfiguration()
    mapConfiguration.elevationStyle = .flat
    mapConfiguration.showsTraffic = false
    mapConfiguration.pointOfInterestFilter = .excludingAll
    options.preferredConfiguration = mapConfiguration

    let snapshot = try await MKMapSnapshotter(options: options).start()
    guard let original = snapshot.image.cgImage else {
      throw PiPTileNavigationError.missingImage(index)
    }
    let nativeScale = CGSize(
      width: CGFloat(original.width) / max(snapshot.image.size.width, 1),
      height: CGFloat(original.height) / max(snapshot.image.size.height, 1)
    )
    let mapCorners = [
      MKMapPoint(x: mapRect.minX, y: mapRect.minY),
      MKMapPoint(x: mapRect.maxX, y: mapRect.minY),
      MKMapPoint(x: mapRect.maxX, y: mapRect.maxY),
      MKMapPoint(x: mapRect.minX, y: mapRect.maxY),
    ]
    let projectedCorners = mapCorners.map { point -> CGPoint in
      let value = snapshot.point(for: point.coordinate)
      return CGPoint(x: value.x * nativeScale.width, y: value.y * nativeScale.height)
    }
    let contentBounds = projectedCorners.reduce(CGRect.null) { bounds, point in
      bounds.union(CGRect(origin: point, size: .zero))
    }.standardized
    let imageBounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
    let cropRect = contentBounds.integral.intersection(imageBounds)
    guard cropRect.width > 0, cropRect.height > 0,
      let cropped = original.cropping(to: cropRect)
    else {
      throw PiPTileNavigationError.invalidSnapshotGeometry(index)
    }

    let expectedCorners = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: cropRect.width, y: 0),
      CGPoint(x: cropRect.width, y: cropRect.height),
      CGPoint(x: 0, y: cropRect.height),
    ]
    let calibrationError = zip(projectedCorners, expectedCorners).map { actual, expected in
      hypot(actual.x - cropRect.minX - expected.x, actual.y - cropRect.minY - expected.y)
    }.max() ?? 0
    let canvasRect = CGRect(
      x: CGFloat(column) * configuration.tilePixelSize.width,
      y: CGFloat(row) * configuration.tilePixelSize.height,
      width: configuration.tilePixelSize.width,
      height: configuration.tilePixelSize.height
    )
    return PiPTileNavigationTile(
      row: row,
      column: column,
      image: cropped,
      mapRect: mapRect,
      canvasRect: canvasRect,
      calibrationErrorPixels: calibrationError
    )
  }
}

enum PiPTileNavigationRenderer {
  static func drawMap(
    source: PiPTileNavigationMapSource,
    cameraTransform: CGAffineTransform,
    outputSize: CGSize,
    debugBoundaries: Bool,
    context: CGContext
  ) {
    context.saveGState()
    context.concatenate(cameraTransform)
    context.interpolationQuality = .high
    for tile in source.visibleTiles(cameraTransform: cameraTransform, outputSize: outputSize) {
      let bleed = source.configuration.seamBleedPixels
      let destination = tile.canvasRect.insetBy(dx: -bleed, dy: -bleed)
      PiPBenchmarkDrawing.drawUpright(
        cgImage: tile.image,
        in: destination,
        context: context
      )
      if debugBoundaries {
        drawDebugBoundary(tile: tile, outputScale: cameraTransform.tileOutputScale, context: context)
      }
    }
    context.restoreGState()
  }

  static func drawOverview(
    source: PiPTileNavigationMapSource,
    outputSize: CGSize,
    debugBoundaries: Bool,
    context: CGContext
  ) {
    let canvasSize = source.configuration.canvasPixelSize
    let transform = CGAffineTransform(
      scaleX: outputSize.width / canvasSize.width,
      y: outputSize.height / canvasSize.height
    )
    drawMap(
      source: source,
      cameraTransform: transform,
      outputSize: outputSize,
      debugBoundaries: debugBoundaries,
      context: context
    )
  }

  private static func drawDebugBoundary(
    tile: PiPTileNavigationTile,
    outputScale: CGFloat,
    context: CGContext
  ) {
    let lineWidth = 2 / max(outputScale, 0.001)
    context.setStrokeColor(UIColor.systemPink.withAlphaComponent(0.9).cgColor)
    context.setLineWidth(lineWidth)
    context.stroke(tile.canvasRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))

    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedSystemFont(ofSize: 28 / max(outputScale, 0.001), weight: .bold),
      .foregroundColor: UIColor.systemPink,
      .backgroundColor: UIColor.black.withAlphaComponent(0.7),
    ]
    tile.label.draw(
      at: CGPoint(
        x: tile.canvasRect.minX + 8 / max(outputScale, 0.001),
        y: tile.canvasRect.minY + 8 / max(outputScale, 0.001)
      ),
      withAttributes: attributes
    )
  }
}

extension CGAffineTransform {
  fileprivate var isInvertible: Bool { abs(a * d - b * c) > .ulpOfOne }
  fileprivate var tileOutputScale: CGFloat { hypot(a, c) }
}
