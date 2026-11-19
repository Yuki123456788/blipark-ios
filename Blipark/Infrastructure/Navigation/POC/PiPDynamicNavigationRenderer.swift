import CoreGraphics
import CoreLocation
import UIKit

struct PiPDynamicRoutePresentation {
  let overviewToNavigationProgress: CGFloat
  let promptAlpha: CGFloat

  static let navigation = PiPDynamicRoutePresentation(
    overviewToNavigationProgress: 1,
    promptAlpha: 0
  )
}

enum PiPDynamicNavigationRenderer {
  static func render(
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    camera: PiPDynamicCameraState,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize,
    debugTileBoundaries: Bool,
    presentation: PiPDynamicRoutePresentation = .navigation,
    vehicleWorldHeadingDegrees: CLLocationDirection? = nil,
    presentationPrompt: String = "開始導航・先看完整路線",
    navigationOverlay: PiPRealNavigationRenderOverlay? = nil
  ) throws -> PiPNavigationRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime

    try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1, y: -1)
      draw(
        route: route,
        sample: sample,
        camera: camera,
        context: context,
        outputSize: size,
        debugTileBoundaries: debugTileBoundaries,
        presentation: presentation,
        vehicleWorldHeadingDegrees: vehicleWorldHeadingDegrees,
        presentationPrompt: presentationPrompt,
        navigationOverlay: navigationOverlay
      )
    }
    let renderEnd = ProcessInfo.processInfo.systemUptime
    return PiPNavigationRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (renderEnd - allocationEnd) * 1_000
    )
  }

  static func cameraTransform(
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    camera: PiPDynamicCameraState,
    outputSize: CGSize
  ) -> CGAffineTransform {
    let scale = route.sourceMetersPerPixel / max(camera.metersPerPoint, .ulpOfOne)
    let pitchScale = max(cos(camera.pitchDegrees * .pi / 180), 0.5)
    let vehicle = PiPNavigationRenderer.vehiclePoint
    let target = CGPoint(x: vehicle.x * outputSize.width, y: vehicle.y * outputSize.height)
    var transform = CGAffineTransform(translationX: target.x, y: target.y)
    transform = transform.scaledBy(x: 1, y: pitchScale)
    transform = transform.rotated(by: -CGFloat(camera.bearingDegrees * .pi / 180))
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -sample.imagePoint.x, y: -sample.imagePoint.y)
    return transform
  }

  private static func draw(
    route: PiPNavigationPreparedRoute,
    sample: PiPNavigationSample,
    camera: PiPDynamicCameraState,
    context: CGContext,
    outputSize: CGSize,
    debugTileBoundaries: Bool,
    presentation: PiPDynamicRoutePresentation,
    vehicleWorldHeadingDegrees: CLLocationDirection?,
    presentationPrompt: String,
    navigationOverlay: PiPRealNavigationRenderOverlay?
  ) {
    PiPBenchmarkDrawing.clear(context: context, size: outputSize)
    let navigationTransform = cameraTransform(
      route: route,
      sample: sample,
      camera: camera,
      outputSize: outputSize
    )
    let progress = min(max(presentation.overviewToNavigationProgress, 0), 1)
    let overviewTransform = routeOverviewTransform(route: route, outputSize: outputSize)
    let transform = interpolate(
      from: overviewTransform,
      to: navigationTransform,
      progress: progress
    )

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
      drawRoutes(
        route: route,
        navigationOverlay: navigationOverlay,
        outputScale: transform.dynamicOutputScale,
        context: context
      )
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
      drawRoutes(
        route: route,
        navigationOverlay: navigationOverlay,
        outputScale: transform.dynamicOutputScale,
        context: context
      )
      context.restoreGState()
    }

    if let navigationOverlay {
      drawParkingMarkers(
        stops: [navigationOverlay.currentStop] + navigationOverlay.upcomingStops,
        transform: transform,
        outputSize: outputSize,
        context: context
      )
    }

    let vehicleCenter = sample.imagePoint.applying(transform)
    let mapBearing = presentationMapBearing(
      cameraBearing: camera.bearingDegrees,
      progress: progress
    )
    let vehicleRotation = resolvedVehicleRotationDegrees(
      vehicleWorldHeading: vehicleWorldHeadingDegrees,
      sampleHeading: sample.headingDegrees,
      mapBearing: mapBearing
    )
    drawVehicle(
      context: context,
      center: vehicleCenter,
      outputSize: outputSize,
      rotationDegrees: vehicleRotation
    )
    if let navigationOverlay {
      drawNavigationInformation(
        overlay: navigationOverlay,
        context: context,
        outputSize: outputSize
      )
    }
    if presentation.promptAlpha > 0 {
      drawNavigationPrompt(
        context: context,
        outputSize: outputSize,
        alpha: presentation.promptAlpha,
        text: presentationPrompt
      )
    }
  }

  static func routeOverviewTransform(
    route: PiPNavigationPreparedRoute,
    outputSize: CGSize
  ) -> CGAffineTransform {
    let bounds = route.imagePoints.reduce(CGRect.null) {
      $0.union(CGRect(origin: $1, size: .zero))
    }
    guard !bounds.isNull else { return .identity }
    let horizontalPadding = outputSize.width * 0.1
    let verticalPadding = outputSize.height * 0.14
    let availableWidth = max(outputSize.width - horizontalPadding * 2, 1)
    let availableHeight = max(outputSize.height - verticalPadding * 2, 1)
    let scale = min(
      availableWidth / max(bounds.width, 1),
      availableHeight / max(bounds.height, 1)
    )
    var transform = CGAffineTransform(
      translationX: outputSize.width * 0.5,
      y: outputSize.height * 0.5
    )
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.translatedBy(x: -bounds.midX, y: -bounds.midY)
    return transform
  }

  static func interpolate(
    from start: CGAffineTransform,
    to end: CGAffineTransform,
    progress: CGFloat
  ) -> CGAffineTransform {
    let value = min(max(progress, 0), 1)
    return CGAffineTransform(
      a: start.a + (end.a - start.a) * value,
      b: start.b + (end.b - start.b) * value,
      c: start.c + (end.c - start.c) * value,
      d: start.d + (end.d - start.d) * value,
      tx: start.tx + (end.tx - start.tx) * value,
      ty: start.ty + (end.ty - start.ty) * value
    )
  }

  static func vehicleRotationDegrees(
    sampleHeading: CLLocationDirection,
    mapBearing: CLLocationDirection
  ) -> CLLocationDirection {
    (sampleHeading - mapBearing + 540).truncatingRemainder(dividingBy: 360) - 180
  }

  static func presentationMapBearing(
    cameraBearing: CLLocationDirection,
    progress: CGFloat
  ) -> CLLocationDirection {
    interpolateAngle(from: 0, to: cameraBearing, progress: min(max(progress, 0), 1))
  }

  static func resolvedVehicleRotationDegrees(
    vehicleWorldHeading: CLLocationDirection?,
    sampleHeading: CLLocationDirection,
    mapBearing: CLLocationDirection
  ) -> CLLocationDirection {
    vehicleRotationDegrees(
      sampleHeading: vehicleWorldHeading ?? sampleHeading,
      mapBearing: mapBearing
    )
  }

  private static func drawRoutes(
    route: PiPNavigationPreparedRoute,
    navigationOverlay: PiPRealNavigationRenderOverlay?,
    outputScale: CGFloat,
    context: CGContext
  ) {
    if let preview = navigationOverlay?.previewRoute {
      drawRoute(
        preview.imagePoints,
        color: navigationOverlay?.upcomingStops.first?.color.uiColor ?? .systemOrange,
        alpha: 0.42,
        outputScale: outputScale,
        context: context
      )
    }
    drawRoute(
      route.imagePoints,
      color: navigationOverlay?.currentStop.color.uiColor ?? .systemBlue,
      alpha: 1,
      outputScale: outputScale,
      context: context
    )
  }

  private static func drawRoute(
    _ points: [CGPoint],
    color: UIColor,
    alpha: CGFloat,
    outputScale: CGFloat,
    context: CGContext
  ) {
    guard let first = points.first else { return }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.setStrokeColor(UIColor.white.withAlphaComponent(0.88 * alpha).cgColor)
    context.setLineWidth(21 / max(outputScale, 0.001))
    context.strokePath()
    context.addPath(path)
    context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
    context.setLineWidth(13 / max(outputScale, 0.001))
    context.strokePath()
  }

  private static func drawParkingMarkers(
    stops: [PiPRealParkingRenderStop],
    transform: CGAffineTransform,
    outputSize: CGSize,
    context: CGContext
  ) {
    let diameter = max(48, min(outputSize.width, outputSize.height) * 0.085)
    for stop in stops.reversed() {
      let center = stop.imagePoint.applying(transform)
      guard center.x > -diameter, center.x < outputSize.width + diameter,
        center.y > -diameter, center.y < outputSize.height + diameter
      else { continue }
      let frame = CGRect(
        x: center.x - diameter * 0.5,
        y: center.y - diameter,
        width: diameter,
        height: diameter
      )
      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: 2),
        blur: 5,
        color: UIColor.black.withAlphaComponent(0.48).cgColor
      )
      let pin = CGMutablePath()
      pin.addEllipse(in: frame)
      pin.move(to: CGPoint(x: center.x - diameter * 0.14, y: frame.maxY - 2))
      pin.addLine(to: CGPoint(x: center.x + diameter * 0.14, y: frame.maxY - 2))
      pin.addLine(to: CGPoint(x: center.x, y: center.y + diameter * 0.17))
      pin.closeSubpath()
      context.addPath(pin)
      context.setFillColor(stop.color.uiColor.withAlphaComponent(stop.isCurrent ? 1 : 0.82).cgColor)
      context.fillPath()
      context.setShadow(offset: .zero, blur: 0, color: nil)
      context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
      context.setLineWidth(stop.isCurrent ? 4 : 2.5)
      context.strokeEllipse(in: frame.insetBy(dx: 1.5, dy: 1.5))
      if let symbol = UIImage(systemName: stop.kind.symbolName)?.withTintColor(
        .white, renderingMode: .alwaysOriginal)
      {
        let inset = diameter * 0.24
        UIGraphicsPushContext(context)
        symbol.draw(in: frame.insetBy(dx: inset, dy: inset))
        UIGraphicsPopContext()
      }
      context.restoreGState()
    }
  }

  private static func drawNavigationInformation(
    overlay: PiPRealNavigationRenderOverlay,
    context: CGContext,
    outputSize: CGSize
  ) {
    let margin = navigationContentMargin(outputSize: outputSize)
    let cardFrame = navigationInformationCardFrame(outputSize: outputSize)
    let cardHeight = cardFrame.height
    context.saveGState()
    context.setShadow(
      offset: CGSize(width: 0, height: 3),
      blur: 8,
      color: UIColor.black.withAlphaComponent(0.24).cgColor
    )
    context.setFillColor(
      UIColor(red: 0.055, green: 0.075, blue: 0.095, alpha: 0.66).cgColor
    )
    context.addPath(UIBezierPath(roundedRect: cardFrame, cornerRadius: 26).cgPath)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    UIGraphicsPushContext(context)
    let iconSize = cardHeight * 0.56
    let iconFrame = CGRect(
      x: cardFrame.minX + 26,
      y: cardFrame.midY - iconSize * 0.5,
      width: iconSize,
      height: iconSize
    )
    let iconBackground = UIBezierPath(roundedRect: iconFrame, cornerRadius: iconSize * 0.24)
    overlay.currentStop.color.uiColor.setFill()
    iconBackground.fill()
    UIImage(systemName: overlay.currentStop.kind.symbolName)?
      .withTintColor(.white, renderingMode: .alwaysOriginal)
      .draw(in: iconFrame.insetBy(dx: iconSize * 0.21, dy: iconSize * 0.21))
    let textX = iconFrame.maxX + 20
    let distanceText = formattedDistance(overlay.remainingRouteDistanceMeters)
    let distanceAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedDigitSystemFont(
        ofSize: max(34, cardHeight * 0.31),
        weight: .heavy
      ),
      .foregroundColor: UIColor.white,
    ]
    let distanceSize = distanceText.size(withAttributes: distanceAttributes)
    let distanceOrigin = CGPoint(
      x: cardFrame.maxX - distanceSize.width - 22,
      y: cardFrame.midY - distanceSize.height * 0.5
    )
    distanceText.draw(
      at: distanceOrigin,
      withAttributes: distanceAttributes
    )
    let nameFont = UIFont.systemFont(ofSize: max(40, cardHeight * 0.36), weight: .heavy)
    let nameFrame = CGRect(
      x: textX,
      y: cardFrame.midY - nameFont.lineHeight * 0.5 - 2,
      width: max(40, distanceOrigin.x - textX - 18),
      height: nameFont.lineHeight + 6
    )
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    paragraph.alignment = .left
    let name = NSAttributedString(
      string: overlay.currentStop.name,
      attributes: [
        .font: nameFont,
        .foregroundColor: UIColor.white,
        .paragraphStyle: paragraph,
      ]
    )
    let nameBounds = name.boundingRect(
      with: nameFrame.size,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      context: nil
    )
    name.draw(
      with: nameFrame.offsetBy(dx: 0, dy: (nameFrame.height - nameBounds.height) * 0.5),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      context: nil
    )
    UIGraphicsPopContext()
    context.restoreGState()

    guard !overlay.upcomingStops.isEmpty else { return }
    let visibleStops = Array(overlay.upcomingStops.prefix(4))
    let spacing: CGFloat = 14
    let chipHeight = max(92, outputSize.height * 0.14)
    let availableWidth = outputSize.width - margin * 2
    let chipWidth = min(
      330,
      (availableWidth - spacing * CGFloat(visibleStops.count - 1))
        / CGFloat(visibleStops.count)
    )
    let rowWidth =
      chipWidth * CGFloat(visibleStops.count)
      + spacing * CGFloat(visibleStops.count - 1)
    var x = (outputSize.width - rowWidth) * 0.5
    let y = outputSize.height - margin - chipHeight
    UIGraphicsPushContext(context)
    for stop in visibleStops {
      let frame = CGRect(x: x, y: y, width: chipWidth, height: chipHeight)
      context.setFillColor(stop.color.uiColor.withAlphaComponent(0.86).cgColor)
      context.addPath(UIBezierPath(roundedRect: frame, cornerRadius: chipHeight * 0.28).cgPath)
      context.fillPath()
      let iconFrame = CGRect(
        x: frame.minX + 17,
        y: frame.midY - chipHeight * 0.26,
        width: chipHeight * 0.52,
        height: chipHeight * 0.52
      )
      UIImage(systemName: stop.kind.symbolName)?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
        .draw(in: iconFrame)
      let titleFrame = CGRect(
        x: iconFrame.maxX + 13,
        y: frame.minY,
        width: frame.maxX - iconFrame.maxX - 23,
        height: frame.height
      )
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineBreakMode = .byTruncatingTail
      let title = NSAttributedString(
        string: stop.name,
        attributes: [
          .font: UIFont.systemFont(ofSize: max(34, chipHeight * 0.40), weight: .bold),
          .foregroundColor: UIColor.white,
          .paragraphStyle: paragraph,
        ]
      )
      let titleBounds = title.boundingRect(
        with: titleFrame.size,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        context: nil
      )
      title.draw(
        with: titleFrame.offsetBy(dx: 0, dy: (titleFrame.height - titleBounds.height) * 0.5),
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        context: nil
      )
      x += chipWidth + spacing
    }
    UIGraphicsPopContext()
  }

  static func navigationInformationCardFrame(outputSize: CGSize) -> CGRect {
    let margin = navigationContentMargin(outputSize: outputSize)
    let cardHeight = max(120, outputSize.height * 0.17)
    let cardWidth = min(outputSize.width * 0.58, 700)
    return CGRect(x: margin, y: margin, width: cardWidth, height: cardHeight)
  }

  private static func navigationContentMargin(outputSize: CGSize) -> CGFloat {
    max(28, outputSize.height * 0.04)
  }

  private static func formattedDistance(_ meters: CLLocationDistance) -> String {
    if meters >= 1_000 { return String(format: "%.1f km", meters / 1_000) }
    if meters >= 100 { return "\(Int((meters / 10).rounded()) * 10) m" }
    return "\(Int(max(0, meters).rounded())) m"
  }

  private static func drawVehicle(
    context: CGContext,
    center: CGPoint,
    outputSize: CGSize,
    rotationDegrees: CLLocationDirection
  ) {
    let radius = max(14, min(outputSize.width, outputSize.height) * 0.05)
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
    context.rotate(by: CGFloat(rotationDegrees * .pi / 180))
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

  private static func drawNavigationPrompt(
    context: CGContext,
    outputSize: CGSize,
    alpha: CGFloat,
    text: String
  ) {
    let clampedAlpha = min(max(alpha, 0), 1)
    let width = min(outputSize.width * 0.48, 520)
    let height = max(58, outputSize.height * 0.09)
    let frame = CGRect(
      x: (outputSize.width - width) * 0.5,
      y: outputSize.height * 0.07,
      width: width,
      height: height
    )
    context.saveGState()
    context.setFillColor(UIColor.black.withAlphaComponent(0.72 * clampedAlpha).cgColor)
    context.addPath(
      UIBezierPath(
        roundedRect: frame,
        cornerRadius: height * 0.5
      ).cgPath
    )
    context.fillPath()
    UIGraphicsPushContext(context)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: max(20, height * 0.38), weight: .semibold),
      .foregroundColor: UIColor.white.withAlphaComponent(clampedAlpha),
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
      at: CGPoint(
        x: frame.midX - textSize.width * 0.5,
        y: frame.midY - textSize.height * 0.5
      ),
      withAttributes: attributes
    )
    UIGraphicsPopContext()
    context.restoreGState()
  }

  private static func interpolateAngle(
    from start: CLLocationDirection,
    to end: CLLocationDirection,
    progress: CGFloat
  ) -> CLLocationDirection {
    let delta = (end - start + 540).truncatingRemainder(dividingBy: 360) - 180
    return start + delta * Double(progress)
  }

}

extension CGAffineTransform {
  fileprivate var dynamicOutputScale: CGFloat { hypot(a, c) }
}
