# 戰國 XT

日本戰國時期大戰略遊戲。three.js + Vite + TypeScript，手機優先，和風水墨視覺。
設計文件見 [GAME_DESIGN.md](GAME_DESIGN.md)。

## 開發

```bash
npm install
npm run dev        # http://localhost:5173（手機測試：npx vite --host）
npm run build      # 輸出到 dist/
npm run preview
```

## 工具

```bash
npx tsc --noEmit -p .                 # 型別檢查
npx tsx tools/sim.ts <seed> <years> <faction>   # 無頭模擬：AI 對 AI 跑 N 年，檢查平衡
npx tsx tools/rtsim.ts [場數]          # 即時戰鬥 vs 回合制戰鬥的勝率 / 時長校準
npx tsx tools/geo/build-geo.ts        # 由 tools/geo/japan.topojson 重新產生 src/data/geo.ts（來源見下）
npx tsx tools/shot.ts http://localhost:5180 [name]   # 無頭截圖（手機直/橫式、桌機、戰鬥、引導）
# 開發伺服器啟動後：
#   /tools/kamon-preview.html      18 個家徽預覽
#   /tools/render-preview.html     地圖 / 戰場場景預覽
```

## 結構

```
src/
  core/      types、state（建立新局、查詢）、rng、save
  data/      regions（19 區屬性與相鄰）、geo（19 區真實地形多邊形與邊界，自動產生）、factions、officers（131 武將）、techs、kamon（SVG 家徽）
  systems/   commands（內政）、military、battle（回合制結算，AI 用）、rtbattle（即時戰鬥）、advisor（軍師引導）、diplomacy、ninja、turn（月結算）、ai、events、modifiers
  render/    MapScene、BattleScene、ink（水墨風材質）
  ui/        App（控制器）、panels（分頁）、BattleView、dom、silhouette、style.css
  i18n/      zh-TW（主）、ja、en
tools/       sim.ts（無頭模擬）、預覽頁
```

遊戲邏輯（core + systems）完全不依賴 DOM / three.js，可在 Node 以 `tsx` 直接執行。

## 資料來源

地圖輪廓來自國土地理院「地球地図日本」（經 [dataofjapan/land](https://github.com/dataofjapan/land) 轉換為 TopoJSON），
下載 `https://raw.githubusercontent.com/dataofjapan/land/master/japan.topojson` 到 `tools/geo/` 後即可重新產生。依其授權，使用時須標示出處。
