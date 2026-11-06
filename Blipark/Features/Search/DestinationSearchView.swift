import SwiftUI

struct DestinationSearchView: View {
  @StateObject private var model: DestinationSearchModel
  @State private var query = ""
  @FocusState private var isSearchFocused: Bool

  private let parkingProvider: any ParkingDataProviding

  init(
    destinationProvider: any DestinationSearchProviding,
    parkingProvider: any ParkingDataProviding
  ) {
    _model = StateObject(wrappedValue: DestinationSearchModel(provider: destinationProvider))
    self.parkingProvider = parkingProvider
  }

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Group {
        if model.isSearching && model.results.isEmpty {
          ProgressView("正在搜尋…")
        } else if let error = model.errorMessage {
          ContentUnavailableView(
            "無法讀取地點",
            systemImage: "exclamationmark.magnifyingglass",
            description: Text(error)
          )
        } else if model.results.isEmpty {
          ContentUnavailableView(
            query.isEmpty ? "尚無可用地點" : "找不到符合的地點",
            systemImage: "mappin.slash",
            description: Text(
              query.isEmpty
                ? "請先到開發者工具新增並啟用測試資料情境。"
                : "目前只會篩選開發者工具中已啟用情境的最終目的地。"
            )
          )
        } else {
          List(model.results) { destination in
            NavigationLink {
              DestinationExploreView(destination: destination, parkingProvider: parkingProvider)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: resultSymbol(destination))
                  .foregroundStyle(BliparkStyle.brand)
                  .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                  Text(destination.name).font(.headline)
                  Text(destination.address ?? "已儲存的測試目的地")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
              .padding(.vertical, 4)
            }
          }
          .listStyle(.plain)
        }
      }
    }
    .navigationTitle("搜尋目的地")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await model.load()
      isSearchFocused = true
    }
    .onChange(of: query) { _, value in model.filter(value) }
    .onChange(of: isSearchFocused) { _, focused in
      if focused && model.allResults.isEmpty { Task { await model.load() } }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") { isSearchFocused = false }
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("篩選已建立的地點", text: $query)
          .focused($isSearchFocused)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        if !query.isEmpty {
          Button { query = "" } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清除")
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 38)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

      Button("關閉") { isSearchFocused = false }
        .font(.subheadline.weight(.medium))
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private func resultSymbol(_: Destination) -> String {
    "mappin.and.ellipse"
  }
}

