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
2. 新增測試情境，可貼上 Apple Maps／Google Maps 連結自動帶入位置，或使用 MapKit、地圖點選與手動座標。
3. 加入目的地周圍 4 × 4 公里方框內的停車點；未知格位或費率請留白／選「未知」。
4. 儲存後回到首頁進入搜尋；輸入框取得焦點時會直接列出所有已啟用的目的地與停車點。
5. 選取任一地點後，從平列清單手動選擇停車點；地圖只標示目前選擇，不會自動推薦或排序。

正式搜尋頁不呼叫 MapKit 地點搜尋或 autocomplete。MapKit 只保留在開發者資料編輯器中，協助建立測試位置；Release build 在正式 API 接入前會呈現誠實的 empty state。

## 驗證 Phase 1–4 使用流程

```text
Debug 開發者工具建立情境
→ 首頁搜尋目的地
→ 從 4 × 4 公里範圍內的平列清單手動選擇停車點
→ 設定車種、類型、收費與直線距離
→ 確認已選停車點（目前不套用推薦或排序）
→ 儲存 Plan
→ 首頁或 Plans Tab 查看與再次編輯
```

Plan 會保存候選 snapshot。之後修改或刪除 TestDataset 不會讓既有 Plan crash，也不會偷偷覆蓋使用者的內容。

完整架構與資料邊界請見 [`docs/architecture.md`](docs/architecture.md)，產品實作計畫請見 [`plan/firstPlan.md`](plan/firstPlan.md)。

