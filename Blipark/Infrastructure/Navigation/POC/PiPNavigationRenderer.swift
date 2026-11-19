import CoreGraphics
import MapKit
import UIKit

struct PiPNavigationRenderedFrame {
  let pixelBuffer: CVPixelBuffer
  let pixelBufferMilliseconds: Double
  let renderMilliseconds: Double
}

enum PiPNavigationRenderer {
  static let vehiclePoint = CGPoint(x: 0.5, y: 0.72)

  static func renderWaitingMap(
    source: any PiPNavigationProjectionSource,
    kind: PiPBenchmarkRendererKind,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize,
    debugTileBoundaries: Bool = false
  ) throws -> PiPNavigationRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime
    let renderStart = allocationEnd

    if kind.usesLegacyPipeline {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let intermediate = UIGraphicsImageRenderer(size: outputSize, format: format).image {
        drawWaitingMap(
          source: source,
          into: $0.cgContext,
          outputSize: outputSize,
          debugTileBoundaries: debugTileBoundaries
        )
      }
      try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        intermediate.draw(in: CGRect(origin: .zero, size: size))
      }
    } else {
      try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        drawWaitingMap(
          source: source,
          into: context,
          outputSize: size,
          debugTileBoundaries: debugTileBoundaries
        )
      }
    }
    let renderEnd = ProcessInfo.processInfo.systemUptime
    return PiPNavigationRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (renderEnd - renderStart) * 1_000
    )
  }

  static func render(
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    kind: PiPBenchmarkRendererKind,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize,
    debugTileBoundaries: Bool = false
  ) throws -> PiPNavigationRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime
    let renderStart = allocationEnd

    if kind.usesLegacyPipeline {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let intermediate = UIGraphicsImageRenderer(size: outputSize, format: format).image {
        render(
          into: $0.cgContext,
          route: route,
          sample: sample,
          outputSize: outputSize,
          debugTileBoundaries: debugTileBoundaries
        )
      }
      try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        intermediate.draw(in: CGRect(origin: .zero, size: size))
      }
    } else {
      try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        render(
          into: context,
          route: route,
          sample: sample,
          outputSize: size,
          debugTileBoundaries: debugTileBoundaries
        )
      }
    }

    let renderEnd = ProcessInfo.processInfo.systemUptime
    return PiPNavigationRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (renderEnd - renderStart) * 1_000
    )
  }

  private static func render(
    into context: CGContext,
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    outputSize: CGSize,
    debugTileBoundaries: Bool
  ) {
    PiPBenchmarkDrawing.clear(context: context, size: outputSize)
    let transform = cameraTransform(route: route, sample: sample, outputSize: outputSize)

    if let tileSource = route.tileSource {
      PiPTileNavigationRenderer.drawMap(
        source: tileSource,
        cameraTransform: transform,
        outputSize: outputSize,
        debugBoundaries: debugTileBoundaries,
        context: context
      )
      context.saveGState()
      context.concatenate(transform)
      drawRoute(route.imagePoints, in: context, outputScale: transform.outputScale)
      context.restoreGState()
    } else {
      context.saveGState()
      context.concatenate(transform)
      context.interpolationQuality = .high
      PiPBenchmarkDrawing.drawUpright(
        cgImage: route.image,
        in: CGRect(origin: .zero, size: route.imageSize),
        context: context
      )
      drawRoute(route.imagePoints, in: context, outputScale: transform.outputScale)
      context.restoreGState()
    }

    drawVehicle(in: context, outputSize: outputSize)
  }

  private static func drawWaitingMap(
    source: any PiPNavigationProjectionSource,
    into context: CGContext,
    outputSize: CGSize,
    debugTileBoundaries: Bool
  ) {
    PiPBenchmarkDrawing.clear(context: context, size: outputSize)
    context.interpolationQuality = .high
    if let tileSource = source as? PiPTileNavigationMapSource {
      PiPTileNavigationRenderer.drawOverview(
        source: tileSource,
        outputSize: outputSize,
        debugBoundaries: debugTileBoundaries,
        context: context
      )
    } else {
      PiPBenchmarkDrawing.drawUpright(
        cgImage: source.fallbackImage,
        in: CGRect(origin: .zero, size: outputSize),
        context: context
      )
    }

    let bannerHeight = max(42, outputSize.height * 0.11)
    context.setFillColor(UIColor.black.withAlphaComponent(0.68).cgColor)
    context.fill(
      CGRect(x: 0, y: outputSize.height - bannerHeight, width: outputSize.width, height: bannerHeight)
    )
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    let text = "PiP 已就緒・切到背景後取得 MKRoute"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: max(18, bannerHeight * 0.34), weight: .semibold),
      .foregroundColor: UIColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
      at: CGPoint(
        x: (outputSize.width - textSize.width) / 2,
        y: outputSize.height - bannerHeight + (bannerHeight - textSize.height) / 2
      ),
      withAttributes: attributes
    )
  }

  static func cameraTransform(
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    outputSize: CGSize
  ) -> CGAffineTransform {
    let sourceMetersPerPixel = route.sourceMetersPerPixel
    let outputMetersPerPixel = route.viewportWidthMeters / max(outputSize.width, 1)
    let scale = sourceMetersPerPixel / max(outputMetersPerPixel, .ulpOfOne)
    let target = CGPoint(
      x: vehiclePoint.x * outputSize.width,
      y: vehiclePoint.y * outputSize.height
    )
    var transform = CGAffineTransform(translationX: target.x, y: target.y)
    transform = transform.rotated(by: -CGFloat(sample.headingDegrees * .pi / 180))
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -sample.imagePoint.x, y: -sample.imagePoint.y)
    return transform
  }

  private static func drawRoute(
    _ points: [CGPoint],
    in context: CGContext,
    outputScale: CGFloat
  ) {
    guard let first = points.first else { return }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    context.addPath(path)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
    context.setLineWidth(15 / max(outputScale, 0.001))
    context.strokePath()

    context.addPath(path)
    context.setStrokeColor(UIColor.systemBlue.cgColor)
    context.setLineWidth(9 / max(outputScale, 0.001))
    context.strokePath()
  }

  private static func drawVehicle(in context: CGContext, outputSize: CGSize) {
    let center = CGPoint(
      x: vehiclePoint.x * outputSize.width,
      y: vehiclePoint.y * outputSize.height
    )
    let radius = max(12, min(outputSize.width, outputSize.height) * 0.042)
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: 2),
      blur: 5,
      color: UIColor.black.withAlphaComponent(0.6).cgColor
    )
    context.setFillColor(UIColor.white.cgColor)
    context.fillEllipse(
      in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    )
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.translateBy(x: center.x, y: center.y)
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 0, y: -radius * 0.8))
    arrow.addLine(to: CGPoint(x: radius * 0.52, y: radius * 0.58))
    arrow.addLine(to: CGPoint(x: 0, y: radius * 0.28))
    arrow.addLine(to: CGPoint(x: -radius * 0.52, y: radius * 0.58))
    arrow.closeSubpath()
    context.addPath(arrow)
    context.setFillColor(UIColor.systemBlue.cgColor)
    context.fillPath()
    context.restoreGState()
  }
}

private extension CGAffineTransform {
  var outputScale: CGFloat { hypot(a, c) }
}
