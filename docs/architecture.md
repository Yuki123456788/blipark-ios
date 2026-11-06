# App architecture

## 模組責任

- `App`：組合依賴與三個主要 Tab，不持有業務規則。
- `Domain`：目的地、停車位置、偏好、計畫與引導 Session 的穩定產品模型。
- `Data`：資料介面與本機 JSON repository。正式 UI 不知道檔案格式。
- `Features`：SwiftUI 畫面與 feature state。
- `DesignSystem`：少量品牌色與共用卡片樣式。

## 資料流

```text
SwiftUI View → Feature Model / Use Case → Repository Protocol → Local JSON or future API
```

本機資料採 versioned JSON 檔案並以 atomic write 儲存。未來 API response 必須先 mapping 成 `Destination`／`ParkingLocation`，raw response 不可進入正式 UI 或 Plan。

## 三種資料的界線

- `TestDataset`：開發者建立的資料來源情境，模擬未來 API 能查到的目的地與停車位置。
- `ParkingPlan`：使用者選擇後保存的個人規劃；候選以 snapshot 保存，資料來源更新不會覆蓋順序與內容。
- `ParkingGuidanceSession`：一次出發的執行狀態，可來自 Plan 或臨時搜尋，不與 Plan 共用 lifecycle。

PiP／真實定位導航會在後續整合階段透過 adapter 接收 `ParkingGuidanceSession`，而不是讓 domain model 依賴 POC renderer 型別。

## 開發資料

Debug build 可從「我的 → 開發者工具」建立、編輯、啟用、停用或刪除 `TestDataset`。目的地與停車點可用 MapKit 搜尋、地圖點選或手動座標設定；資料會保存於 `test-datasets-v1.json`。JSON 匯入會先驗證 schema、ID、座標、車種與格位數，任何錯誤都不覆蓋既有資料。

導航實測參數另存於 `developer-navigation-v1.json`。依目前決策，預設使用 5×5 圖磚、80 公尺固定觀察距離與 PiP controls style 2；這些設定不會出現在一般使用者操作介面。

Debug build 的正式搜尋會先查詢啟用的 TestDataset，再補上 MapKit 一般地點結果並依名稱與座標去重。測試目的地的 UUID 是持久化識別；正式畫面不顯示 Mock／Test 標籤。Release build 不掛載 TestDataset provider，在正式 API 尚未接入時只提供一般地點搜尋與誠實的無停車資料狀態。完整 Apple Maps／Google Maps 座標連結可直接進入探索；需要網路重導向的短連結會明確回報尚未支援。

## 推薦與 Plan

`ParkingRecommendationService` 先排除不支援車種、類型或直線距離上限的資料，再依免費偏好、距離與 UUID 穩定排序。未知費率不視為免費；畫面也不把直線距離稱為步行距離。

建立 Plan 時先套用全域預設策略，使用者可在儲存前覆寫並手動調整候選順序。`ParkingPlan` 保存 destination 與候選 snapshot；TestDataset 後續更新或刪除不會自動改寫個人計畫。導覽 Session 與 POC adapter 屬於 Phase 5，Phase 1–4 不宣稱已完成 PiP 或背景導航。

