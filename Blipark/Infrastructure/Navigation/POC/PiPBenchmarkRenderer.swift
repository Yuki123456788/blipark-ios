import AVFoundation
import CoreMedia
import UIKit

final class PiPBenchmarkMapSource: @unchecked Sendable {
  static let sourceCoverageMeters: Double = 4_000
  static let navigationViewportWidthMeters: Double = 300

  let image: UIImage
  let cgImage: CGImage
  let geographicWidthMeters: Double

  var mapScaleMultiplier: CGFloat {
    CGFloat(geographicWidthMeters / Self.navigationViewportWidthMeters)
  }

  init?(image: UIImage, geographicWidthMeters: Double) {
    guard let cgImage = image.cgImage else { return nil }
    self.image = image
    self.cgImage = cgImage
    self.geographicWidthMeters = geographicWidthMeters
  }
}

enum PiPBenchmarkRenderError: LocalizedError {
  case pixelBuffer(Int32)
  case missingBaseAddress
  case contextCreation
  case formatDescription(OSStatus)
  case sampleBuffer(OSStatus)

  var errorDescription: String? {
    switch self {
    case .pixelBuffer(let status): "無法取得 PixelBuffer（\(status)）"
    case .missingBaseAddress: "PixelBuffer 沒有可繪製的記憶體"
    case .contextCreation: "無法建立 Core Graphics Context"
    case .formatDescription(let status): "無法建立影像格式（\(status)）"
    case .sampleBuffer(let status): "無法建立 SampleBuffer（\(status)）"
    }
  }
}

final class PiPBenchmarkPixelBufferProvider: @unchecked Sendable {
  private let width: Int
  private let height: Int
  private let pool: CVPixelBufferPool?

  init(size: CGSize, usesPool: Bool) throws {
    width = Int(size.width)
    height = Int(size.height)
    guard usesPool else {
      pool = nil
      return
    }

    let pixelAttributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height,
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    let poolAttributes: [CFString: Any] = [
      kCVPixelBufferPoolMinimumBufferCountKey: 3
    ]
    var createdPool: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(
      kCFAllocatorDefault,
      poolAttributes as CFDictionary,
      pixelAttributes as CFDictionary,
      &createdPool
    )
    guard status == kCVReturnSuccess, let createdPool else {
      throw PiPBenchmarkRenderError.pixelBuffer(status)
    }
    pool = createdPool

    // Hold all three allocations until the loop finishes so the pool cannot
    // satisfy every request by immediately reusing the same buffer.
    var prewarmedBuffers: [CVPixelBuffer] = []
    for _ in 0..<3 {
      var pixelBuffer: CVPixelBuffer?
      let prewarmStatus = CVPixelBufferPoolCreatePixelBuffer(
        kCFAllocatorDefault,
        createdPool,
        &pixelBuffer
      )
      guard prewarmStatus == kCVReturnSuccess, let pixelBuffer else {
        throw PiPBenchmarkRenderError.pixelBuffer(prewarmStatus)
      }
      prewarmedBuffers.append(pixelBuffer)
    }
    prewarmedBuffers.removeAll()
  }

  func makePixelBuffer() throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status: CVReturn
    if let pool {
      let auxiliary: [CFString: Any] = [
        kCVPixelBufferPoolAllocationThresholdKey: 6
      ]
      status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
        kCFAllocatorDefault,
        pool,
        auxiliary as CFDictionary,
        &pixelBuffer
      )
    } else {
      let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
      ]
      status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
      )
    }
    guard status == kCVReturnSuccess, let pixelBuffer else {
      throw PiPBenchmarkRenderError.pixelBuffer(status)
    }
    return pixelBuffer
  }
}

struct PiPBenchmarkRenderedFrame {
  let pixelBuffer: CVPixelBuffer
  let pixelBufferMilliseconds: Double
  let renderMilliseconds: Double
}

protocol MapFrameRenderer {
  func render(
    source: PiPBenchmarkMapSource,
    state: MapAnimationState,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize
  ) throws -> PiPBenchmarkRenderedFrame
}

struct LegacyMapFrameRenderer: MapFrameRenderer {
  func render(
    source: PiPBenchmarkMapSource,
    state: MapAnimationState,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize
  ) throws -> PiPBenchmarkRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime
    let renderStart = allocationEnd

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let intermediate = UIGraphicsImageRenderer(size: outputSize, format: format).image {
      rendererContext in
      let context = rendererContext.cgContext
      PiPBenchmarkDrawing.clear(context: context, size: outputSize)
      PiPBenchmarkDrawing.drawMap(
        image: source.image,
        sourceSize: source.image.size,
        mapScaleMultiplier: source.mapScaleMultiplier,
        state: state,
        outputSize: outputSize,
        context: context
      )
      PiPBenchmarkDrawing.drawVehicleIfNeeded(
        state: state, outputSize: outputSize, context: context)
    }

    try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }
      intermediate.draw(in: CGRect(origin: .zero, size: size))
    }
    let renderEnd = ProcessInfo.processInfo.systemUptime
    return PiPBenchmarkRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (renderEnd - renderStart) * 1_000
    )
  }
}

struct DirectMapFrameRenderer: MapFrameRenderer {
  func render(
    source: PiPBenchmarkMapSource,
    state: MapAnimationState,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize
  ) throws -> PiPBenchmarkRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime
    let renderStart = allocationEnd

    try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1, y: -1)
      PiPBenchmarkDrawing.clear(context: context, size: size)
      PiPBenchmarkDrawing.drawMap(
        cgImage: source.cgImage,
        mapScaleMultiplier: source.mapScaleMultiplier,
        state: state,
        outputSize: size,
        context: context
      )
      PiPBenchmarkDrawing.drawVehicleIfNeeded(state: state, outputSize: size, context: context)
    }
    let renderEnd = ProcessInfo.processInfo.systemUptime
    return PiPBenchmarkRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (renderEnd - renderStart) * 1_000
    )
  }
}

