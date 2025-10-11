# SVG 到 PNG 轉換指南

## 概述
由於 `flutter_launcher_icons` 不支援 SVG 格式，我們需要將 SVG 文件轉換為 PNG 格式。

## 需要轉換的文件

### 主要圖標
- `tram_icon_android.svg` → `tram_icon_android.png` (192x192)
- `tram_icon_high.svg` → `tram_icon_high.png` (144x144)
- `tram_icon_medium.svg` → `tram_icon_medium.png` (96x96)
- `tram_icon_minimal.svg` → `tram_icon_minimal.png` (48x48)

### 前景圖標
- `tram_icon_foreground_android.svg` → `tram_icon_foreground_android.png` (108x108)

## 推薦轉換工具

### 1. **Convertio.co** (主要推薦)
- **網址**: https://convertio.co/zh/
- **優點**: 介面友好，支援多種格式
- **步驟**:
  1. 訪問網站
  2. 上傳 SVG 文件
  3. 選擇輸出格式為 PNG
  4. 設定解析度 (建議 300 DPI)
  5. 下載轉換後的 PNG 文件

### 2. **I Love Compress**
- **網址**: https://ilovecompress.com/svg-to-png
- **優點**: 直接在瀏覽器中轉換，無需上傳文件
- **特點**: 確保數據安全

### 3. **DesignFast**
- **網址**: https://designfast.io/toolkit/svg-to-png-converter
- **優點**: 快速且免費，支援自定義解析度
- **適用**: 高質量輸出需求

### 4. **AnyConvert**
- **網址**: https://anyconvert.app/svg-to-png
- **優點**: 易於使用，支援最大 50MB 文件

## 轉換設定建議

### 解析度設定
- **低密度圖標**: 48x48, 96x96 → 72 DPI
- **高密度圖標**: 144x144, 192x192 → 300 DPI
- **前景圖標**: 108x108 → 300 DPI

### 輸出格式
- **格式**: PNG-24
- **背景**: 透明
- **抗鋸齒**: 啟用
- **壓縮**: 無損

## 轉換步驟

### 步驟 1: 準備文件
1. 確保所有 SVG 文件都在 `assets/icon/` 目錄中
2. 檢查 SVG 文件的尺寸設定是否正確

### 步驟 2: 選擇轉換工具
1. 根據需求選擇合適的轉換工具
2. 建議使用 Convertio.co 進行主要轉換

### 步驟 3: 執行轉換
1. 上傳 SVG 文件
2. 設定輸出參數
3. 執行轉換
4. 下載 PNG 文件

### 步驟 4: 文件命名
1. 將轉換後的 PNG 文件重命名為對應的名稱
2. 確保文件名與 `pubspec.yaml` 中的配置一致

## 轉換完成後的驗證

### 文件檢查
- [ ] 所有 PNG 文件都已生成
- [ ] 文件名與配置一致
- [ ] 文件尺寸正確
- [ ] 圖片質量良好

### 配置驗證
- [ ] `pubspec.yaml` 中的路徑正確
- [ ] 所有平台配置都已更新
- [ ] 依賴已更新 (`flutter pub get`)

### 圖標生成測試
- [ ] 運行 `flutter pub run flutter_launcher_icons:main`
- [ ] 檢查生成的圖標文件
- [ ] 驗證各平台的圖標顯示

## 常見問題

### Q: 轉換後的 PNG 文件太大怎麼辦？
A: 使用 PNG 壓縮工具，如 TinyPNG 或 ImageOptim

### Q: 轉換後的圖片模糊怎麼辦？
A: 確保使用足夠高的解析度 (300 DPI)，並啟用抗鋸齒

### Q: 如何保持透明背景？
A: 選擇 PNG-24 格式，並確保不添加背景色

### Q: 轉換失敗怎麼辦？
A: 檢查 SVG 文件是否有效，嘗試使用不同的轉換工具

## 下一步

轉換完成後：
1. 更新 `pubspec.yaml` 配置
2. 運行 `flutter pub get`
3. 執行 `flutter pub run flutter_launcher_icons:main`
4. 測試生成的圖標

## 相關文檔
- [Flutter 圖標配置指南](https://pub.dev/packages/flutter_launcher_icons)
- [Android 圖標設計指南](https://developer.android.com/guide/practices/ui_guidelines/icon_design)
- [iOS 圖標設計指南](https://developer.apple.com/design/human-interface-guidelines/ios/icons-and-images/app-icon/)
