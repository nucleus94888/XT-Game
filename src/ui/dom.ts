// 極簡 DOM 建構工具
type Child = Node | string | number | null | undefined | false | Child[];

export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K, attrs: Record<string, unknown> | null = null, ...children: Child[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (attrs) for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') el.className = String(v);
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v as EventListener);
    else if (k === 'html') el.innerHTML = String(v);
    else if (k in el && typeof v !== 'string') (el as unknown as Record<string, unknown>)[k] = v;
    else el.setAttribute(k, String(v));
  }
  append(el, children);
  return el;
}

function append(el: Node, children: Child[]) {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else if (c instanceof Node) el.appendChild(c);
    else el.appendChild(document.createTextNode(String(c)));
  }
}

export function clear(el: Element): void { while (el.firstChild) el.removeChild(el.firstChild); }

export function fmt(n: number): string { return Math.round(n).toLocaleString(); }

/** 數值條 */
export function bar(value: number, max = 100, cls = ''): HTMLElement {
  return h('div', { class: `bar ${cls}` }, h('div', { class: 'bar-fill', style: { width: `${Math.max(0, Math.min(100, value / max * 100))}%` } }));
}

/** 短暫提示 */
let toastTimer: number | undefined;
export function toast(msg: string, ok = true): void {
  let el = document.getElementById('toast');
  if (!el) { el = h('div', { id: 'toast' }); document.body.appendChild(el); }
  el.textContent = msg;
  el.className = ok ? 'show' : 'show err';
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => { el!.className = ''; }, 2200);
}

/** 模態對話框，回傳所選 index */
export function modal(title: string, body: Child, buttons: string[], opts: { danger?: number } = {}): Promise<number> {
  return new Promise(resolve => {
    const overlay = h('div', { class: 'modal-overlay' });
    const box = h('div', { class: 'modal' },
      h('div', { class: 'modal-title' }, title),
      h('div', { class: 'modal-body' }, body),
      h('div', { class: 'modal-buttons' }, buttons.map((b, i) => h('button', {
        class: i === opts.danger ? 'btn danger' : i === 0 ? 'btn primary' : 'btn',
        onClick: () => { overlay.remove(); resolve(i); },
      }, b))),
    );
    overlay.appendChild(box);
    document.body.appendChild(overlay);
  });
}

/** 滑桿輸入 */
export function slider(min: number, max: number, value: number, onChange: (v: number) => void): HTMLElement {
  const label = h('span', { class: 'slider-value' }, fmt(value));
  const input = h('input', { type: 'range', min, max, value, step: Math.max(1, Math.round((max - min) / 200)) });
  input.addEventListener('input', () => { label.textContent = fmt(+input.value); onChange(+input.value); });
  const quick = h('div', { class: 'slider-quick' }, [0.25, 0.5, 0.75, 1].map(p => h('button', { class: 'btn tiny', onClick: () => {
    input.value = String(Math.round(min + (max - min) * p)); label.textContent = fmt(+input.value); onChange(+input.value);
  } }, `${p * 100}%`)));
  return h('div', { class: 'slider' }, h('div', { class: 'slider-row' }, input, label), quick);
}
