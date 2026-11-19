import SwiftUI

@MainActor
final class DeveloperNavigationSettingsModel: ObservableObject {
  @Published var settings = DeveloperNavigationSettings.standard
  @Published private(set) var isLoading = true
  @Published var message: String?

  private let repository: any DeveloperSettingsRepository

  init(repository: any DeveloperSettingsRepository) {
    self.repository = repository
  }

  func load() async {
    do {
      settings = try await repository.settings()
    } catch {
      message = error.localizedDescription
    }
    isLoading = false
  }

  func save() async {
    do {
      try await repository.save(settings)
      message = "設定已儲存。"
    } catch {
      message = error.localizedDescription
    }
  }

  func restoreDefaults() {
    settings = .standard
  }
}

struct DeveloperNavigationSettingsView: View {
  @Environment(\.appEnvironment) private var environment
  @State private var model: DeveloperNavigationSettingsModel?

  var body: some View {
    Group {
      if let model {
        settingsForm(model)
      } else {
        ProgressView()
          .task {
            let value = DeveloperNavigationSettingsModel(repository: environment.developerSettings)
            model = value
            await value.load()
          }
      }
    }
    .navigationTitle("導航實測參數")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func settingsForm(@ObservedObject _ model: DeveloperNavigationSettingsModel) -> some View {
    Form {
      Section("地圖") {
        Picker("地圖渲染", selection: $model.settings.renderMode) {
          ForEach(NavigationMapRenderMode.allCases) { Text($0.title).tag($0) }
        }
        Picker("圖磚網格", selection: $model.settings.tileGridSize) {
          ForEach(2...5, id: \.self) { Text("\($0) × \($0)").tag($0) }
        }
        .disabled(model.settings.renderMode != .tileGrid)
        Toggle("顯示圖磚邊界", isOn: $model.settings.showsTileBoundaries)
      }

      Section("Camera") {
        Picker("導航視角", selection: $model.settings.zoomMode) {
          ForEach(NavigationZoomMode.allCases) { Text($0.title).tag($0) }
        }
        settingSlider(
          "固定觀察距離",
          value: $model.settings.fixedLookAheadMeters,
          range: 80...1_500,
          step: 25,
          suffix: "m"
        )
        settingSlider(
          "視覺傾斜角",
          value: $model.settings.pitchDegrees,
          range: 0...55,
          step: 5,
          suffix: "°"
        )
      }

      Section("定位與路線") {
        settingSlider(
          "GPS 更新距離",
          value: $model.settings.locationDistanceFilterMeters,
          range: 1...50,
          step: 1,
          suffix: "m"
        )
        settingSlider(
          "定位間移動推估",
          value: $model.settings.positionPredictionLimitSeconds,
          range: 0...4,
          step: 0.5,
          suffix: "s"
        )
        settingSlider(
          "最大水平誤差",
          value: $model.settings.maximumHorizontalAccuracyMeters,
          range: 20...200,
          step: 10,
          suffix: "m"
        )
        settingSlider(
          "偏離路線門檻",
          value: $model.settings.offRouteThresholdMeters,
          range: 30...200,
          step: 5,
          suffix: "m"
        )
        settingSlider(
          "下一路線預載距離",
          value: $model.settings.nextRoutePreviewDistanceMeters,
          range: 50...250,
          step: 10,
          suffix: "m"
        )
      }

      Section {
        Picker("PiP 控制樣式", selection: $model.settings.pipControlsStyle) {
          Text("0・系統預設").tag(0)
          Text("1・隱藏播放").tag(1)
          Text("2・全部隱藏").tag(2)
        }
      } footer: {
        Text("樣式 1／2 使用 POC 驗證過的非公開 controlsStyle，可能有相容性與 App Review 風險；正式導航整合前需再次決定發布策略。")
      }

      Section {
        Button("儲存設定") { Task { await model.save() } }
          .buttonStyle(.borderedProminent)
        Button("恢復 POC 預設值", role: .destructive) { model.restoreDefaults() }
      }

      if let message = model.message {
        Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
      }
    }
  }

  private func settingSlider(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    suffix: String
  ) -> some View {
    VStack(alignment: .leading) {
      HStack {
        Text(title)
        Spacer()
        Text("\(value.wrappedValue, specifier: step < 1 ? "%.1f" : "%.0f") \(suffix)")
          .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range, step: step)
    }
  }
}

