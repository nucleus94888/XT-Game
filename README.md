# 半藏 HANZO

以服部半藏為主角的動作冒險遊戲。目前是「手感切片」階段：**一個半藏、一個稻草人、一刀**，
唯一驗收標準是「砍下去爽不爽」。引擎 Godot 4.7.2（免費、開源），目標平台 iOS 優先、Android 之後。

- 線上試玩（iPhone Safari 直接開，可「加入主畫面」變全螢幕）：https://nucleus94888.github.io/XT-Game/
- 工具管線與 iOS 上架流程：[PIPELINE.md](PIPELINE.md)
- 之前的戰國大戰略版本：封存在 `strategy-archive` 分支，沒有刪除。
- 兩次 LLM Council 的報告與逐字稿：`docs/council/`

## 第一關：伊賀夜襲

標題畫面選「第一關」。山門 → 第一院（足輕×2 巡邏、弓兵×1）→ 窄道 → 第二院（武士巡邏）→ 小屋裡的目標武將（背對門）。
暗殺武將後回南邊山門撤離，結算時間、擊破、暗殺數、被擊中與被發現次數，評價 影 / S / A / B / C。

- 敵人有視野錐與視線遮蔽：頭上白條是警覺度，「？」起疑、「！」發現並呼叫 10 公尺內同伴。出刀有聲音，5 公尺內的敵人會起疑。
- 未察覺的敵人從背後砍 = **暗殺**，一擊必殺、無聲。
- 足輕：長槍，成群；弓兵：保持距離射箭，箭可格擋不可彈反，用閃步躲；武士／武將：會架刀擋輕攻擊，用重擊（第三段）或彈反破防；體幹崩壞後一刀忍殺。
- 敵人失去你的蹤影會到最後看到／聽到的位置搜索幾秒再回巡邏；手裡劍打在地上的聲響會把守衛引過去。
- 熄掉燈籠後站在暗處，敵人視野縮短四成。
- 擊倒敵人有機率掉落「忍者口糧」，走過去回 35 HP（目標武將必掉）。
- 死亡可「再來一次」。

## 操作

| 動作 | 觸控 | 鍵盤 |
| --- | --- | --- |
| 移動（相對鏡頭） | 左 60% 畫面任意處按住拖曳（浮動搖桿） | WASD / 方向鍵 |
| 轉視角 | 右側空白處拖曳 | Q / E |
| 攻擊（三段連斬，收刀過半可接下一段） | 右下「攻擊」 | J / Space |
| 閃步（無敵，可取消前置與收刀） | 右下「閃」 | K / Shift |
| 格擋（按住，隻狼式架刀；舉刀後 220 毫秒內擋下＝彈反，對方後仰、體幹 +35） | 右側「格擋」（按住） | L / Ctrl |
| 投手裡劍（自動瞄準鏡頭前方最近敵人；打地面引開守衛、打燈籠熄燈、打斷弓兵）／有鉤繩點時變「鉤」飛上屋頂 | 右側「投／鉤」 | U / F |
| 落下忍殺 | 從屋頂落下時按攻擊，對下方未察覺的敵人一擊必殺 | J |
| 手感調校面板 | 右上「手感調校」 | P / Tab |

稻草人靠近時每 2.8 秒、或 1.5 秒內連吃三刀，會出現「！」然後橫掃，用閃步躲或在它揮出的瞬間格擋彈反。
頭上黃條是「體幹」：被砍、被彈反都會累積，滿了就「體幹崩壞」硬直 2.5 秒，期間任何一刀都是「忍殺」一擊必殺。HP 歸零或忍殺後倒下、1.2 秒後重生。

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

# 重新產生圖示 / 字型子集
npm run assets
```

## 目錄

```
hanzo/            Godot 專案（遊戲本體）
  scenes/main.tscn
  scripts/        game_feel.gd（手感參數中心）、player.gd、dummy.gd、camera_rig.gd、touch_controls.gd、hud.gd、tuning_panel.gd、fx.gd
  audio/mixkit/   Mixkit 免費授權刀劍音效（揮空、砍中），tools/sfx/prep.mjs 裁切整理
  audio/kenney/   Kenney CC0 音效（木樁、衣物、受傷）；sfx.gd 直接播 WAV 走低延遲取樣模式
  icons/          程式繪製圖示（tools/icons/gen.mjs）
  fonts/ui.otf    Noto Sans TC 子集（tools/fonts/subset.py）
  export_presets.cfg  Web 與 iOS 匯出設定
tools/            資產產生器、iOS 憑證工具
.github/workflows web.yml（→ GitHub Pages）、ios.yml（雲端 Mac：模擬器建置 / TestFlight）
docs/council/     LLM Council 報告
```
