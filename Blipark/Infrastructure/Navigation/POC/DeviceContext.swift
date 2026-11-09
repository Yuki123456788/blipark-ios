import Foundation
import UIKit

struct DeviceContext: Equatable {
  let environment: String
  let model: String
  let systemVersion: String

  static var current: DeviceContext {
    #if targetEnvironment(simulator)
      let environment = "模擬器"
      let model =
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        ?? UIDevice.current.model
    #else
      let environment = "實機"
      let model = UIDevice.current.model
    #endif

    return DeviceContext(
      environment: environment,
      model: model,
      systemVersion: UIDevice.current.systemVersion
    )
  }
}
