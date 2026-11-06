import SwiftUI
import UniformTypeIdentifiers

struct DeveloperToolsView: View {
  @StateObject private var model: TestDatasetListModel
  @State private var editingDataset: TestDataset?
  @State private var showsNewDataset = false
  @State private var showsImporter = false
  @State private var showsExporter = false
  @State private var exportDocument: DatasetArchiveDocument?

  init(repository: any TestDatasetRepository) {
    _model = StateObject(wrappedValue: TestDatasetListModel(repository: repository))
  }

  var body: some View {
    List {
      Section {
        NavigationLink {
          DeveloperNavigationSettingsView()
        } label: {
          Label("導航實測參數", systemImage: "wrench.and.screwdriver")
        }
      } footer: {
        Text("進階導航參數只存在於開發工具，不會出現在一般操作流程。")
      }

      Section("測試資料情境") {
        if model.isLoading && model.datasets.isEmpty {
          HStack { Spacer(); ProgressView(); Spacer() }
        } else if model.datasets.isEmpty {
          ContentUnavailableView(
            "尚無測試情境",
            systemImage: "map",
            description: Text("建立真實目的地及附近停車點，正式搜尋流程就能讀取。")
          )
        } else {
          ForEach(model.datasets) { dataset in
            Button { editingDataset = dataset } label: {
              HStack(spacing: 12) {
                Image(systemName: dataset.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                  .foregroundStyle(dataset.isEnabled ? BliparkStyle.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text(dataset.destination.name).foregroundStyle(.primary)
                  Text("\(dataset.parkingLocations.count) 個停車點")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
              Button(dataset.isEnabled ? "停用" : "啟用") {
                Task { await model.setEnabled(dataset, enabled: !dataset.isEnabled) }
              }
              .tint(dataset.isEnabled ? .orange : BliparkStyle.accent)
            }
            .swipeActions {
              Button("刪除", role: .destructive) {
                Task { await model.delete(dataset) }
              }
            }
          }
        }
      }

      Section("搬移資料") {
        Button("匯入 JSON", systemImage: "square.and.arrow.down") { showsImporter = true }
        Button("匯出全部 JSON", systemImage: "square.and.arrow.up") {
          Task {
            guard let data = await model.exportData() else { return }
            exportDocument = DatasetArchiveDocument(data: data)
            showsExporter = true
          }
        }
        .disabled(model.datasets.isEmpty)
      }
    }
    .navigationTitle("開發者工具")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("新增", systemImage: "plus") { showsNewDataset = true }
      }
    }
    .task { await model.load() }
    .refreshable { await model.load() }
    .sheet(isPresented: $showsNewDataset) {
      TestDatasetEditorView(repository: model.repository) { Task { await model.load() } }
    }
    .sheet(item: $editingDataset) { dataset in
      TestDatasetEditorView(dataset: dataset, repository: model.repository) {
        Task { await model.load() }
      }
    }
    .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
      switch result {
      case .success(let url):
        let canAccess = url.startAccessingSecurityScopedResource()
        defer { if canAccess { url.stopAccessingSecurityScopedResource() } }
        do {
          let data = try Data(contentsOf: url)
          Task { await model.importData(data) }
        } catch {
          model.errorMessage = error.localizedDescription
        }
      case .failure(let error):
        model.errorMessage = error.localizedDescription
      }
    }
    .fileExporter(
      isPresented: $showsExporter,
      document: exportDocument,
      contentType: .json,
      defaultFilename: "blipark-test-datasets"
    ) { result in
      if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
      exportDocument = nil
    }
    .alert("無法完成操作", isPresented: errorBinding) {
      Button("好") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "未知錯誤")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )
  }
}

