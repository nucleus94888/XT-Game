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
# 開發伺服器啟動後：
#   /tools/kamon-preview.html      18 個家徽預覽
#   /tools/render-preview.html     地圖 / 戰場場景預覽
```

## 結構

```
src/
  core/      types、state（建立新局、查詢）、rng、save
  data/      regions（18 區）、factions（18 勢力）、officers（131 武將）、techs、kamon（SVG 家徽）
  systems/   commands（內政）、military、battle、diplomacy、ninja、turn（月結算）、ai、events、modifiers
  render/    MapScene、BattleScene、ink（水墨風材質）
  ui/        App（控制器）、panels（分頁）、BattleView、dom、silhouette、style.css
  i18n/      zh-TW（主）、ja、en
tools/       sim.ts（無頭模擬）、預覽頁
```

遊戲邏輯（core + systems）完全不依賴 DOM / three.js，可在 Node 以 `tsx` 直接執行。
