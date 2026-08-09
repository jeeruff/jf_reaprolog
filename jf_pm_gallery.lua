-- jf_pm_gallery.lua
-- Экспорт текущего вида браузера в автономный HTML: навигатор-тамбнейлы
-- рисуются на canvas тем же алгоритмом, что draw_thumb (оттенок — fnv1a
-- пути + номер трека, поэтому цвета совпадают с ImGui). Файл самодостаточен,
-- его можно кинуть кому угодно; только ручные превью — file://, они видны
-- лишь на этой машине.

local M = {}

local function fnv1a(str)
  local h = 2166136261
  for i = 1, #str do
    h = ((h ~ str:byte(i)) * 16777619) & 0xFFFFFFFF
  end
  return h
end

local TEMPLATE = [==[<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>JF PM — галерея проектов</title>
<style>
  :root {
    --ground: #111213; --card: #1a1b1d; --border: #2a2c2e;
    --text: #cfd2d4; --muted: #8a8f93; --accent: #d9b96c;
  }
  html { background: var(--ground); }
  body {
    font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif;
    color: var(--text); background: var(--ground);
    margin: 0; padding: 28px clamp(16px, 4vw, 48px) 64px;
  }
  header { margin-bottom: 22px; }
  h1 { font-size: 17px; font-weight: 600; margin: 0 0 6px; }
  .sub { color: var(--muted); font-size: 12.5px; }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 10px;
  }
  .card {
    display: flex; gap: 12px; background: var(--card);
    border: 1px solid var(--border); border-radius: 6px;
    padding: 12px; min-width: 0;
  }
  .card canvas, .card img.thumb {
    border-radius: 4px; flex: none;
    width: 128px; height: 128px; object-fit: cover;
  }
  .info { min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .name {
    font-weight: 600; font-size: 13.5px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .status { font-size: 12px; }
  .next { color: var(--accent); font-size: 12px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .meta {
    color: var(--muted); font-size: 12px;
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-variant-numeric: tabular-nums;
  }
  .tags { color: var(--muted); font-size: 11.5px; margin-top: auto;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  footer { margin-top: 26px; color: var(--muted); font-size: 12px; max-width: 62ch; }
</style>
</head>
<body>
<header>
  <h1>JF PM — галерея проектов</h1>
  <div class="sub" id="stats"></div>
</header>
<div class="grid" id="grid"></div>
<footer>
  Строка — трек, горизонталь — время в масштабе длительности проекта.
  Снято с индекса jf_pm; сгенерировано кнопкой «галерея» в браузере проектов.
</footer>
<script>
const DATA = /*__DATA__*/;

function hsv(h, s, v) {
  const i = Math.floor(h * 6), f = h * 6 - i;
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  const [r, g, b] = [[v,t,p],[q,v,p],[p,v,t],[p,q,v],[t,p,v],[v,p,q]][i % 6];
  return `rgb(${r*255|0},${g*255|0},${b*255|0})`;
}

function drawNav(canvas, card, size) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = size * dpr;
  canvas.height = size * dpr;
  const g = canvas.getContext('2d');
  g.scale(dpr, dpr);
  g.fillStyle = '#161616';
  g.fillRect(0, 0, size, size);
  const tracks = Math.max(card.tracks, 1);
  const row = size / tracks;
  for (const it of card.items) {
    let x0 = (it.p / card.dur) * size;
    let x1 = Math.min(x0 + (it.l / card.dur) * size, size);
    if (x1 - x0 < 1) x1 = x0 + 1;
    g.fillStyle = hsv(((card.h + it.t * 53) % 360) / 360, 0.5, 0.85);
    g.fillRect(x0, (it.t - 1) * row + 0.5, x1 - x0, Math.max(1, row - 1));
  }
  // полоса регионов внизу; hue (r.h) посчитан в Lua от имени региона
  for (const r of card.regions || []) {
    let x0 = Math.max(r.p / card.dur, 0) * size;
    let x1 = Math.min(r.f / card.dur, 1) * size;
    if (x1 - x0 < 1) x1 = x0 + 1;
    g.fillStyle = hsv((r.h % 360) / 360, 0.6, 0.9);
    g.fillRect(x0, size - 4, x1 - x0, 4);
  }
  // лупы — янтарные скобки сверху (координаты — секунды проекта)
  if (card.dur > 0) {
    for (const lp of card.loops || []) {
      let x0 = Math.max(lp.a / card.dur, 0) * size;
      let x1 = Math.min(lp.b / card.dur, 1) * size;
      if (x1 - x0 < 1) x1 = x0 + 1;
      g.fillStyle = 'rgba(217,185,108,0.85)';
      g.fillRect(x0, 0, x1 - x0, 4);
    }
  }
  // плашка DAW в углу
  if (card.daw) {
    g.font = 'bold 11px system-ui';
    const tw = g.measureText(card.daw.l).width;
    g.fillStyle = card.daw.col;
    g.fillRect(2, size - 18, tw + 8, 16);
    g.fillStyle = '#111213';
    g.fillText(card.daw.l, 6, size - 6);
  }
}

const fmtDur = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const fmtSize = b => !b ? '?' :
  b >= 1073741824 ? (b / 1073741824).toFixed(1) + ' ГБ' :
  b >= 1048576 ? (b / 1048576).toFixed(1) + ' МБ' :
  Math.max(1, b / 1024 | 0) + ' КБ';

const grid = document.getElementById('grid');
for (const card of DATA.cards) {
  const el = document.createElement('div');
  el.className = 'card';
  const thumb = card.thumb
    ? `<img class="thumb" src="file://${encodeURI(card.thumb)}" alt="">`
    : '<canvas></canvas>';
  el.innerHTML = `${thumb}
    <div class="info">
      <div class="name"></div>
      <div class="status"></div>
      <div class="next"></div>
      <div class="meta">${card.mtime} · ${fmtDur(card.dur)}</div>
      <div class="meta">${card.tracks} трк · ${card.n_items} айт · ${fmtSize(card.size)}${card.loops ? ' · ⟲' + card.loops.length : ''}</div>
      <div class="tags"></div>
    </div>`;
  el.querySelector('.name').textContent = card.name;
  const st = el.querySelector('.status');
  st.textContent = card.status || '—';
  if (card.scol) st.style.color = card.scol;
  el.querySelector('.next').textContent = card.next ? '→ ' + card.next : '';
  el.querySelector('.tags').textContent =
    card.tags && card.tags.length ? '# ' + card.tags.join('  # ') : '';
  grid.appendChild(el);
  const cv = el.querySelector('canvas');
  if (cv) drawNav(cv, card, 128);
}
document.getElementById('stats').textContent =
  `${DATA.cards.length} проектов · ${DATA.generated}`;
</script>
</body>
</html>
]==]

-- entries — [{card, meta}] из collect_cards() браузера (фильтры и сортировка
-- уже применены). Возвращает true либо nil, err.
function M.export(core, entries, out_path)
  local cards = {}
  for _, e in ipairs(entries) do
    local c, meta = e.card, e.meta
    local scol = core.STATUS_COLORS[meta.status]
    cards[#cards + 1] = {
      name = c.name,
      h = fnv1a(c.path),
      tracks = c.track_count or 1,
      dur = c.duration or 0,
      mtime = os.date('%d.%m.%y', c.mtime or 0),
      size = c.dir_size or 0,
      n_items = #(c.items or {}),
      items = c.items or {},
      regions = (function()
        local out = {}
        for _, r in ipairs(c.regions or {}) do
          out[#out + 1] = {
            p = r.pos, f = r.fin,
            h = fnv1a(r.name ~= '' and r.name or '?'),
          }
        end
        return out
      end)(),
      status = meta.status,
      scol = scol and string.format('#%06X', scol >> 8) or nil,
      next = meta.report_todo:match('^[^\n]+'),
      tags = meta.tags,
      thumb = c.thumb_user or c.thumb_file,
      daw = (function()
        if not c.daw then return nil end
        local dt = core.DAW_TYPES[c.daw_ext] or {}
        return { l = dt.label or '?', col = dt.color
          and string.format('#%06X', dt.color >> 8) or '#8a8f93' }
      end)(),
      loops = (function()
        -- лупы в секундах проекта (pv_offset уже скомпенсирован)
        if not c.loops or #c.loops == 0 then return nil end
        local off = c.pv_offset or 0
        local out = {}
        for _, lp in ipairs(c.loops) do
          out[#out + 1] = { a = lp.a + off, b = lp.b + off }
        end
        return out
      end)(),
    }
  end
  local json = core.json_encode({
    cards = cards,
    generated = os.date('%d.%m.%Y %H:%M'),
  })
  local html = TEMPLATE:gsub('/%*__DATA__%*/', function() return json end)
  local f, err = io.open(out_path, 'wb')
  if not f then return nil, err end
  f:write(html)
  f:close()
  return true
end

return M
