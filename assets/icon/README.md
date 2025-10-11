# 輕鐵應用程式圖標集

## 概述
本目錄包含輕鐵應用程式的各種圖標文件，專門針對不同平台和密度要求進行優化。

## Android 開發文檔最小尺寸要求

### 密度分類
- **mdpi**: 48x48 px (1x)
- **hdpi**: 72x72 px (1.5x)
- **xhdpi**: 96x96 px (2x)
- **xxhdpi**: 144x144 px (3x)
- **xxxhdpi**: 192x192 px (4x)

### 自適應圖標要求
- **前景圖標**: 108x108 dp (432x432 px @ xxxhdpi)
- **背景**: 108x108 dp，支援形狀裁剪

## SVG 圖標文件

### 1. tram_icon_minimal.svg (48x48)
- **用途**: mdpi 密度，最小尺寸要求
- **特點**: 極簡化設計，清晰可辨識
- **適用**: 低密度設備，節省資源

### 2. tram_icon_medium.svg (96x96)
- **用途**: hdpi 和 xhdpi 密度
- **特點**: 中等複雜度，平衡細節和性能
- **適用**: 中等密度設備

### 3. tram_icon_high.svg (144x144)
- **用途**: xxhdpi 密度
- **特點**: 高密度設計，豐富細節
- **適用**: 高密度設備

### 4. tram_icon_android.svg (192x192)
- **用途**: xxxhdpi 密度，主要圖標
- **特點**: 完整設計，最佳視覺效果
- **適用**: 高密度設備，主要圖標

### 5. tram_icon_foreground_android.svg (108x108)
- **用途**: Android 自適應圖標前景
- **特點**: 居中設計，適合形狀裁剪
- **適用**: Android 8.0+ 自適應圖標

## 原始圖標文件

### PNG 格式
- `tram_icon.png` (1024x1024) - 主要圖標
- `tram_icon_foreground.png` - 前景圖標

### SVG 格式
- `tram_icon.svg` (1024x1024) - 原始 SVG
- `tram_icon_foreground.svg` - 原始前景 SVG
- `tram_icon_simple.svg` - 簡化版本

## 使用建議

### 開發階段
1. 使用 SVG 文件進行設計和調整
2. 根據需要選擇合適的複雜度版本
3. 測試在不同密度設備上的顯示效果

### 生產階段
1. 使用 `flutter_launcher_icons` 自動生成所有密度
2. 確保自適應圖標正確配置
3. 驗證在所有目標設備上的顯示效果

### 性能優化
1. 低密度設備使用簡化版本
2. 高密度設備使用完整版本
3. 自適應圖標使用專門設計的前景版本

## 技術規格

### 顏色方案
- **主色**: #1976D2 (Material Blue)
- **次要色**: #FFC107 (Material Amber)
- **強調色**: #FF9800 (Material Orange)
- **背景色**: #F67C0F (自適應圖標背景)

### 設計原則
- **可擴展性**: 所有圖標都支援無損縮放
- **清晰度**: 在小尺寸下仍保持清晰可辨
- **一致性**: 統一的設計語言和視覺風格
- **平台適配**: 針對不同平台進行專門優化

## 維護說明

### 更新圖標
1. 修改對應的 SVG 文件
2. 重新生成 PNG 文件
3. 更新 `pubspec.yaml` 配置
4. 運行 `flutter pub run flutter_launcher_icons:main`

### 版本控制
- 保留所有版本的 SVG 文件
- 記錄重要的設計變更
- 維護圖標的歷史版本

## 相關文檔
- [Android 圖標設計指南](https://developer.android.com/guide/practices/ui_guidelines/icon_design)
- [Flutter 圖標配置](https://pub.dev/packages/flutter_launcher_icons)
- [Material Design 圖標指南](https://material.io/design/iconography/)
