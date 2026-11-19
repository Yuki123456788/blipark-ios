import SwiftUI

@MainActor
final class GeneralSettingsModel: ObservableObject {
  @Published var preferences = AppPreferences.standard
  @Published private(set) var isLoading = true
  @Published var errorMessage: String?

  private let repository: any PreferencesRepository

  init(repository: any PreferencesRepository) {
    self.repository = repository
  }

  func load() async {
    do {
      preferences = try await repository.preferences()
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  func save() async {
    do {
      try await repository.save(preferences)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct GeneralSettingsView: View {
  @StateObject private var model: GeneralSettingsModel

  init(repository: any PreferencesRepository) {
    _model = StateObject(wrappedValue: GeneralSettingsModel(repository: repository))
  }

  var body: some View {
    Form {
      Section {
        Picker("接近目的地時開始提示", selection: $model.preferences.guidanceTriggerDistanceMeters) {
          Text("1 km").tag(1_000.0)
          Text("2 km").tag(2_000.0)
          Text("3 km").tag(3_000.0)
        }
        .pickerStyle(.segmented)
      } header: {
        Text("觸發距離")
      } footer: {
        Text("沒有在出發前另外調整時，停車引導會使用這個距離。其他工程參數只放在 Debug 開發者工具。")
      }
    }
    .navigationTitle("App 設定")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
    .onChange(of: model.preferences.guidanceTriggerDistanceMeters) { _, _ in
      guard !model.isLoading else { return }
      Task { await model.save() }
    }
    .alert("無法儲存設定", isPresented: errorBinding) {
      Button("好") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "未知錯誤")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
  }
}

