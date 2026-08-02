-- jf_pm_browser.lua
-- JF PM: браузер проектов (ReaImGui).
-- Запуск по хоткею из Action List, в фоне не висит.
-- Читает ТОЛЬКО индекс (jf_pm_index.json); Rescan пересобирает индекс
-- парсингом .rpp как текста — проекты не открываются.
--
-- Эргономика: без слайдеров и выпадашек — всё чипами в ширину, не в глубину.
-- Vim-навигация: h/j/k/l — фокус по карточкам, Enter — раскрыть (в таймлайне —
-- открыть), o — открыть проект, / — в поле тега, Esc — свернуть/сброс,
-- g/G — в начало/конец.

local SCRIPT_PATH = ({reaper.get_action_context()})[2]
local SCRIPT_DIR = SCRIPT_PATH:match('^(.*)[/\\]')
local core = dofile(SCRIPT_DIR .. '/jf_pm_core.lua')

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Нужен ReaImGui 0.9+ (ReaPack: ReaImGui: ReaScript binding for Dear ImGui).',
    'JF PM', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

local ctx = ImGui.CreateContext('JF PM')
local font = ImGui.CreateFont('sans-serif', 14)
local big_font = ImGui.CreateFont('sans-serif', 44) -- для иероглифов-тамбнейлов
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, big_font)

-- ---------------------------------------------------------------------------

local state = {
  index = core.load_index(),
  scan_paths = core.get_setting('scan_paths'),
  stems_path = core.get_setting('stems_path'),
  regions_path = core.get_setting('regions_path'),
  thumb_style = tonumber(core.get_setting('thumb_style')) or 0, -- 0 калейдоскоп, 1 иероглиф
  view = 0,                 -- 0 сетка, 1 таймлайн, 2 календарь
  filter_status = 0,        -- 0 активные, 1 все, 2 без отчёта, 3.. статусы
  filter_tag = '',
  sort_mode = 1,            -- 1 дата, 2 статус, 3 длительность, 4 имя
  expanded = nil,           -- path раскрытой карточки
  focus = 0,                -- индекс карточки в фокусе (vim), 0 = нет
  scroll_to_focus = false,
  focus_tag_input = false,
  status_msg = '',
  show_settings = false,
}

local STATUS_ORDER = {}
for i, s in ipairs(core.STATUSES) do STATUS_ORDER[s] = i end

local SORT_CHIPS = { 'дата', 'статус', 'длительность', 'имя' }
local VIEW_CHIPS = { 'сетка', 'таймлайн', 'календарь' }

-- радикалы Канси для тамбнейлов-иероглифов
local RADICALS = {
  '山','川','水','火','木','金','土','日','月','風','雨','雷','雲','雪','氷',
  '龍','鳥','魚','馬','鹿','虫','鬼','心','手','足','目','耳','口','骨','血',
  '人','女','子','母','父','老','鼓','音','言','歌','舞','弓','刀','矛','斧',
  '門','戶','井','田','里','谷','林','森','岩','石','沙','泉','海','波','潮',
  '光','影','闇','夜','夢','霧','煙','灰','炎','燈','星','空','天','地','原',
  '花','草','竹','米','麥','豆','瓜','桑','梅','蘭','菊','苔','根','葉','實',
  '絲','網','布','衣','革','皮','角','爪','牙','羽','毛','殼','壺','皿','鼎',
}

local function fmt_duration(sec)
  if not sec or sec <= 0 then return '—' end
  return string.format('%d:%02d', math.floor(sec / 60), math.floor(sec % 60))
end

local function fmt_date(ts)
  if not ts or ts == 0 then return '—' end
  return os.date('%d.%m.%y %H:%M', ts)
end

local function fmt_size(bytes)
  if not bytes or bytes <= 0 then return '?' end
  if bytes >= 1048576 then return string.format('%.1f МБ', bytes / 1048576) end
  return string.format('%d КБ', math.max(1, math.floor(bytes / 1024)))
end

local function trunc(s, n)
  local len = utf8.len(s)
  if len and len > n then
    return s:sub(1, utf8.offset(s, n + 1) - 1) .. '…'
  end
  return s
end

local function fnv1a(str)
  local h = 2166136261
  for i = 1, #str do
    h = ((h ~ str:byte(i)) * 16777619) & 0xFFFFFFFF
  end
  return h
end

local function hash_color(h, s, v)
  local r, g, b = ImGui.ColorConvertHSVtoRGB((h % 360) / 360, s or 0.5, v or 0.92)
  return ImGui.ColorConvertDouble4ToU32(r, g, b, 1.0)
