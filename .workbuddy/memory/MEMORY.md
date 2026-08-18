# MeiPDF 项目长期笔记

## 项目定位
原生 macOS PDF 浏览器，Swift 6 + SwiftUI + PDFKit。聚焦**浏览体验**与**打印**，明确不做编辑功能。
目标：macOS 14 (Sonoma)+，无 Xcode 依赖（SwiftPM + build-app.sh）。

## 架构要点
- 单一 `AppState`（`@MainActor @Observable`）持有所有打开的 `DocumentState` 与偏好。
- 所有可观察模型类（`AppState` / `DocumentState` / `Preferences`）必须 `@MainActor`：本 SDK 的 `PDFView` 属性是 main-actor isolated，否则报 actor 隔离错误。
- PDF 渲染用 `NSViewRepresentable` 桥接 `PDFView` 子类 `MeiPDFView`；标注拖拽在该子类里用 `MainActor.assumeIsolated` 访问主线程状态。
- 标注**非破坏性**：存于 Application Support/MeiPDF 的 sidecar JSON，按 `path|size|mtime` 哈希作为 fileID（`MetaStore`）。

## 编译/打包关键坑（Command Line Tools SDK, MacOSX26.5）
1. 编译必须 `--disable-sandbox`。
2. `NSPrintInfo` 无 `duplex`/`duplexing` → 用 `printSettings["NSPrintDuplexing"] = 0/1/2`。
3. PDFKit API：翻页用 `go(to:)`（非 `goToPage`）；`thumbnail(of:for:)` 返回非 Optional；`quadrilateralPoints` 要 `[NSValue]`；annotation subtype 是 `String?`。
4. bundle 用 `codesign --force --deep --sign -` 自签名，避免 Gatekeeper 拦截。

## 验证局限
本环境无 GUI，无法启动 app 做交互测试。验证仅限 `swift build` 通过 + `MeiPDF.app` 结构正确（已 ad-hoc 签名）。

## 未实现（决策已过，未落地）
- DMG 打包 + Sparkle 自动更新（产品方案已确认，脚本未写）。
