# Blipark iOS

Blipark 的正式 iOS App。專案使用 SwiftUI、MapKit 與 protocol-based repositories，最低支援 iOS 17。

## 開啟與建置

```bash
xcodebuild \
  -project Blipark.xcodeproj \
  -scheme Blipark \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/BliparkDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build
```

App 的正式畫面只依賴 `DestinationSearchProviding`、`ParkingDataProviding`、`PlanRepository` 等介面。開發資料與未來 API 實作可替換，但不應改寫主要 UI 或 domain logic。

## 建立可搜尋的開發資料

1. 使用 Debug build 開啟「我的 → 開發者工具」。
2. 新增測試情境，利用 MapKit 搜尋或地圖點選設定目的地。
3. 加入多個附近停車點；未知格位或費率請留白／選「未知」。
4. 儲存後回到首頁搜尋目的地名稱。
5. 選取目的地即可在地圖與清單查看候選；距離明確標示為直線約略距離。

一般 MapKit 搜尋結果也會顯示，但如果沒有對應 parking provider 資料，探索頁會呈現誠實的 empty state，不會合成停車點。

## 驗證 Phase 1–4 使用流程

```text
Debug 開發者工具建立情境
→ 首頁搜尋目的地
→ 地圖／清單檢視候選
→ 設定車種、類型、收費與直線距離
→ 增刪並拖曳候選順序
→ 儲存 Plan
→ 首頁或 Plans Tab 查看與再次編輯
```

Plan 會保存候選 snapshot 與手動順序。之後修改或刪除 TestDataset 不會讓既有 Plan crash，也不會偷偷覆蓋使用者的內容。

完整架構與資料邊界請見 [`docs/architecture.md`](docs/architecture.md)，產品實作計畫請見 [`plan/firstPlan.md`](plan/firstPlan.md)。

