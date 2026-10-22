import './ui/style.css';
import { setLang, getLang } from './i18n';
import { App } from './ui/App';

async function boot() {
  const lang = getLang();
  if (lang !== 'zh-TW') await setLang(lang);
  const root = document.getElementById('app')!;
  const app = new App(root);
  (window as unknown as { __app: App }).__app = app; // 開發 / 自動測試用
  // 開發用：?faction=oda&seed=1 直接開局
  const q = new URLSearchParams(location.search);
  const f = q.get('faction');
  if (f) {
    const { createGame, officersIn, regionsOf, totalTroops } = await import('./core/state');
    const state = createGame(Number(q.get('seed') ?? 1), f as never);
    state.flags.devSkipIntro = true;
    if (q.get('guide')) { state.flags.guide = true; state.flags.guideStep = Number(q.get('guide')) || 0; state.flags.devSkipIntro = !q.get('intro'); }
    if (q.get('battle')) {
      // 開發用：立刻對相鄰敵區出陣並進入戰鬥
      const { cmdMarch, marchTargets } = await import('./systems/military');
      const { endTurn } = await import('./systems/turn');
      const home = regionsOf(state, state.player)[0];
      const target = marchTargets(state, state.player, home.id)[0];
      const ids = officersIn(state, home.id, state.player).slice(0, 3).map(o => o.id);
      cmdMarch(state, state.player, home.id, target, ids, Math.round(totalTroops(home) * 0.8));
      endTurn(state);
    }
    app.startFrom(state);
  }
}
boot();
