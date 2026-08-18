# MeiPDF

原生 macOS PDF 浏览器，基于 **SwiftUI + PDFKit**，聚焦**浏览与打印**，不做编辑。
不需要 Xcode —— 用 SwiftPM + 自写脚本即可编译出可运行的 `.app`，并支持 Sparkle 自动更新。

> 目标系统：macOS 14 (Sonoma) 及以上。

---

## 目录结构

```
MeiPDF/
├── Package.swift / Package.resolved     # SwiftPM 工程定义
├── README.md                            # 本文件（项目主文档）
├── .gitignore
├── Sources/MeiPDF/                     # 源码（SwiftPM target 入口，内部按职责分子目录）
│   ├── App/      MeiPDFApp / AppState / Updater      （App 入口、全局状态、Sparkle 更新器）
│   ├── Models/   Models / MetaStore / DocumentState  （数据模型、元数据、单文档状态）
│   ├── Views/    ContentView / Sidebar / Toolbar / PasswordSheet / PreferencesView / PrintSheet
│   ├── PDF/      PDFViewWrapper                     （PDFKit 桥接 + 标注拖拽）
│   └── Printing/ Printing                           （打印视图 + 打印控制）
├── Resources/
│   └── Info.plist                     # 资源：被打包进 .app 的 Info.plist
├── Scripts/                          # 构建 / 分发脚本（均从项目根目录操作）
│   ├── version.sh                    #   版本号解析（tag > 环境变量 > 1.0.0）
│   ├── build-app.sh                  #   编译 + 产出 MeiPDF.app（嵌入 Sparkle、注入版本、签名）
│   ├── build-dmg.sh                  #   打包 DMG 到 Distribution/
│   └── release.sh                    #   本地等价发布：build-dmg + 签名 appcast + 建 GitHub Release
├── Distribution/                     # 本地出包产物（gitignore，不入库）
│   ├── Installer/                    #   打进 DMG 的自用安装辅助
│   │   ├── install.command           #     双击移除 Gatekeeper 隔离并安装到 /Applications
│   │   └── README.txt                #     DMG 内快速说明
│   └── （生成物：MeiPDF-x.y.z.dmg、appcast.xml、临时 staging）
├── Secrets/                          # 本地密钥（gitignore，绝不入库）
│   └── ed25519_private.{key,pem}     #   Sparkle 自动更新签名私钥
├── Docs/
│   └── RELEASE.md                    # 发布 / 签名 / 公证 / Secrets 配置指南
└── .github/workflows/                # CI/CD
    ├── release.yml                   #   推送 v* tag 自动构建 DMG 并发布（可选签名+公证+appcast）
    └── ci.yml                        #   PR / main 上保证可编译
```

---

## 快速开始（本地）

需要 macOS 与 Command Line Tools（`xcode-select --install`）。无需完整 Xcode。

```bash
# 1. 解析依赖（Sparkle）
swift package resolve

# 2. 编译并产出 .app
bash Scripts/build-app.sh
open MeiPDF.app

# 3. 打包 DMG（含自用安装脚本）
bash Scripts/build-dmg.sh
# 产物在 Distribution/MeiPDF-x.y.z.dmg
```

### 没证书（自用）
下载/打开 DMG 后，双击里面的 **`install.command`**（或在终端执行
`sudo xattr -rd com.apple.quarantine /Applications/MeiPDF.app`），即可解除 Gatekeeper 隔离正常打开。
详见 DMG 内的 `README.txt`。

### 有 Developer ID 证书（正式发行）
在仓库配置 Secrets 后由 `release.yml` 自动签名 + 公证；本地也可：
```bash
SIGN_IDENTITY="Developer ID Application: <你的名称> (TEAMID)" bash Scripts/build-dmg.sh
```
此时 `install.command` 无害，直接拖进「应用程序」即可。

---

## 自动更新（Sparkle）
`SUFeedURL` 指向 `releases/latest/download/appcast.xml`。每次发版都会把签名后的
`appcast.xml` 作为 release 资产上传，自动更新即可生效（需要 Secrets 中配置 `SPARKLE_EDKEY`）。

---

## 发布（GitHub Actions）
推送一个版本 tag 即触发自动构建与发布：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

无 Secrets 时仍会产出 **ad-hoc DMG**（别人下载需走上面的「没证书」流程）；
配齐证书与密钥后则自动完成 Developer ID 签名、公证、签名 appcast。
完整配置见 [Docs/RELEASE.md](Docs/RELEASE.md)。
