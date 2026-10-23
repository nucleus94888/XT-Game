# 工具管線（iOS 優先）

原則：只接「第一刀」需要的最小工具組，其餘「被實際卡住才裝」。全部免費，除了 Apple 開發者計畫本身。

## 現況總表

| 環節 | 用什麼 | 狀態 | 費用 |
| --- | --- | --- | --- |
| 引擎 | Godot 4.7.2（GL Compatibility 渲染器，Web / iOS 同一套） | 已裝在 `C:\Users\Win\tools\godot\`，匯出範本已裝 | 免費 |
| 手感調校 | 遊戲內面板（`game_feel.gd` + `tuning_panel.gd`），五組盲選預設、存檔、複製數值 | 完成 | — |
| 觸控操作 | 自製浮動搖桿 + 兩鍵（`touch_controls.gd`），桌機滑鼠模擬觸控 | 完成 | — |
| 音效 | Kenney「Impact Sounds」「RPG Audio」（CC0，直接下載免登入），`sfx.gd` 用 AudioStreamRandomizer 隨機變化與音高 | 24 個檔，288 KB | 免費，免標註 |
| 圖示 | 程式繪製 PNG（`tools/icons/gen.mjs`，1024/512/180/144） | 完成 | 免費 |
| 中文字型 | Noto Sans TC（OFL）子集化成 203 KB（`tools/fonts/subset.py`，需 `pip install fonttools`） | 完成 | 免費 |
| 自動試玩截圖 | `--autoplay --shot=` 參數（`main.gd`），AI 可自己看畫面 | 完成 | — |
| iPhone 上測試（免費路徑） | Web 匯出 → GitHub Pages → iPhone Safari 開 → 加入主畫面 | `web.yml`，push 到 main 自動部署 | 免費 |
| iOS 原生建置 | GitHub Actions **macOS 執行器**（公開倉庫免費）跑 Godot 匯出 + xcodebuild | `ios.yml` 的 `simulator` 工作，每次 push 自動驗證 | 免費 |
| iOS 真機 / TestFlight / App Store | `ios.yml` 的 `testflight` 工作（手動觸發） | 管線已寫好，**等 Apple 帳號與憑證** | Apple 開發者計畫 US$99/年 |
| Android | Godot 內建匯出 APK/AAB | 依你的指示先不做 | Google Play 一次性 US$25 |

## 為什麼 Windows 也能做 iOS

iOS 的編譯、簽章、上傳只能在 macOS + Xcode 上做。你的電腦是 Windows 10，所以我們用 GitHub Actions 提供的 macOS 虛擬機當「雲端 Mac」。
這個倉庫是公開的，GitHub 對公開倉庫的 macOS 執行器**不收費**。流程：

```
Windows 寫碼 → git push → GitHub 的 Mac：下載 Godot → 匯出 Xcode 專案 → xcodebuild → (簽章) → TestFlight
```

每次 push 都會跑「模擬器建置」：不需要任何 Apple 帳號，證明整條路通。產物（`Hanzo-simulator.app.zip`）可在任何一台 Mac 的 Xcode 模擬器上執行。

## 要上 iPhone 真機或 TestFlight，你需要做的事（一次性）

沒有付 US$99 的話，從 Windows **完全沒有辦法**把 app 裝進 iPhone（免費 Apple ID 的 7 天側載也要一台實體 Mac 插線）。
所以真機之前，先用 Safari 版測手感；決定要走下去再付。

1. **加入 Apple Developer Program**（US$99/年）：https://developer.apple.com/programs/enroll/ 。完成後記下 **Team ID**（10 碼）。
2. **建立 App ID**：Certificates, Identifiers & Profiles → Identifiers → + → App IDs → Bundle ID 填 `com.nucleus94888.hanzo`（已寫在 `hanzo/export_presets.cfg`）。
3. **建立發佈憑證（不需要 Mac）**：
   ```
   bash tools/ios/make-csr.sh "你的名字" your@email.com
   ```
   把產生的 `.csr` 上傳到 Certificates → + → Apple Distribution，下載 `distribution.cer` 放到 `tools/ios/secrets/`，再：
   ```
   bash tools/ios/make-p12.sh
   ```
   會印出 `APPLE_CERT_PASSWORD` 與 `APPLE_CERT_P12_BASE64`。
4. **建立 Provisioning Profile**：Profiles → + → App Store Connect → 選上面的 App ID 與憑證 → 下載 `.mobileprovision`。
   `base64 -w0 xxx.mobileprovision` 的輸出就是 `APPLE_PROFILE_BASE64`。
5. **App Store Connect API 金鑰**：https://appstoreconnect.apple.com → 使用者與存取 → 整合 → App Store Connect API → + （權限 App Manager）。
   記下 **Key ID**、**Issuer ID**，下載 `.p8`；`base64 -w0 AuthKey_XXXX.p8` 就是 `APPLE_API_KEY_P8_BASE64`。
6. **在 App Store Connect 建立 App**：我的 App → + → 平台 iOS、名稱「半藏 HANZO」、Bundle ID 選 `com.nucleus94888.hanzo`。
7. **把 7 個 Secrets 填進 GitHub**：倉庫 → Settings → Secrets and variables → Actions → New repository secret：

   | Secret | 內容 |
   | --- | --- |
   | `APPLE_TEAM_ID` | 10 碼 Team ID |
   | `APPLE_CERT_P12_BASE64` | 步驟 3 印出的 |
   | `APPLE_CERT_PASSWORD` | 步驟 3 印出的（預設 `hanzo-ios`） |
   | `APPLE_PROFILE_BASE64` | 步驟 4 |
   | `APPLE_API_KEY_ID` | 步驟 5 |
   | `APPLE_API_ISSUER_ID` | 步驟 5 |
   | `APPLE_API_KEY_P8_BASE64` | 步驟 5 |

8. 倉庫 → Actions → 「iOS（雲端 Mac 建置）」→ Run workflow → 勾選 testflight → Run。
   幾分鐘後在 iPhone 的 TestFlight app 就能裝。

這 8 步只有第 1 步要錢，其餘都在瀏覽器與 Git Bash 完成，不需要 Mac。你告訴我「帳號開好了」，我可以陪你逐步做 2–8。

## 日常流程

```
改程式 → 本機跑 Godot 看 → git push →
  web.yml  約 3 分鐘 → https://nucleus94888.github.io/XT-Game/ 在 iPhone Safari 重新整理
  ios.yml  約 8 分鐘 → Actions 頁看「模擬器建置」綠勾（證明 iOS 編得過）
```

## 之後才裝的東西（被卡住才裝）

- **Blender + Mixamo**：等灰盒手感確認「爽」之後，再換真人型角色與動作。Mixamo 需 Adobe 帳號（免費）在瀏覽器操作，我無法代勞下載。
- **Android SDK**：你說先不做。Godot 匯出 Android 需要 Android Studio 的 SDK + JDK 17，裝好後 `export_presets.cfg` 加一個 Android 預設即可。
- **LLM 對白 / TTS**：第二階段（地圖變任務生成器）才需要。
- **商店素材（截圖、宣傳圖）**：有東西可截的時候。

## 資料來源與授權

- Godot Engine：MIT。
- Noto Sans TC：SIL Open Font License 1.1。
- 音效：Kenney（CC0 1.0，公共領域），`hanzo/audio/kenney/LICENSE-kenney-CC0.txt`。
- 圖示、角色、場景：程式產生。