enum PiPBenchmarkDrawing {
  static func withPixelBufferContext(
    _ pixelBuffer: CVPixelBuffer,
    draw: (CGContext, CGSize) -> Void
  ) throws {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw PiPBenchmarkRenderError.missingBaseAddress
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard
      let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { throw PiPBenchmarkRenderError.contextCreation }
    context.interpolationQuality = .high
    draw(context, CGSize(width: width, height: height))
  }

  static func clear(context: CGContext, size: CGSize) {
    context.saveGState()
    context.setBlendMode(.copy)
    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    context.restoreGState()
  }

  static func drawMap(
    image: UIImage,
    sourceSize: CGSize,
    mapScaleMultiplier: CGFloat,
    state: MapAnimationState,
    outputSize: CGSize,
    context: CGContext
  ) {
    context.saveGState()
    applyMapTransform(
      sourceSize: sourceSize,
      mapScaleMultiplier: mapScaleMultiplier,
      state: state,
      outputSize: outputSize,
      context: context
    )
    image.draw(in: CGRect(origin: .zero, size: sourceSize))
    context.restoreGState()
  }

  static func drawMap(
    cgImage: CGImage,
    mapScaleMultiplier: CGFloat,
    state: MapAnimationState,
    outputSize: CGSize,
    context: CGContext
  ) {
    let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
    context.saveGState()
    applyMapTransform(
      sourceSize: sourceSize,
      mapScaleMultiplier: mapScaleMultiplier,
      state: state,
      outputSize: outputSize,
      context: context
    )
    drawUpright(
      cgImage: cgImage,
      in: CGRect(origin: .zero, size: sourceSize),
      context: context
    )
    context.restoreGState()
  }

  /// `CGContext.draw(CGImage)` assumes Quartz's Y-up image space. Callers in
  /// this project first convert their bitmap context to UIKit's Y-down space,
  /// so drawing without this local flip mirrors the map while overlay paths
  /// remain unmirrored.
  static func drawUpright(
    cgImage: CGImage,
    in rect: CGRect,
    context: CGContext
  ) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
  }

  static func drawVehicleIfNeeded(
    state: MapAnimationState,
    outputSize: CGSize,
    context: CGContext
  ) {
    guard state.showsVehicle else { return }
    let center = CGPoint(
      x: state.vehiclePoint.x * outputSize.width,
      y: state.vehiclePoint.y * outputSize.height
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
    arrow.move(to: CGPoint(x: 0, y: -radius * 0.78))
    arrow.addLine(to: CGPoint(x: radius * 0.52, y: radius * 0.58))
    arrow.addLine(to: CGPoint(x: 0, y: radius * 0.28))
    arrow.addLine(to: CGPoint(x: -radius * 0.52, y: radius * 0.58))
    arrow.closeSubpath()
    context.addPath(arrow)
    context.setFillColor(UIColor.systemBlue.cgColor)
    context.fillPath()
    context.restoreGState()
  }

  private static func applyMapTransform(
    sourceSize: CGSize,
    mapScaleMultiplier: CGFloat,
    state: MapAnimationState,
    outputSize: CGSize,
    context: CGContext
  ) {
    let scale =
      max(
        outputSize.width / max(sourceSize.width, 1),
        outputSize.height / max(sourceSize.height, 1)
      ) * max(1, mapScaleMultiplier)
    context.translateBy(
      x: outputSize.width * (0.5 + state.translation.x),
      y: outputSize.height * (0.5 + state.translation.y)
    )
    context.rotate(by: state.rotationRadians)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -sourceSize.width / 2, y: -sourceSize.height / 2)
  }
}

final class PiPBenchmarkSampleBufferFactory: @unchecked Sendable {
  private let targetFPS: Int
  private let cachesFormatDescription: Bool
  private var cachedFormatDescription: CMVideoFormatDescription?
  private var lastPresentationTimeStamp = CMTime.invalid

  init(targetFPS: Int, cachesFormatDescription: Bool) {
    self.targetFPS = targetFPS
    self.cachesFormatDescription = cachesFormatDescription
  }

  func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) throws -> CMSampleBuffer {
    let formatDescription: CMVideoFormatDescription
    if cachesFormatDescription, let cachedFormatDescription {
      formatDescription = cachedFormatDescription
    } else {
      var created: CMVideoFormatDescription?
      let status = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &created
      )
      guard status == noErr, let created else {
        throw PiPBenchmarkRenderError.formatDescription(status)
      }
      formatDescription = created
      if cachesFormatDescription {
        cachedFormatDescription = created
      }
    }

    var presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
    if lastPresentationTimeStamp.isValid,
      CMTimeCompare(presentationTimeStamp, lastPresentationTimeStamp) <= 0
    {
      presentationTimeStamp = CMTimeAdd(
        lastPresentationTimeStamp,
        CMTime(value: 1, timescale: 1_000_000_000)
      )
    }
    lastPresentationTimeStamp = presentationTimeStamp
    var timing = CMSampleTimingInfo(
      duration: CMTime(seconds: 1 / Double(targetFPS), preferredTimescale: 60_000),
      presentationTimeStamp: presentationTimeStamp,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else {
      throw PiPBenchmarkRenderError.sampleBuffer(status)
    }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer,
      createIfNecessary: true
    ) as? [NSMutableDictionary], let attachment = attachments.first {
      attachment[kCMSampleAttachmentKey_DisplayImmediately] = true
    }
    return sampleBuffer
  }
}
