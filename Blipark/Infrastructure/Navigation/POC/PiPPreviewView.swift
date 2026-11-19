import AVFoundation
import SwiftUI
import UIKit

struct PiPPreviewView: UIViewRepresentable {
  let displayLayer: AVSampleBufferDisplayLayer

  func makeUIView(context: Context) -> PiPDisplayView {
    let view = PiPDisplayView()
    view.attach(displayLayer)
    return view
  }

  func updateUIView(_ uiView: PiPDisplayView, context: Context) {
    uiView.attach(displayLayer)
    uiView.setNeedsLayout()
  }
}

final class PiPDisplayView: UIView {
  private weak var displayLayer: AVSampleBufferDisplayLayer?

  func attach(_ displayLayer: AVSampleBufferDisplayLayer) {
    guard self.displayLayer !== displayLayer else { return }
    self.displayLayer?.removeFromSuperlayer()
    self.displayLayer = displayLayer
    layer.addSublayer(displayLayer)
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    displayLayer?.frame = bounds
  }
}
