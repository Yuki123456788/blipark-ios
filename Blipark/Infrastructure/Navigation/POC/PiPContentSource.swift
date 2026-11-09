import AVFoundation
import CoreLocation
import CoreMedia
import UIKit

struct PiPNavigationContent {
  var mode: NavigationDisplayMode
  var maneuver: ManeuverType
  var distanceMeters: Int
  var instruction: String
  var mapAsset: PiPNavigationMapAsset?
  var progress: CGFloat

  var currentPoint: CGPoint? {
    mapAsset?.currentPoint
  }

  var remainingRoutePoints: [CGPoint] {
    mapAsset?.routePoints ?? []
  }
}

struct PiPConfiguration {
  enum ContentMode: String, Equatable {
    case text = "文字"
    case colorBlocks = "文字加色塊"
    case simpleGraphic = "簡單圖形"
  }

  var width: Int
  var height: Int
  var remainingSpaces: Int
  var distanceMeters: Int
  var contentMode: ContentMode
  var navigation: PiPNavigationContent? = nil

  var aspectRatio: CGFloat {
    CGFloat(width) / CGFloat(max(height, 1))
  }

  var resolutionText: String { "\(width) × \(height)" }

  static let standard = PiPConfiguration(
    width: 1280,
    height: 720,
    remainingSpaces: 12,
    distanceMeters: 350,
    contentMode: .colorBlocks
  )
}

@MainActor
final class PiPContentSource {
  let displayLayer = AVSampleBufferDisplayLayer()

  private(set) var configuration = PiPConfiguration.standard
  private(set) var isPlaying = true
  private var renderingTimer: Timer?
  private var usesExternalFrames = false

  var readinessDescription: String {
    if let error = displayLayer.error {
      return "Frame 顯示失敗：\(error.localizedDescription)"
    }
    return displayLayer.status == .rendering ? "第一個 frame 已顯示" : "等待第一個 frame"
  }

  var isRendering: Bool { displayLayer.status == .rendering }

  init() {
    displayLayer.videoGravity = .resizeAspect
    displayLayer.backgroundColor = UIColor.black.cgColor
  }

