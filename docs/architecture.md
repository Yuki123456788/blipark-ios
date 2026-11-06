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

Debug build 可從「我的 → 開發者工具」建立、編輯、啟用、停用或刪除 `TestDataset`。測試情境自訂名稱與最終目的地地標名稱分開保存。目的地與停車點可貼上 Apple Maps／Google Maps 連結自動帶入，也可用 MapKit 搜尋、點擊既有地標，或長按地圖加入沒有地標的任意位置；介面不要求手動輸入地址或座標。目的地確定後，同頁直接顯示目的地置中的停車地圖，選到位置後才呈現停車類型、收費與車種設定。資料會保存於 `test-datasets-v1.json`。停車點必須落在以目的地為中心的 4,000 × 4,000 公尺 MapKit 投影方框內。這是 Snapshot 的開發資料上限，不是一般使用者的搜尋策略。JSON 匯入與手動儲存都會驗證 schema、ID、座標、範圍、車種與格位數，任何錯誤都不覆蓋既有資料。

導航實測參數另存於 `developer-navigation-v1.json`。依目前決策，預設使用 5×5 圖磚、80 公尺固定觀察距離與 PiP controls style 2；這些設定不會出現在一般使用者操作介面。

Debug build 的正式搜尋只查詢啟用 TestDataset 的最終目的地。搜尋框取得焦點時直接列出目的地，再以本機文字篩選；停車點不會成為搜尋結果，一般流程也不呼叫 MapKit autocomplete 或地點搜尋。選取目的地後，parking provider 才回傳該情境的停車點。正式畫面不顯示 Mock／Test 標籤。Release build 不掛載 TestDataset provider，在正式 API 尚未接入時呈現誠實的無資料狀態。

Apple Maps／Google Maps 連結匯入只存在於開發者資料編輯器。完整連結直接解析座標，短連結經網路展開；只有地點文字而沒有座標時，才在這個開發工具流程使用 MapKit 解析。

## 推薦與 Plan

目前探索頁保留 provider 的資料順序，不預選、不推薦，也不依距離或名稱重新排序。一般使用者看到的方框由 `informationRangeWidthMeters` 決定，代表目的地置中的方形查看範圍；舊偏好沒有此欄位時，使用全域導航觸發距離，預設為 2 × 2 公里。調整範圍、車種或停車類型會即時更新地圖及清單，但不暴露 Snapshot 的固定 4 公里上限。使用者可在同頁查看所有可見停車點、收費、類型、直線距離及街景佔位，再手動選取並排列候選嘗試順序；此順序與本次策略一起保存進 Plan。

`ParkingPlan` 保存 destination 與候選 snapshot；TestDataset 後續更新或刪除不會自動改寫個人計畫。`ParkingRecommendationService` 保留供後續推薦功能使用，目前一般建立流程不呼叫它。導覽 Session 與 POC adapter 屬於 Phase 5，Phase 1–4 不宣稱已完成 PiP 或背景導航。

