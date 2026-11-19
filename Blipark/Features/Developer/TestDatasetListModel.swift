import Foundation

@MainActor
final class TestDatasetListModel: ObservableObject {
  @Published private(set) var datasets: [TestDataset] = []
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?

  let repository: any TestDatasetRepository

  init(repository: any TestDatasetRepository) {
    self.repository = repository
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      datasets = try await repository.datasets(includeDisabled: true)
        .sorted { $0.updatedAt > $1.updatedAt }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(_ dataset: TestDataset) async {
    do {
      try await repository.delete(id: dataset.id)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func setEnabled(_ dataset: TestDataset, enabled: Bool) async {
    var updated = dataset
    updated.isEnabled = enabled
    updated.updatedAt = .now
    do {
      try await repository.save(updated)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func exportData() async -> Data? {
    do {
      return try await repository.exportArchive()
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func importData(_ data: Data) async {
    do {
      try await repository.importArchive(data)
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