  func start(configuration: PiPConfiguration) {
    self.configuration = configuration
    isPlaying = true
    usesExternalFrames = false
    renderFrame(flushFirst: true)
    renderingTimer?.invalidate()
    renderingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.renderFrame()
      }
    }
  }

  func startExternal(configuration: PiPConfiguration) {
    self.configuration = configuration
    isPlaying = true
    usesExternalFrames = true
    renderingTimer?.invalidate()
    renderingTimer = nil
    // PiP needs an initial image before the benchmark worker has produced its first frame.
    renderFrame(flushFirst: true)
  }

  @discardableResult
  func enqueueExternal(_ sampleBuffer: CMSampleBuffer) -> Bool {
    guard usesExternalFrames, isPlaying else { return false }
    let renderer = displayLayer.sampleBufferRenderer
    guard renderer.isReadyForMoreMediaData else { return false }
    if displayLayer.status == .failed {
      displayLayer.flush()
    }
    renderer.enqueue(sampleBuffer)
    return true
  }

  func update(configuration: PiPConfiguration, flushFirst: Bool = false) {
    let dimensionsChanged =
      self.configuration.width != configuration.width
      || self.configuration.height != configuration.height
    self.configuration = configuration
    renderFrame(flushFirst: flushFirst || dimensionsChanged)
  }

  func setPlaying(_ playing: Bool) {
    isPlaying = playing
    if playing, !usesExternalFrames {
      renderFrame()
    }
  }

  func stop() {
    renderingTimer?.invalidate()
    renderingTimer = nil
    usesExternalFrames = false
    displayLayer.flushAndRemoveImage()
  }

  private func renderFrame(flushFirst: Bool = false) {
    guard isPlaying, let sampleBuffer = makeSampleBuffer(configuration: configuration) else {
      return
    }
    if flushFirst || displayLayer.status == .failed {
      displayLayer.flush()
    }
    displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
  }

  private func makeSampleBuffer(configuration: PiPConfiguration) -> CMSampleBuffer? {
    let attributes: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    var pixelBuffer: CVPixelBuffer?
    let result = CVPixelBufferCreate(
      kCFAllocatorDefault,
      configuration.width,
      configuration.height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &pixelBuffer
    )
    guard result == kCVReturnSuccess, let pixelBuffer else { return nil }

    draw(configuration: configuration, into: pixelBuffer)

    var formatDescription: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
      ) == noErr,
      let formatDescription
    else { return nil }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
      ) == noErr,
      let sampleBuffer
    else { return nil }

    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer,
      createIfNecessary: true
    ) as? [NSMutableDictionary],
      let firstAttachment = attachments.first
    {
      firstAttachment[kCMSampleAttachmentKey_DisplayImmediately] = true
    }
    return sampleBuffer
  }

  private func draw(configuration: PiPConfiguration, into pixelBuffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: configuration.width,
        height: configuration.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return }

    context.translateBy(x: 0, y: CGFloat(configuration.height))
    context.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }

    let bounds = CGRect(x: 0, y: 0, width: configuration.width, height: configuration.height)
    if let navigation = configuration.navigation {
      drawNavigation(navigation, in: bounds)
      return
    }

    drawParking(configuration: configuration, in: bounds, context: context)
  }

  private func drawParking(
    configuration: PiPConfiguration,
    in bounds: CGRect,
    context: CGContext
  ) {
    let colors =
      [
        UIColor(red: 0.03, green: 0.13, blue: 0.24, alpha: 1).cgColor,
        UIColor(red: 0.02, green: 0.34, blue: 0.48, alpha: 1).cgColor,
      ] as CFArray
    let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: colors,
      locations: [0, 1]
    )
    if let gradient {
      context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: bounds.midY),
        end: CGPoint(x: bounds.maxX, y: bounds.midY),
        options: []
      )
    }

    if configuration.contentMode != .text {
      let badgeWidth = min(CGFloat(configuration.width) * 0.18, CGFloat(configuration.height) * 1.5)
      let badgeRect = CGRect(x: 0, y: 0, width: badgeWidth, height: bounds.height)
      UIColor.systemBlue.withAlphaComponent(0.72).setFill()
      UIRectFill(badgeRect)
    }

    let time = Self.timeFormatter.string(from: Date())
    let parkingPrefix = configuration.contentMode == .simpleGraphic ? "P" : "🅿︎"
    let text =
      "\(parkingPrefix)  剩餘 \(configuration.remainingSpaces) 格  │  距離 \(configuration.distanceMeters)m  │  \(time)"
    let fontSize = max(
      18,
      min(CGFloat(configuration.height) * 0.29, CGFloat(configuration.width) * 0.055)
    )
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: UIColor.white,
      .paragraphStyle: paragraph,
    ]
    let verticalInset = max(2, (bounds.height - fontSize * 1.35) / 2)
    let textRect = bounds.insetBy(dx: max(12, bounds.width * 0.025), dy: verticalInset)
    (text as NSString).draw(in: textRect, withAttributes: attributes)
  }

  private func drawNavigation(_ navigation: PiPNavigationContent, in bounds: CGRect) {
    switch navigation.mode {
    case .fullMap:
      drawNavigationMap(navigation, in: bounds)
      drawMapCaption(navigation, in: bounds)
    case .guidance:
      drawGuidance(navigation, in: bounds)
    case .hybrid:
      drawNavigationMap(navigation, in: bounds)
      drawCompactGuidance(navigation, in: bounds)
    }
  }

  private func drawNavigationMap(_ navigation: PiPNavigationContent, in bounds: CGRect) {
    if let asset = navigation.mapAsset {
      asset.image.draw(in: bounds)
      drawRoute(navigation.remainingRoutePoints, in: bounds)
      if let originalDestinationPoint = asset.originalDestinationPoint {
        drawMapMarker(
          code: "B",
          point: originalDestinationPoint,
          color: .systemOrange,
          in: bounds
        )
      }
      if let parkingPoint = asset.parkingPoint {
        drawMapMarker(code: "C", point: parkingPoint, color: .systemGreen, in: bounds)
      }
      if asset.showsVehicle {
        if let rotation = asset.vehicleRotationDegrees {
          drawVehicleMarker(point: asset.currentPoint, rotationDegrees: rotation, in: bounds)
        } else {
          drawMapMarker(code: "A", point: asset.currentPoint, color: .systemBlue, in: bounds)
        }
      }
      if !asset.isViewportCovered {
        drawCoverageWarning(in: bounds)
      }
    } else {
      UIColor(red: 0.04, green: 0.13, blue: 0.23, alpha: 1).setFill()
      UIRectFill(bounds)
      drawCenteredText(
        "正在準備導航地圖…",
        in: bounds,
        fontSize: max(18, bounds.height * 0.08),
        weight: .semibold
      )
    }
  }

  private func drawCoverageWarning(in bounds: CGRect) {
    let height = max(44, bounds.height * 0.12)
    let warningRect = CGRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
    UIColor.systemRed.withAlphaComponent(0.92).setFill()
    UIRectFill(warningRect)
    drawCenteredText(
      "超出預擷取地圖範圍",
      in: warningRect.insetBy(dx: 8, dy: 4),
      fontSize: max(15, height * 0.38),
      weight: .bold
    )
  }

  private func drawVehicleMarker(
    point: CGPoint,
    rotationDegrees: CLLocationDirection,
    in bounds: CGRect
  ) {
    let center = scaled(point, in: bounds)
    let radius = max(12, min(bounds.width, bounds.height) * 0.035)
    guard let context = UIGraphicsGetCurrentContext() else { return }

    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotationDegrees * .pi / 180)
    context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.cgColor)
    UIColor.white.setFill()
    UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
      .fill()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    let arrow = UIBezierPath()
    arrow.move(to: CGPoint(x: 0, y: -radius * 0.72))
    arrow.addLine(to: CGPoint(x: radius * 0.52, y: radius * 0.55))
    arrow.addLine(to: CGPoint(x: 0, y: radius * 0.28))
    arrow.addLine(to: CGPoint(x: -radius * 0.52, y: radius * 0.55))
    arrow.close()
    UIColor.systemBlue.setFill()
    arrow.fill()
    context.restoreGState()
  }

  private func drawRoute(_ points: [CGPoint], in bounds: CGRect) {
    guard points.count > 1 else { return }
    let path = UIBezierPath()
    path.move(to: scaled(points[0], in: bounds))
    for point in points.dropFirst() {
      path.addLine(to: scaled(point, in: bounds))
    }
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = max(9, bounds.height * 0.022)
    UIColor.white.withAlphaComponent(0.9).setStroke()
    path.stroke()
    path.lineWidth = max(6, bounds.height * 0.014)
    UIColor.systemBlue.setStroke()
    path.stroke()
  }

  private func drawMapMarker(
    code: String,
    point: CGPoint,
    color: UIColor,
    in bounds: CGRect
  ) {
    let center = scaled(point, in: bounds)
    let diameter = max(28, min(bounds.width, bounds.height) * 0.085)
    let rect = CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
    color.setFill()
    UIBezierPath(ovalIn: rect).fill()
    UIColor.white.setStroke()
    let border = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
    border.lineWidth = max(2, diameter * 0.06)
    border.stroke()
    drawCenteredText(code, in: rect, fontSize: diameter * 0.43, weight: .bold)
  }

  private func drawMapCaption(_ navigation: PiPNavigationContent, in bounds: CGRect) {
    let height = max(54, bounds.height * 0.15)
    let rect = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    UIColor.black.withAlphaComponent(0.68).setFill()
    UIRectFill(rect)
    let text = "\(navigation.distanceMeters) m 後\(navigation.maneuver.title)・\(navigation.instruction)"
    drawCenteredText(
      text,
      in: rect.insetBy(dx: 14, dy: 4),
      fontSize: max(18, height * 0.38),
      weight: .bold
    )
  }

  private func drawGuidance(_ navigation: PiPNavigationContent, in bounds: CGRect) {
    drawNavigationGradient(in: bounds)
    let iconSide = min(bounds.height * 0.56, bounds.width * 0.26)
    let iconRect = CGRect(
      x: bounds.width * 0.08,
      y: bounds.midY - iconSide / 2,
      width: iconSide,
      height: iconSide
    )
    drawManeuverIcon(navigation.maneuver, in: iconRect)

    let textRect = CGRect(
      x: bounds.width * 0.38,
      y: bounds.height * 0.18,
      width: bounds.width * 0.55,
      height: bounds.height * 0.64
    )
    drawGuidanceText(navigation, in: textRect, compact: false)
  }

  private func drawCompactGuidance(_ navigation: PiPNavigationContent, in bounds: CGRect) {
    let cardHeight = max(72, bounds.height * 0.28)
    let card = CGRect(
      x: bounds.width * 0.025,
      y: bounds.maxY - cardHeight - bounds.height * 0.025,
      width: bounds.width * 0.95,
      height: cardHeight
    )
    let path = UIBezierPath(roundedRect: card, cornerRadius: cardHeight * 0.14)
    UIColor(red: 0.08, green: 0.27, blue: 0.78, alpha: 0.94).setFill()
    path.fill()

    let iconRect = CGRect(
      x: card.minX + cardHeight * 0.13,
      y: card.minY + cardHeight * 0.18,
      width: cardHeight * 0.64,
      height: cardHeight * 0.64
    )
    drawManeuverIcon(navigation.maneuver, in: iconRect)
    let textRect = CGRect(
      x: iconRect.maxX + cardHeight * 0.12,
      y: card.minY + cardHeight * 0.12,
      width: card.maxX - iconRect.maxX - cardHeight * 0.24,
      height: cardHeight * 0.76
    )
    drawGuidanceText(navigation, in: textRect, compact: true)
  }

  private func drawNavigationGradient(in bounds: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let colors = [
      UIColor(red: 0.23, green: 0.16, blue: 0.72, alpha: 1).cgColor,
      UIColor(red: 0.02, green: 0.46, blue: 0.95, alpha: 1).cgColor,
    ] as CFArray
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
      )
    else { return }
    context.drawLinearGradient(
      gradient,
      start: bounds.origin,
      end: CGPoint(x: bounds.maxX, y: bounds.maxY),
      options: []
    )
  }

  private func drawManeuverIcon(_ maneuver: ManeuverType, in rect: CGRect) {
    let configuration = UIImage.SymbolConfiguration(
      pointSize: min(rect.width, rect.height),
      weight: .bold
    )
    UIImage(systemName: maneuver.symbolName, withConfiguration: configuration)?
      .withTintColor(.white, renderingMode: .alwaysOriginal)
      .draw(in: rect)
  }

  private func drawGuidanceText(
    _ navigation: PiPNavigationContent,
    in rect: CGRect,
    compact: Bool
  ) {
    let distanceFontSize = compact ? rect.height * 0.36 : rect.height * 0.38
    let instructionFontSize = compact ? rect.height * 0.2 : rect.height * 0.18
    let distanceRect = CGRect(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: rect.height * 0.52
    )
    let instructionRect = CGRect(
      x: rect.minX,
      y: distanceRect.maxY,
      width: rect.width,
      height: rect.height * 0.48
    )
    drawText(
      "\(navigation.distanceMeters) m",
      in: distanceRect,
      fontSize: max(18, distanceFontSize),
      weight: .bold
    )
    drawText(
      navigation.instruction,
      in: instructionRect,
      fontSize: max(14, instructionFontSize),
      weight: .semibold
    )
  }

  private func drawCenteredText(
    _ text: String,
    in rect: CGRect,
    fontSize: CGFloat,
    weight: UIFont.Weight
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
      .foregroundColor: UIColor.white,
      .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
  }

  private func drawText(
    _ text: String,
    in rect: CGRect,
    fontSize: CGFloat,
    weight: UIFont.Weight
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
      .foregroundColor: UIColor.white,
      .paragraphStyle: paragraph,
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
  }

  private func scaled(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
    CGPoint(
      x: bounds.minX + point.x * bounds.width,
      y: bounds.minY + point.y * bounds.height
    )
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}
