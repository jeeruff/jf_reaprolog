-- jf_pm_browser.lua
-- JF Project Manager: браузер проектов (ReaImGui).
-- Запуск по хоткею из Action List, в фоне не висит.
-- Читает ТОЛЬКО индекс (jf_pm_index.json); Rescan пересобирает индекс
-- парсингом .rpp как текста — проекты не открываются.

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
ImGui.Attach(ctx, font)

-- ---------------------------------------------------------------------------

local state = {
  index = core.load_index(),
  scan_paths = core.get_scan_paths_str(),
  filter_status = 0,        -- 0 активные, 1 все, 2 без отчёта, дальше статусы
  filter_tag = '',
  sort_mode = 1,            -- 1 дата, 2 статус, 3 длительность, 4 имя
  expanded = nil,           -- path раскрытой карточки
  status_msg = '',
  show_settings = false,
}

local SORT_LABELS = 'по дате\0по статусу\0по длительности\0по имени\0'

local STATUS_ORDER = {}
for i, s in ipairs(core.STATUSES) do STATUS_ORDER[s] = i end

local function status_filter_labels()
  local items = { 'активные', 'все', 'без отчёта' }
  for _, s in ipairs(core.STATUSES) do items[#items + 1] = s end
  items[#items + 1] = 'без статуса'
  return table.concat(items, '\0') .. '\0'
end
local STATUS_FILTER_LABELS = status_filter_labels()

local function fmt_duration(sec)
  if not sec or sec <= 0 then return '—' end
  return string.format('%d:%02d', math.floor(sec / 60), math.floor(sec % 60))
end

local function fmt_date(ts)
  if not ts or ts == 0 then return '—' end
  return os.date('%d.%m.%y %H:%M', ts)
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
    elseif f >= 3 and f <= 2 + #core.STATUSES then
      ok = meta.status == core.STATUSES[f - 2]
    elseif f == 3 + #core.STATUSES then
      ok = meta.status == ''
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

local function draw_settings()
  ImGui.SeparatorText(ctx, 'Настройки')
  ImGui.Text(ctx, 'Директории проектов (через ;):')
  ImGui.SetNextItemWidth(ctx, -80)
  local changed, val = ImGui.InputText(ctx, '##paths', state.scan_paths)
  if changed then state.scan_paths = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'OK##paths') then
    core.set_scan_paths_str(state.scan_paths)
    state.show_settings = false
    state.status_msg = 'Пути сохранены'
  end
  ImGui.Separator(ctx)
end

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

  if card.render_file ~= '' then
    ImGui.TextDisabled(ctx, 'Рендер: ' .. card.render_file)
  end
  ImGui.TextDisabled(ctx, card.path)
end

local function draw_card(entry, card_w)
  local card, meta = entry.card, entry.meta
  local expanded = state.expanded == card.path
  local h = expanded and 0 or 132  -- 0 = авто-высота по контенту

  local child_flags = ImGui.ChildFlags_Border
  if expanded then
    child_flags = child_flags | ImGui.ChildFlags_AutoResizeY
  end
  if ImGui.BeginChild(ctx, card.path, card_w, h, child_flags) then
    ImGui.Text(ctx, card.name)

    local color = core.STATUS_COLORS[meta.status]
    local stage = core.PIPELINE[meta.status]
    if stage then
      -- прогресс по пайплайну: ●●○○ = «в работе»
      ImGui.SameLine(ctx)
      local dots = string.rep('●', stage) .. string.rep('○', core.PIPELINE_STEPS - stage)
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, dots)
    end
    if meta.status ~= '' then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, meta.status)
    end
    if card.needs_report then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, '· без отчёта')
    end

    ImGui.TextDisabled(ctx, fmt_date(card.mtime) .. '   ' ..
      fmt_duration(card.duration) .. '   ' .. (#card.regions) .. ' рег.')

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

  if ImGui.IsItemHovered(ctx) then
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      open_project(card.path)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
      state.expanded = expanded and nil or card.path
    end
  end
end

local function draw_toolbar()
  if ImGui.Button(ctx, 'Rescan') then rescan() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'пути') then state.show_settings = not state.show_settings end

  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 140)
  local changed, val = ImGui.Combo(ctx, 'фильтр', state.filter_status, STATUS_FILTER_LABELS)
  if changed then state.filter_status = val end

  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 150)
  changed, val = ImGui.Combo(ctx, 'сортировка', state.sort_mode - 1, SORT_LABELS)
  if changed then state.sort_mode = val + 1 end

  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 140)
  changed, val = ImGui.InputTextWithHint(ctx, '##tag', 'тег…', state.filter_tag)
  if changed then state.filter_tag = val end

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
end

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 940, 640, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'JF — проекты', true)
  if visible then
    draw_toolbar()
    if state.show_settings then draw_settings() end
    ImGui.Separator(ctx)

    local cards = collect_cards()
    if #cards == 0 then
      ImGui.TextDisabled(ctx, 'Пусто. Rescan, или ослабь фильтры.')
    else
      local avail = ImGui.GetContentRegionAvail(ctx)
      local card_w = 290
      local cols = math.max(1, math.floor(avail / (card_w + 8)))
      for i, entry in ipairs(cards) do
        if (i - 1) % cols ~= 0 then ImGui.SameLine(ctx) end
        draw_card(entry, card_w)
      end
    end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
