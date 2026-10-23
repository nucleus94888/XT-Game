# 半藏 HANZO

以服部半藏為主角的動作冒險遊戲。目前是「手感切片」階段：**一個半藏、一個稻草人、一刀**，
唯一驗收標準是「砍下去爽不爽」。引擎 Godot 4.7.2（免費、開源），目標平台 iOS 優先、Android 之後。

- 線上試玩（iPhone Safari 直接開，可「加入主畫面」變全螢幕）：https://nucleus94888.github.io/XT-Game/
- 工具管線與 iOS 上架流程：[PIPELINE.md](PIPELINE.md)
- 之前的戰國大戰略版本：封存在 `strategy-archive` 分支，沒有刪除。
- 兩次 LLM Council 的報告與逐字稿：`docs/council/`

## 操作

| 動作 | 觸控 | 鍵盤 |
| --- | --- | --- |
| 移動 | 左 60% 畫面任意處按住拖曳（浮動搖桿） | WASD / 方向鍵 |
| 斬（三段連斬，收刀過半可接下一段） | 右下「斬」 | J / Space |
| 閃步（無敵，可取消前置與收刀） | 右下「閃」 | K / Shift |
| 手感調校面板 | 右上「手感調校」 | P / Tab |

稻草人 1.5 秒內連吃三刀會出現「！」然後橫掃反擊，用閃步躲。HP 歸零會倒下、1.2 秒後重生。

## 三天驗收流程

1. 打開面板，**先不要看數字**，輪流按「甲・利落 / 乙・沉重 / 丙・流暢 / 丁・電影 / 戊・無料」各砍一分鐘。
2. 挑最爽的一組，再拖滑桿微調；感覺對了按「儲存」。
3. 按「複製數值」把那組參數貼回來給 AI，AI 把它固定成正式預設。
4. 第三天晚上在 iPhone 上砍：爽 → 進第二階段（地圖翻轉成任務生成器）；不爽 → 回 `strategy-archive` 補回饋感，兩週內不再改方向。

## 本機開發

```
# Godot 4.7.2 已安裝在 C:\Users\Win\tools\godot\，雙擊 Godot_v4.7.2-stable_win64.exe → 匯入 hanzo/project.godot
# 或命令列直接跑：
C:\Users\Win\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path hanzo

# 自動試玩 + 截圖（AI 用來看畫面）
C:\Users\Win\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path hanzo ++ --shot=C:/Users/Win/Desktop/XT-Game/build/shots --autoplay

# 重新產生音效 / 圖示 / 字型子集
npm run assets
```

## 目錄

```
hanzo/            Godot 專案（遊戲本體）
  scenes/main.tscn
  scripts/        game_feel.gd（手感參數中心）、player.gd、dummy.gd、camera_rig.gd、touch_controls.gd、hud.gd、tuning_panel.gd、fx.gd
  audio/synth/    為砍稻草人專門合成的音效（tools/sfx/gen.mjs：破風、砍進乾草、稻草爆開）
  audio/kenney/   Kenney CC0 音效（木樁、衣物、受傷），sfx.gd 隨機變化
  icons/          程式繪製圖示（tools/icons/gen.mjs）
  fonts/ui.otf    Noto Sans TC 子集（tools/fonts/subset.py）
  export_presets.cfg  Web 與 iOS 匯出設定
tools/            資產產生器、iOS 憑證工具
.github/workflows web.yml（→ GitHub Pages）、ios.yml（雲端 Mac：模擬器建置 / TestFlight）
docs/council/     LLM Council 報告
```
