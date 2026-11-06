import SwiftUI

struct MapLinkImportField: View {
  @Binding var link: String
  var prompt = "貼上 Apple Maps 或 Google Maps 連結"
  let onImport: (Destination) -> Void

  @State private var isImporting = false
  @State private var statusMessage: String?
  @State private var importTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        TextField(prompt, text: $link)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
          .onSubmit { startImport() }
        if isImporting {
          ProgressView().controlSize(.small)
        } else {
          Button("匯入") { startImport() }
            .disabled(!ExternalMapLinkParser.isSupportedLink(link))
        }
      }
      if let statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(statusMessage == "已帶入位置" ? BliparkStyle.brand : .red)
      }
    }
    .onChange(of: link) { _, value in
      importTask?.cancel()
      statusMessage = nil
      guard ExternalMapLinkParser.isSupportedLink(value) else { return }
      importTask = Task {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        await importLink()
      }
    }
    .onDisappear { importTask?.cancel() }
  }

  private func startImport() {
    importTask?.cancel()
    importTask = Task { await importLink() }
  }

  @MainActor
  private func importLink() async {
    isImporting = true
    defer { isImporting = false }
    do {
      let destination = try await ExternalMapLinkImporter.importLocation(from: link)
      guard !Task.isCancelled else { return }
      onImport(destination)
      statusMessage = "已帶入位置"
    } catch is CancellationError {
      return
    } catch {
      statusMessage = error.localizedDescription
    }
  }
}