end

local function all_tags(card, meta)
  local seen, out = {}, {}
  for _, t in ipairs(meta.tags) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  for _, t in ipairs(card.fs_tags or {}) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  return out
end

-- ---------------------------------------------------------------------------

local function collect_cards()
  local cards = {}
  for _, card in pairs(state.index.projects) do
    local meta = core.card_meta(card)
    local ok = true
    local f = state.filter_status
    if f == 0 then
      ok = meta.status ~= 'архив'
    elseif f == 2 then
      ok = card.needs_report or meta.report_ts == 0
    elseif f >= 3 then
      ok = meta.status == core.STATUSES[f - 2]
    end
    if ok and state.filter_tag ~= '' then
      local needle = state.filter_tag:lower()
      ok = false
      for _, t in ipairs(all_tags(card, meta)) do
        if t:lower():find(needle, 1, true) then ok = true break end
      end
    end
    if ok then cards[#cards + 1] = { card = card, meta = meta } end
  end

  local m = state.sort_mode
  table.sort(cards, function(a, b)
    -- проекты без отчёта всплывают наверх при любой сортировке
    local na = a.card.needs_report and 1 or 0
    local nb = b.card.needs_report and 1 or 0
    if na ~= nb then return na > nb end
    if m == 2 then
      local oa = STATUS_ORDER[a.meta.status] or 99
      local ob = STATUS_ORDER[b.meta.status] or 99
      if oa ~= ob then return oa < ob end
    elseif m == 3 then
      if (a.card.duration or 0) ~= (b.card.duration or 0) then
        return (a.card.duration or 0) > (b.card.duration or 0)
      end
    elseif m == 4 then
      if a.card.name:lower() ~= b.card.name:lower() then
        return a.card.name:lower() < b.card.name:lower()
      end
    end
    if (a.card.mtime or 0) ~= (b.card.mtime or 0) then
      return (a.card.mtime or 0) > (b.card.mtime or 0)
    end
    return a.card.name < b.card.name
  end)
  return cards
end

local function rescan()
  local paths = core.get_scan_paths()
  if #paths == 0 then
    state.status_msg = 'Укажи директории проектов (кнопка «пути»)'
    state.show_settings = true
    return
  end
  local t0 = reaper.time_precise()
  state.index = core.build_index(paths, state.index)
  core.save_index(state.index)
  local n = 0
  for _ in pairs(state.index.projects) do n = n + 1 end
  state.status_msg = string.format('Rescan: %d проектов за %.1f c', n,
    reaper.time_precise() - t0)
end

local function open_project(path)
  reaper.Main_OnCommand(40859, 0) -- New project tab
  reaper.Main_openProject(path)
end

-- ---------------------------------------------------------------------------
-- Тамбнейлы

local img_cache = {}
local function get_image(path)
  local img = img_cache[path]
  if img == nil then
    local ok, res = pcall(ImGui.CreateImage, path)
    img = ok and res or false
    if img then ImGui.Attach(ctx, img) end
    img_cache[path] = img
  end
  return img or nil
end

local function draw_thumb(card, size)
  -- своя картинка: jf_thumb.png/jpg в папке проекта
  if card.thumb_file then
    local img = get_image(card.thumb_file)
    if img then
      ImGui.Image(ctx, img, size, size)
      return
    end
  end
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + size, y0 + size, 0x161616FF, 4)
  local h = fnv1a(card.path)
  if state.thumb_style == 1 then
    -- радикал, детерминированный от пути проекта
    local glyph = RADICALS[h % #RADICALS + 1]
    local col = hash_color(h % 360, 0.45, 0.95)
    local fs = size * 0.68
    ImGui.DrawList_AddTextEx(dl, big_font, fs,
      x0 + size * 0.16, y0 + size * 0.13, col, glyph)
  else
    -- 8-битный калейдоскоп: четверть 4x4 из хеша, зеркалим по обеим осям
    local cell = size / 8
    local col1 = hash_color(h % 360, 0.55, 0.95)
    local col2 = hash_color((h >> 8) % 360, 0.35, 0.65)
    for y = 0, 7 do
      for x = 0, 7 do
        local qx = x < 4 and x or 7 - x
        local qy = y < 4 and y or 7 - y
        local bit_i = qy * 4 + qx
        if (h >> bit_i) & 1 == 1 then
          local c = ((h >> ((bit_i + 16) % 32)) & 1) == 1 and col1 or col2
          ImGui.DrawList_AddRectFilled(dl,
            x0 + x * cell, y0 + y * cell,
            x0 + (x + 1) * cell, y0 + (y + 1) * cell, c)
        end
      end
    end
  end
  ImGui.Dummy(ctx, size, size)
end

-- ---------------------------------------------------------------------------
-- Сетка карточек

local function draw_card_details(card, meta)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format('%s BPM · %d/%d · %d трек(ов)',
    card.tempo and tostring(card.tempo) or '—',
    card.timesig_num or 4, card.timesig_den or 4, card.track_count or 0))

  if meta.desc ~= '' then
    ImGui.TextWrapped(ctx, meta.desc)
  end

  if #card.regions > 0 then
    ImGui.TextDisabled(ctx, 'Структура:')
    for _, r in ipairs(card.regions) do
      ImGui.BulletText(ctx, string.format('%s  [%s – %s]',
        r.name ~= '' and r.name or '(без имени)',
        fmt_duration(r.pos), fmt_duration(r.fin)))
    end
  end

  if #card.track_names > 0 then
    ImGui.TextDisabled(ctx, 'Треки:')
    local named = {}
    for _, n in ipairs(card.track_names) do
      named[#named + 1] = n ~= '' and n or '(без имени)'
    end
    ImGui.TextWrapped(ctx, table.concat(named, ', '))
  end

  if meta.report_done ~= '' or meta.report_todo ~= '' then
    ImGui.TextDisabled(ctx, 'Отчёт (' .. fmt_date(meta.report_ts) .. '):')
    if meta.report_done ~= '' then
      ImGui.TextWrapped(ctx, 'Сделано: ' .. meta.report_done)
    end
    if meta.report_todo ~= '' then
      ImGui.TextWrapped(ctx, 'Дальше: ' .. meta.report_todo)
    end
  else
    ImGui.TextDisabled(ctx, 'Отчёта нет')
  end

  -- скрытая ветка: бэкапы (свёрнута по умолчанию)
  local backups = card.backups or {}
  if #backups > 0 then
    if ImGui.TreeNode(ctx, string.format('Бэкапы (%d)###bak', #backups)) then
      for _, b in ipairs(backups) do
        ImGui.BulletText(ctx, string.format('%s — %s, %s',
          b.file, fmt_date(b.mtime), fmt_size(b.size)))
      end
      ImGui.TreePop(ctx)
    end
  end

  if card.render_file ~= '' then
    ImGui.TextDisabled(ctx, 'Рендер: ' .. card.render_file)
  end
  ImGui.TextDisabled(ctx, card.path)
  if ImGui.SmallButton(ctx, 'свернуть') then state.expanded = nil end
end

local function draw_card(entry, i, card_w)
  local card, meta = entry.card, entry.meta
  local expanded = state.expanded == card.path
  local focused = state.focus == i
  local h = expanded and 0 or 138  -- 0 = авто-высота по контенту

  local child_flags = ImGui.ChildFlags_Border
  if expanded then
    child_flags = child_flags | ImGui.ChildFlags_AutoResizeY
  end
  if focused then
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xE8E8E8FF)
  end
  if ImGui.BeginChild(ctx, card.path, card_w, h, child_flags) then
    draw_thumb(card, 64)
    ImGui.SameLine(ctx)
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, trunc(card.name, 22))

    local color = core.STATUS_COLORS[meta.status]
    local stage = core.PIPELINE[meta.status]
    if stage then
      -- прогресс по пайплайну: ●●○○ = «в работе»
      local dots = string.rep('●', stage) ..
                   string.rep('○', core.PIPELINE_STEPS - stage)
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, dots)
      ImGui.SameLine(ctx)
    end
    if meta.status ~= '' then
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, meta.status)
    else
      ImGui.TextDisabled(ctx, '—')
    end
    if card.needs_report then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, '· без отчёта')
    end

    ImGui.TextDisabled(ctx, fmt_date(card.mtime))
    ImGui.TextDisabled(ctx, fmt_duration(card.duration) .. '   ' ..
      (#card.regions) .. ' рег.')
    ImGui.EndGroup(ctx)

    -- следующий шаг из последнего отчёта — открытая петля снаружи головы
    local next_action = meta.report_todo:match('^[^\n]+')
    if next_action then
      ImGui.TextColored(ctx, 0xD9B96CFF, '→ ' .. next_action)
    end

    local tags = all_tags(card, meta)
    if #tags > 0 then
      ImGui.TextWrapped(ctx, '# ' .. table.concat(tags, '  # '))
    end

    if expanded then draw_card_details(card, meta) end
    ImGui.EndChild(ctx)
  end
  if focused then
    ImGui.PopStyleColor(ctx)
    if state.scroll_to_focus then
      ImGui.SetScrollHereY(ctx, 0.5)
      state.scroll_to_focus = false
    end
  end

  if ImGui.IsItemHovered(ctx) then
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      open_project(card.path)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not expanded then
      state.expanded = card.path
      state.focus = i
    end
  end
end

local function draw_grid(cards)
  if #cards == 0 then
    ImGui.TextDisabled(ctx, 'Пусто. Rescan, или ослабь фильтры.')
    return 1
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local card_w = 300
  local cols = math.max(1, math.floor(avail / (card_w + 8)))
  for i, entry in ipairs(cards) do
    if (i - 1) % cols ~= 0 then ImGui.SameLine(ctx) end
    draw_card(entry, i, card_w)
  end
  return cols
end

-- ---------------------------------------------------------------------------
-- Таймлайн: строка на проект, бар от старейшего бэкапа до последнего изменения

local TIMELINE_SPAN = 183 * 86400 -- полгода

local function draw_timeline(cards)
  if #cards == 0 then
    ImGui.TextDisabled(ctx, 'Пусто. Rescan, или ослабь фильтры.')
    return
  end
  local now = os.time()
  local min_t = now - TIMELINE_SPAN
  local label_w = 180
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local plot_w = math.max(100, avail_w - label_w - 10)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- ось месяцев
  local ax, ay = ImGui.GetCursorScreenPos(ctx)
  local t = os.date('*t', min_t)
  t.day, t.hour, t.min, t.sec = 1, 12, 0, 0
  local mt = os.time(t)
  while mt < now do
    if mt >= min_t then
      local x = ax + label_w + (mt - min_t) / TIMELINE_SPAN * plot_w
      ImGui.DrawList_AddLine(dl, x, ay, x, ay + 14, 0x3A3A3AFF)
      ImGui.DrawList_AddText(dl, x + 3, ay, 0x777777FF, os.date('%m.%y', mt))
    end
    local nt = os.date('*t', mt)
    nt.month = nt.month + 1
    mt = os.time(nt)
  end
  ImGui.Dummy(ctx, avail_w, 16)

  for i, entry in ipairs(cards) do
    local card, meta = entry.card, entry.meta
    local rx, ry = ImGui.GetCursorScreenPos(ctx)
    ImGui.Selectable(ctx, '##tl' .. i, state.focus == i, 0, 0, 18)
    if state.focus == i and state.scroll_to_focus then
      ImGui.SetScrollHereY(ctx, 0.5)
      state.scroll_to_focus = false
    end
    if ImGui.IsItemHovered(ctx) then
      local next_action = meta.report_todo:match('^[^\n]+') or ''
      ImGui.SetTooltip(ctx, card.name ..
        (meta.status ~= '' and ('  [' .. meta.status .. ']') or '') ..
        (next_action ~= '' and ('\n→ ' .. next_action) or ''))
      if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
        open_project(card.path)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
        state.focus = i
      end
    end

    ImGui.DrawList_AddText(dl, rx, ry + 1, 0xCCCCCCFF, trunc(card.name, 24))

    local t1 = card.mtime or now
    local t0 = t1
    local bks = card.backups or {}
    if #bks > 0 then
      t0 = bks[#bks].mtime or t1 -- отсортированы по убыванию, хвост — старейший
    end
    if t0 > t1 then t0 = t1 end
    if t1 >= min_t then
      t0 = math.max(t0, min_t)
      local bx0 = rx + label_w + (t0 - min_t) / TIMELINE_SPAN * plot_w
      local bx1 = rx + label_w + (t1 - min_t) / TIMELINE_SPAN * plot_w
      if bx1 - bx0 < 3 then bx0 = bx1 - 3 end
      local col = core.STATUS_COLORS[meta.status] or 0x8A8A8AFF
      ImGui.DrawList_AddRectFilled(dl, bx0, ry + 4, bx1, ry + 15, col, 2)
    else
      ImGui.DrawList_AddText(dl, rx + label_w, ry + 1, 0x555555FF,
        'старше полугода')
    end
  end
end

-- ---------------------------------------------------------------------------
-- Календарь: тепловая карта активности (mtime, отчёты, бэкапы) за 26 недель

local function day_key(ts)
  local d = os.date('*t', ts)
  d.hour, d.min, d.sec = 0, 0, 0
  return os.time(d)
end

local function draw_calendar(cards)
  local DAY = 86400
  local now = os.time()
  local act = {}
  local function mark(ts, name)
    if not ts or ts == 0 then return end
    local key = day_key(ts)
    local a = act[key]
    if not a then a = { n = 0, names = {} } act[key] = a end
    if not a.names[name] then
      a.names[name] = true
      a.n = a.n + 1
    end
  end
  for _, e in ipairs(cards) do
    mark(e.card.mtime, e.card.name)
    mark(e.meta.report_ts, e.card.name)
    for _, b in ipairs(e.card.backups or {}) do mark(b.mtime, e.card.name) end
  end

  local WEEKS = 26
  local cell, gap = 16, 3
  local wd = (os.date('*t', now).wday + 5) % 7 -- 0 = понедельник
  local monday = day_key(now) - wd * DAY
  local start = monday - (WEEKS - 1) * 7 * DAY

  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  y0 = y0 + 16 -- место под метки месяцев
  local dl = ImGui.GetWindowDrawList(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local hover_key, hover_act
  local prev_month = ''
  for w = 0, WEEKS - 1 do
    for d = 0, 6 do
      local ts = start + (w * 7 + d) * DAY + DAY / 2
      if ts > now + DAY then break end
      local key = day_key(ts)
      local cx = x0 + w * (cell + gap)
      local cy = y0 + d * (cell + gap)
      local a = act[key]
      local col = 0x1B1B1BFF
      if a then
        col = a.n >= 3 and 0xE8E8E8FF or (a.n == 2 and 0x9A9A9AFF or 0x5C5C5CFF)
      end
      ImGui.DrawList_AddRectFilled(dl, cx, cy, cx + cell, cy + cell, col, 2)
      if mx >= cx and mx < cx + cell and my >= cy and my < cy + cell then
        hover_key, hover_act = key, a
      end
      if d == 0 then
        local m = os.date('%m', ts)
        if m ~= prev_month then
          ImGui.DrawList_AddText(dl, cx, y0 - 16, 0x777777FF, os.date('%m.%y', ts))
          prev_month = m
        end
      end
    end
  end
  ImGui.Dummy(ctx, WEEKS * (cell + gap), 7 * (cell + gap) + 18)
  ImGui.TextDisabled(ctx,
    'активность = сохранения, бэкапы, отчёты · ярче — больше проектов за день')
  if hover_key then
    local txt = os.date('%d.%m.%Y', hover_key + 3600)
    if hover_act then
      local names = {}
      for n in pairs(hover_act.names) do names[#names + 1] = n end
      table.sort(names)
      txt = txt .. '\n' .. table.concat(names, '\n')
    end
    ImGui.SetTooltip(ctx, txt)
  end
end

-- ---------------------------------------------------------------------------
-- Тулбар и настройки: всё чипами, без выпадашек

local function chip(label, active)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, active and 0x3D3D3DFF or 0x1E1E1EFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, active and 0xFFFFFFFF or 0x9A9A9AFF)
  local clicked = ImGui.SmallButton(ctx, label)
  ImGui.PopStyleColor(ctx, 2)
  return clicked
end

local function draw_settings()
  ImGui.SeparatorText(ctx, 'Пути')
  local changed, val

  ImGui.Text(ctx, 'Проекты (через ;):')
  ImGui.SetNextItemWidth(ctx, -1)
  changed, val = ImGui.InputText(ctx, '##paths', state.scan_paths)
  if changed then state.scan_paths = val end

  ImGui.Text(ctx, 'Расслоение → мультитреки:')
  ImGui.SetNextItemWidth(ctx, -1)
  changed, val = ImGui.InputText(ctx, '##stems', state.stems_path)
  if changed then state.stems_path = val end

  ImGui.Text(ctx, 'Расслоение → регионы:')
  ImGui.SetNextItemWidth(ctx, -1)
  changed, val = ImGui.InputText(ctx, '##regions', state.regions_path)
  if changed then state.regions_path = val end

  ImGui.Text(ctx, 'Тамбнейлы:')
  ImGui.SameLine(ctx)
  if chip('калейдоскоп', state.thumb_style == 0) then state.thumb_style = 0 end
  ImGui.SameLine(ctx)
  if chip('иероглиф', state.thumb_style == 1) then state.thumb_style = 1 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, 'или jf_thumb.png в папке проекта')

  if ImGui.Button(ctx, 'Сохранить настройки') then
    core.set_setting('scan_paths', state.scan_paths)
    core.set_setting('stems_path', state.stems_path)
    core.set_setting('regions_path', state.regions_path)
    core.set_setting('thumb_style', tostring(state.thumb_style))
    state.show_settings = false
    state.status_msg = 'Настройки сохранены'
  end
  ImGui.Separator(ctx)
end

local function draw_toolbar()
  if ImGui.Button(ctx, 'Rescan') then rescan() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'пути') then state.show_settings = not state.show_settings end

  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, label in ipairs(VIEW_CHIPS) do
    ImGui.SameLine(ctx)
    if chip(label, state.view == i - 1) then
      state.view = i - 1
      state.focus = 0
    end
  end

  -- WIP-счётчик: >3 в работе — многовато, внимание расползается
  local wip, no_report = 0, 0
  for _, card in pairs(state.index.projects) do
    local s = (card.ext or {}).STATUS or ''
    if s == 'в работе' or s == 'к миксу' then wip = wip + 1 end
    if card.needs_report then no_report = no_report + 1 end
  end
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, wip > 3 and 0xE06060FF or 0x8A8A8AFF,
    string.format('WIP: %d', wip))
  if no_report > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xE06060FF, string.format('без отчёта: %d', no_report))
  end
  if state.status_msg ~= '' then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, state.status_msg)
  end

  -- ряд фильтров
  if chip('активные', state.filter_status == 0) then state.filter_status = 0 end
  ImGui.SameLine(ctx)
  if chip('все', state.filter_status == 1) then state.filter_status = 1 end
  ImGui.SameLine(ctx)
  if chip('без отчёта', state.filter_status == 2) then state.filter_status = 2 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, s in ipairs(core.STATUSES) do
    ImGui.SameLine(ctx)
    if chip(s, state.filter_status == i + 2) then state.filter_status = i + 2 end
  end

  -- ряд сортировки + тег
  ImGui.TextDisabled(ctx, 'сорт:')
  for i, s in ipairs(SORT_CHIPS) do
    ImGui.SameLine(ctx)
    if chip(s, state.sort_mode == i) then state.sort_mode = i end
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  if state.focus_tag_input then
    ImGui.SetKeyboardFocusHere(ctx)
    state.focus_tag_input = false
  end
  local changed, val = ImGui.InputTextWithHint(ctx, '##tag', 'тег… ( / )', state.filter_tag)
  if changed then state.filter_tag = val end
