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

完整架構與資料邊界請見 [`docs/architecture.md`](docs/architecture.md)，產品實作計畫請見 [`plan/firstPlan.md`](plan/firstPlan.md)。

