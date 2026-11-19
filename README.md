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
2. 輸入獨立的測試情境名稱，再用地標搜尋、點擊地圖地標、長按任意位置，或貼上 Apple Maps／Google Maps 連結設定最終目的地。
3. 目的地確定後直接在同頁地圖加入停車點；點地標或貼連結選取，長按只用於沒有地標的任意位置，接著確認類型、收費與適用車種。
4. 停車測資仍受目的地周圍 4 × 4 公里 Snapshot 內部上限約束；這個工程範圍只顯示在開發者工具。
5. 儲存後回到首頁搜尋；輸入框取得焦點時只會列出各啟用情境的最終目的地，不會混入停車點。
6. 選取目的地後，在同一頁調整停車偏好與 1–4 km 方形查看範圍、總覽地圖與停車資訊、檢視街景佔位，並手動勾選及排列候選順序。

正式搜尋頁不呼叫 MapKit 地點搜尋或 autocomplete。MapKit 只保留在開發者資料編輯器中，協助建立測試位置；Release build 在正式 API 接入前會呈現誠實的 empty state。

## 驗證 Phase 1–4 使用流程

```text
Debug 開發者工具建立情境
→ 首頁搜尋目的地
→ 在目的地探索頁設定停車偏好與動態查看範圍
→ 從地圖、街景佔位與資訊卡綜合查看多個停車點
→ 手動選取候選及調整嘗試順序（目前不自動推薦或排序）
→ 儲存 Plan
→ 首頁或 Plans Tab 查看與再次編輯
```

Plan 會保存候選 snapshot。之後修改或刪除 TestDataset 不會讓既有 Plan crash，也不會偷偷覆蓋使用者的內容。

完整架構與資料邊界請見 [`docs/architecture.md`](docs/architecture.md)，產品實作計畫請見 [`plan/firstPlan.md`](plan/firstPlan.md)。

