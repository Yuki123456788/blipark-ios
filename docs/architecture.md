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