end

-- ---------------------------------------------------------------------------
-- Vim-навигация

local function handle_keys(cards, cols)
  if ImGui.IsAnyItemActive(ctx) then return end -- набор текста в поле
  if not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
    return
  end
  local n = #cards
  if n == 0 then return end
  local moved = false
  local step_h = state.view == 0 and 1 or 0
  local step_v = state.view == 0 and cols or 1

  local function move(delta)
    local f = state.focus
    if f == 0 then
      f = 1
    else
      f = f + delta
      if f < 1 then f = 1 end
      if f > n then f = n end
    end
    state.focus = f
    moved = true
  end

  if ImGui.IsKeyPressed(ctx, ImGui.Key_J) then move(step_v) end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_K) then move(-step_v) end
  if step_h > 0 then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_L) then move(step_h) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_H) then move(-step_h) end
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_G) then
    if ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift ~= 0 then
      state.focus = n
    else
      state.focus = 1
    end
    moved = true
  end
  if moved then state.scroll_to_focus = true end

  local entry = state.focus > 0 and cards[state.focus] or nil
  if entry then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if state.view == 0 then
        state.expanded = state.expanded ~= entry.card.path and entry.card.path or nil
      else
        open_project(entry.card.path)
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_O) then
      open_project(entry.card.path)
    end
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Slash) then
    state.focus_tag_input = true
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    if state.expanded then
      state.expanded = nil
    else
      state.focus = 0
    end
  end
end

-- ---------------------------------------------------------------------------

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 980, 660, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'JF — проекты', true)
  if visible then
    draw_toolbar()
    if state.show_settings then draw_settings() end
    ImGui.Separator(ctx)

    local cards = collect_cards()
    local cols = 1
    if state.view == 0 then
      cols = draw_grid(cards)
    elseif state.view == 1 then
      draw_timeline(cards)
    else
      draw_calendar(cards)
    end
    handle_keys(cards, cols)
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
