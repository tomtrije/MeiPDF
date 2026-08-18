# 发布指南（MeiPDF）

MeiPDF 通过 GitHub Actions 自动打包 DMG 并发布。本文件说明两种模式、所需 Secrets，以及
本地等价操作。

---

## 两种分发模式

| 模式 | 场景 | 用户怎么装 | 自动更新 |
|------|------|------------|----------|
| **无证书（ad-hoc）** | 自用 / 内部 | 双击 DMG 内 `install.command` 解除隔离，或 `sudo xattr -rd com.apple.quarantine /Applications/MeiPDF.app` | 不可用（需签名 appcast） |
| **Developer ID 签名 + 公证** | 正式对外 | 拖进「应用程序」直接打开（`install.command` 无害） | 可用（需 `SPARKLE_EDKEY`） |

两种模式由仓库 Secrets 是否齐全决定，**同一套 workflow 自动适配**，缺密钥不会报错，只是降级为 ad-hoc。

---

## 本地构建/打包命令

```bash
swift package resolve
bash Scripts/build-app.sh        # 产出 MeiPDF.app
bash Scripts/build-dmg.sh        # 产出 Distribution/MeiPDF-x.y.z.dmg
```

- 签名切换：设 `SIGN_IDENTITY` 即用 Developer ID 签名（带 `--options runtime`，公证必需），不设则 ad-hoc。
- 版本号：脚本自动取最近 git tag（去 `v`），否则 `1.0.0`；也可用 `MEIPDF_VERSION=x.y.z` 覆盖。

---

## GitHub 自动发布

推送 tag 即触发 `.github/workflows/release.yml`：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

流程：解析版本 → 缓存 SwiftPM → 构建 `.app`（嵌入 Sparkle）→ 打包 DMG →
（有证书）签名 + 公证 →（有 `SPARKLE_EDKEY`）生成签名 appcast → 建 Release 并上传 DMG + appcast.xml。

`ci.yml` 在 PR / main 推送时仅编译，不发包。

---

## 需要的 Secrets（Settings → Secrets and variables → Actions）

### 仅做签名 + 公证（让 DMG 不被 Gatekeeper 拦截）
| Secret | 内容 |
|--------|------|
| `MACOS_SIGNING_CERT` | Developer ID Application 的 `.p12` 做 base64：`base64 -i cert.p12` |
| `MACOS_SIGNING_CERT_PASSWORD` | 该 `.p12` 的密码 |
| `APPLE_ID` | 你的 Apple ID 邮箱 |
| `APPLE_APP_PASSWORD` | 专用密码（appleid.apple.com → 安全 → 生成 App 专用密码） |
| `APPLE_TEAM_ID` | 10 位团队 ID |

### 还要启用自动更新（Sparkle）
| Secret | 内容 |
|--------|------|
| `SPARKLE_EDKEY` | 本地 `Secrets/ed25519_private.key` 的**文件内容**（一串 base64 seed） |

> 密钥**永远不要**提交进仓库。`Secrets/` 已在 `.gitignore` 中忽略。

---

## 生成 / 轮换 Sparkle 密钥（本地，需 openssl）

```bash
# 1. 生成（PEM 为主密钥，base64 seed 供 Sparkle 工具消费）
openssl genpkey -algorithm ed25519 -out Secrets/ed25519_private.pem
openssl pkey -in Secrets/ed25519_private.pem -outform DER | tail -c 32 | base64 -b 0 > Secrets/ed25519_private.key

# 2. 导出公钥填进 Resources/Info.plist 的 SUPublicEDKey
openssl pkey -in Secrets/ed25519_private.pem -pubout -outform DER | tail -c 32 | base64 -b 0
```

密钥轮换后，旧的已发布版本无法再自动更新到新签名版本，需重新下载安装。

---

## 本地等价一键发布

```bash
bash Scripts/release.sh
```

它会：build-dmg → 用 `Secrets/ed25519_private.key` 生成签名 appcast → `gh release create` 上传 DMG + appcast.xml。
要求已 `gh auth login` 且密钥存在。
